-- ======================================================================
-- ARREGLO SISTEMA DE CALIFICACIONES (spec 65)
-- ----------------------------------------------------------------
-- 1) RLS en ratings (estaba apagado: anon key leía TODO)
-- 2) Índice único: un usuario = una calificación por servicio
-- 3) Evitar auto-calificación (rater_id != rated_id)
-- 4) Políticas SELECT: conductor ve las suyas, cliente ve las suyas
-- 5) Trigger on_rating_inserted: crea driver_profiles si falta
-- ======================================================================

-- 1) Índice único: previene duplicados en BD (el cliente bloquea en UI,
--    pero la BD es la autoridad final). El índice también acelera
--    hasClientRatedService (eq en las tres columnas).
CREATE UNIQUE INDEX IF NOT EXISTS uq_ratings_service_rater_rated
  ON public.ratings (service_id, rater_id, rated_id);

-- 2) RLS en ratings
ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

-- 3) Políticas SELECT
-- Conductor ve las calificaciones QUE RECIBIÓ (rated_id = su user_id)
DROP POLICY IF EXISTS "drivers_select_own_received_ratings" ON public.ratings;
CREATE POLICY "drivers_select_own_received_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rated_id = auth.uid());

-- Cliente ve las calificaciones QUE DIO (rater_id = su user_id)
DROP POLICY IF EXISTS "customers_select_own_given_ratings" ON public.ratings;
CREATE POLICY "customers_select_own_given_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rater_id = auth.uid());

-- 4) Política INSERT reforzada (ya existía "customers_insert_own_ratings"
--    pero solo verificaba que el rater sea dueño del servicio; faltaba
--    comprobar que NO se califica a sí mismo y que el rated_id ES el
--    conductor del servicio).
DROP POLICY IF EXISTS "customers_insert_own_ratings" ON public.ratings;
CREATE POLICY "customors_insert_own_ratings" ON public.ratings
  FOR INSERT TO authenticated
  WITH CHECK (
    rater_id = auth.uid()
    AND rated_id != auth.uid()                                 -- no auto-calificación
    AND EXISTS (SELECT 1 FROM public.services
                WHERE id = service_id
                  AND customer_id = auth.uid()
                  AND driver_id = rated_id)                    -- rated_id es el conductor real
  );

-- 5) Trigger on_rating_inserted: guarda el resultado en variable y
--    crea driver_profiles si no existe (igual que en arreglo_update_service_status).
--    Así evita el error FOUND=FALSE del UPDATE anterior que rompía la tx.
DROP TRIGGER IF EXISTS trig_on_rating ON public.ratings;
DROP FUNCTION IF EXISTS public.on_rating_inserted() CASCADE;

CREATE OR REPLACE FUNCTION public.on_rating_inserted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_profiles_id uuid;
  v_ok boolean;
BEGIN
  -- Busca o crea el perfil del conductor calificado
  SELECT id INTO v_driver_profiles_id
    FROM public.driver_profiles
   WHERE user_id = NEW.rated_id;

  IF NOT FOUND THEN
    -- Perfil no existe: lo crea con valores por defecto y lo actualiza abajo
    INSERT INTO public.driver_profiles (user_id, rating, total_services, is_verified, status, availability)
    VALUES (NEW.rated_id, 0, 0, false, 'offline', 'offline')
    RETURNING id INTO v_driver_profiles_id;
  END IF;

  -- Recalcula la media y actualiza
  UPDATE public.driver_profiles
     SET rating = COALESCE((
           SELECT AVG(score)::numeric(3,2)
             FROM public.ratings
            WHERE rated_id = NEW.rated_id
         ), 0),
         updated_at = NOW()
   WHERE id = v_driver_profiles_id;

  -- Notifica al conductor (si falla, no rompemos la calificación)
  BEGIN
    PERFORM public.notify_user(
      NEW.rated_id, 'new_rating',
      'Nueva calificación',
      'Un cliente te calificó con ' || NEW.score::text || ' estrellas.',
      jsonb_build_object('service_id', NEW.service_id, 'rating', NEW.score, 'comment', NEW.comment)
    );
  EXCEPTION WHEN OTHERS THEN
    -- Ignorar: la calificación ya se guardó
  END;

  RETURN NEW;
END $$;

CREATE TRIGGER trig_on_rating
  AFTER INSERT ON public.ratings
  FOR EACH ROW EXECUTE FUNCTION public.on_rating_inserted();

-- 6) Limpieza de duplicados históricos (opcional: deja la MÁS RECIENTE)
--    Ejecutar SOLO una vez tras aplicar la migración.
WITH dup AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY service_id, rater_id, rated_id ORDER BY created_at DESC) AS rn
  FROM public.ratings
)
DELETE FROM public.ratings
WHERE id IN (SELECT id FROM dup WHERE rn > 1);

-- 7) Limpieza de auto-calificaciones históricas
DELETE FROM public.ratings WHERE rater_id = rated_id;