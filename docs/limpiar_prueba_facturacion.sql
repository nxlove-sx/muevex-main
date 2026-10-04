-- ---------------------------------------------------------------------------
-- Limpieza de las pruebas de facturación
-- ---------------------------------------------------------------------------
-- Para reproducir el bug del IVA (28/09) se creó una cuenta de cliente de
-- prueba y 15 servicios con precios de sonda, más 9 facturas en 'borrador'.
-- El 02/10 se creó además una cuenta de **conductor** para probar el flujo
-- completo (pedir → aceptar → completar → minifactura) y salieron las facturas
-- FEV-000017, FEV-000018 y FEV-000019.
--
-- Nada de eso se puede borrar desde la app: RLS no permite DELETE en `services`,
-- y las facturas las escribió una función `SECURITY DEFINER` a la que la app no
-- llega.
--
-- Se borra todo de una vez, por cliente, y en el orden correcto: primero las
-- facturas (su `service_id` apunta a `services` con ON DELETE RESTRICT, así que
-- si se borran los servicios primero el borrado falla).
--
-- Es idempotente: si no hay nada que borrar no hace nada.

DO $$
DECLARE
  v_usuario UUID;
  v_conductor UUID;
  v_borrados INT := 0;
BEGIN
  -- Las cuentas de prueba se localizan por su correo, que es único.
  SELECT u.id INTO v_usuario
  FROM public.users u
  WHERE u.email = 'prueba.facturacion@muevex.test';

  IF v_usuario IS NULL THEN
    RAISE NOTICE 'No existe la cuenta de cliente de prueba: no hay nada que limpiar.';
  ELSE
    -- Las facturas del conductor de prueba las creó el cliente de prueba, así
    -- que entran por aquí. Se filtran por `customer_id` a propósito: la factura
    -- pertenece al cliente aunque la emitiera el conductor.
    DELETE FROM public.invoice_items
    WHERE invoice_id IN (
      SELECT id FROM public.invoices WHERE customer_id = v_usuario
    );
    GET DIAGNOSTICS v_borrados = ROW_COUNT;
    RAISE NOTICE 'Renglones de factura borrados: %', v_borrados;

    DELETE FROM public.invoices
    WHERE customer_id = v_usuario;
    GET DIAGNOSTICS v_borrados = ROW_COUNT;
    RAISE NOTICE 'Facturas borradas: %', v_borrados;

    DELETE FROM public.services
    WHERE customer_id = v_usuario;
    GET DIAGNOSTICS v_borrados = ROW_COUNT;
    RAISE NOTICE 'Servicios borrados: %', v_borrados;

    DELETE FROM public.customer_profiles WHERE user_id = v_usuario;
    DELETE FROM public.users WHERE id = v_usuario;
    RAISE NOTICE 'Perfil y usuario de cliente borrados.';
  END IF;

  -- El conductor de prueba. Sus servicios y facturas ya se han ido arriba
  -- (los creó el cliente de prueba), así que aquí solo queda su perfil.
  SELECT u.id INTO v_conductor
  FROM public.users u
  WHERE u.email = 'prueba.conductor@muevex.test';

  IF v_conductor IS NOT NULL THEN
    -- Por si se quedó algún servicio suyo sin cliente de prueba.
    DELETE FROM public.invoice_items
    WHERE invoice_id IN (
      SELECT id FROM public.invoices WHERE driver_id = v_conductor
    );
    DELETE FROM public.invoices WHERE driver_id = v_conductor;

    DELETE FROM public.services WHERE driver_id = v_conductor;

    DELETE FROM public.driver_profiles WHERE user_id = v_conductor;
    DELETE FROM public.driver_locations WHERE driver_id = v_conductor;
    DELETE FROM public.users WHERE id = v_conductor;
    RAISE NOTICE 'Perfil y usuario de conductor de prueba borrados.';
  END IF;

  -- Las filas de auth.users se borran aparte, desde el panel:
  -- Authentication → Users → borrar "prueba.facturacion@muevex.test" y
  -- "prueba.conductor@muevex.test".
  RAISE NOTICE
    'Falta borrar los dos usuarios de Authentication desde el panel y, si se '
    'quiere, reiniciar la secuencia de facturas.';
END;
$$;

-- La numeración de facturas ya consumió los números FEV-000001 a FEV-000019.
-- Si se quiere que la primera factura real sea la FEV-000001:
--
-- UPDATE public.invoice_sequences SET last_number = 0 WHERE prefijo = 'FEV';
--
-- Si no se hace, la primera factura real saldrá como FEV-000020, lo cual es
-- inocuo: la resolución DIAN no obliga a empezar por el 1, solo a no repetir
-- números ya emitidos.
