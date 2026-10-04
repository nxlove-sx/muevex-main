-- ===========================================================================
-- MUEVEX — Arreglo de update_service_status()
--
-- Qué le pasa
-- -----------
-- `update_service_status(uuid, text)` es la RPC con la que el conductor mueve un
-- servicio: en_recogida → en_curso → completado. Al llegar a `completado`
-- hace DOS updates dentro de la misma transacción:
--
--     UPDATE services        ... WHERE id = ... AND driver_id = auth.uid() AND status='en_curso';
--     UPDATE driver_profiles SET total_services = total_services + 1 WHERE user_id = auth.uid();
--
-- y después comprueba:
--
--     IF NOT FOUND THEN
--       RAISE EXCEPTION 'No puedes cambiar el estado de este servicio.';
--     END IF;
--
-- En plpgsql `FOUND` lo sobrescribe **cualquier** sentencia de SQL anterior. El
-- segundo update (el de `driver_profiles`) vuelve a poner FOUND a true/false
-- según haya fila o no. Si el conductor **no tiene fila en
-- `driver_profiles`**, ese segundo update no toca nada, FOUND pasa a falso, y la
-- función lanza la excepción… **después** de haber completado el servicio.
--
-- La excepción aborta la transacción, así que el `UPDATE services` se revierte
-- también: el servicio se queda en `en_curso` y el conductor recibe un error que
-- no dice nada de la fila que falta.
--
-- Consecuencia medida en la base el 02/10/2026: un conductor sin fila en
-- `driver_profiles` **no puede completar ningún servicio**, con lo cual tampoco
-- puede emitir minifactura, no le aparece nada en el historial y no le suman las
-- ganancias. Es decir: todo lo de facturas en el historial del conductor
-- dependía de este bug.
--
-- Qué hace este fichero
-- ---------------------
-- Reescribe la función para que:
--
--   1. Guarde el resultado del UPDATE de `services` en una variable propia
--      (`v_ok`) en vez de fiarse de `FOUND` más tarde. Así el segundo update no
--      puede falsear el resultado.
--   2. Que la actualización de `driver_profiles` sea inocua si no hay fila, y que
--      además **cree** la fila si falta, en lugar de dejar al conductor
--      bloqueado para siempre.
--   3. Diga qué pasa de verdad cuando el estado no se puede cambiar, en vez del
--      "No puedes cambiar el estado de este servicio." genérico: o no es suyo, o
--      el estado actual no permite esa transición.
--
-- Es idempotente: se puede correr las veces que haga falta.
--
-- Dónde: Supabase Dashboard → SQL Editor → New query → Run. O
--        `psql "$SUPABASE_DB_URL" -f docs/arreglo_update_service_status.sql`
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) update_service_status: no depender de FOUND
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_service_status(p_service_id uuid, p_status text)
RETURNS SETOF public.services
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_est         numeric;
  v_fee         numeric;
  v_actual      text;
  v_actual_driver uuid;
  v_ok          boolean := false;
BEGIN
  IF p_status NOT IN ('en_recogida','en_curso','completado', 'aceptado') THEN
    RAISE EXCEPTION 'Transición de estado no permitida.';
  END IF;

  IF p_status = 'en_recogida' THEN
    UPDATE public.services
       SET status = 'en_recogida'
     WHERE id = p_service_id AND driver_id = auth.uid() AND status = 'aceptado'
     RETURNING customer_id INTO v_customer_id;
    v_ok := FOUND;

  ELSIF p_status = 'en_curso' THEN
    UPDATE public.services
       SET status = 'en_curso', started_at = NOW()
     WHERE id = p_service_id AND driver_id = auth.uid() AND status = 'en_recogida'
     RETURNING customer_id INTO v_customer_id;
    v_ok := FOUND;

  ELSE -- 'completado'
    UPDATE public.services
       SET status = 'completado',
           completed_at = NOW(),
           final_price = COALESCE(estimated_price, price_base, 0),
           driver_earnings = COALESCE(estimated_price, price_base, 0)
                             - COALESCE(platform_fee, 0)
     WHERE id = p_service_id AND driver_id = auth.uid() AND status = 'en_curso'
     RETURNING customer_id, driver_earnings, platform_fee
       INTO v_customer_id, v_est, v_fee;
    v_ok := FOUND;

    IF v_ok THEN
      -- El contador de servicios del conductor. Antes esto se apoyaba en que
      -- hubiera fila en `driver_profiles` y, si no había, tumbaba el
      -- completado entero. Ahora se crea la fila si falta y se actualiza con
      -- `total_services + 1` sobre el valor real, para no duplicar si el
      -- completado se repite.
      UPDATE public.driver_profiles
         SET total_services = total_services + 1
       WHERE user_id = auth.uid();

      IF NOT FOUND THEN
        INSERT INTO public.driver_profiles (id, user_id, total_services)
             VALUES (auth.uid(), auth.uid(), 1)
        ON CONFLICT (id) DO NOTHING;
      END IF;
    END IF;
  END IF;

  -- El fallo se decide con `v_ok`, no con FOUND: `FOUND` a estas alturas
  -- describe el último update ejecutado (el de `driver_profiles`), no el que
  -- importa.
  IF NOT v_ok THEN
    -- Mensaje que dice la verdad: primero de quién es el servicio y luego en
    -- qué estado está. Antes era el mismo texto para los dos casos.
    SELECT status, driver_id INTO v_actual, v_actual_driver
      FROM public.services
     WHERE id = p_service_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Ese servicio no existe.';
    ELSIF v_actual_driver IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Ese servicio no es tuyo.';
    ELSE
      RAISE EXCEPTION 'No se puede pasar de "%" a "%".', v_actual, p_status;
    END IF;
  END IF;

  PERFORM public.notify_user(
    v_customer_id,
    CASE p_status
      WHEN 'en_recogida' THEN 'service_arrival'
      WHEN 'en_curso'    THEN 'service_started'
      ELSE 'service_completed'
    END,
    CASE p_status
      WHEN 'en_recogida' THEN 'Tu conductor llegó'
      WHEN 'en_curso'    THEN 'Tu servicio está en curso'
      ELSE 'Servicio completado'
    END,
    CASE p_status
      WHEN 'en_recogida' THEN 'Tu conductor ya está en el origen.'
      WHEN 'en_curso'    THEN 'Tu carga va en camino hacia el destino.'
      ELSE 'Servicio completado. Gracias por usar MUEVEX, cuenta con nosotros.'
    END,
    jsonb_build_object('service_id', p_service_id, 'status', p_status)
  );

  RETURN QUERY SELECT * FROM public.services WHERE id = p_service_id;
END $$;

-- ---------------------------------------------------------------------------
-- 2) Limpiar conductors que quedaron sin perfil
-- ---------------------------------------------------------------------------
-- La función ya no se bloquea si falta la fila, pero un conductor sin
-- `driver_profiles` tampoco aparece en los listados que la usan (capacidad,
-- vehículos, reputación). Esto deja la fila con los valores de arranque.
INSERT INTO public.driver_profiles (id, user_id, total_services)
SELECT u.id, u.id, 0
  FROM public.users u
 WHERE u.role = 'driver'
   AND NOT EXISTS (
     SELECT 1 FROM public.driver_profiles dp WHERE dp.user_id = u.id
   )
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3) Permisos (por si el fichero se corre sobre una base nueva)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regprocedure('public.update_service_status(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.update_service_status(uuid, text) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.update_service_status(uuid, text) TO authenticated;
  END IF;
END $$;

COMMIT;

-- ===========================================================================
-- Comprobaciones (verlas a ojo en el SQL Editor)
-- ===========================================================================
--  1) No debe quedar ninguna función que mire FOUND después de tocar
--     `driver_profiles`:
--       SELECT position('IF NOT FOUND' in prosrc) > 0 AS usa_found FROM
--       pg_proc WHERE proname = 'update_service_status';
--
--  2) Conductores sin perfil (debe salir 0 filas):
--       SELECT u.id, u.email FROM public.users u
--        WHERE u.role = 'driver'
--          AND NOT EXISTS (SELECT 1 FROM public.driver_profiles dp WHERE dp.user_id = u.id);
--
--  3) Probar el flujo completo con un conductor sin `driver_profiles`:
--       - aceptar el servicio     → status = aceptado
--       - update_service_status   → en_recogida
--       - update_service_status   → en_curso
--       - update_service_status   → completado   <-- aquí fallaba
-- ===========================================================================