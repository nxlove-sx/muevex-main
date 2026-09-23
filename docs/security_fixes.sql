-- =============================================================================
-- MUEVEX · CORRECCIONES DE SEGURIDAD (auditoría 2026-09-07)
-- -----------------------------------------------------------------------------
-- Ejecutar ESTE script completo en: Supabase Dashboard > SQL Editor
-- (1 vez; todas las instrucciones son idempotentes).
-- Cubre los hallazgos:
--   [CRÍTICO-7]  Validación server-side de INSERT en services.
--   [CRÍTICO-20] BOLA/IDOR en storage: lectura bucket-wide de service-loads.
--   [WARNING-3]  RLS faltante en notifications y driver_locations.
--   [WARNING-12/19] Endurecer ejecución de RPCs (REVOKE de public).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0) driver_locations · crear la tabla faltante (si nunca se aplicó
--    migracion_conductor.sql). Incluye el UNIQUE en driver_id que exige el
--    upsert onConflict de las apps y el alta en realtime.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.driver_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  service_id UUID REFERENCES public.services(id) ON DELETE SET NULL,
  latitude NUMERIC(10, 6) NOT NULL,
  longitude NUMERIC(10, 6) NOT NULL,
  heading REAL DEFAULT 0,
  speed REAL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now()
);

DELETE FROM public.driver_locations a
  USING public.driver_locations b
  WHERE a.driver_id = b.driver_id AND a.updated_at < b.updated_at;

CREATE UNIQUE INDEX IF NOT EXISTS driver_locations_driver_id_key
  ON public.driver_locations(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_locations_service
  ON public.driver_locations(service_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_locations_driver
  ON public.driver_locations(driver_id, updated_at DESC);

ALTER TABLE public.driver_locations REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND tablename = 'driver_locations'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_locations;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1) STORAGE · lectura granular según relación (reemplaza profiles_select_public)
-- ---------------------------------------------------------------------------
-- service-loads: solo el cliente dueño del servicio o el conductor asignado.
DROP POLICY IF EXISTS "profiles_select_public" ON storage.objects;
DROP POLICY IF EXISTS "service_loads_select_owner_or_driver" ON storage.objects;
CREATE POLICY "service_loads_select_owner_or_driver" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'service-loads'
    AND EXISTS (
      SELECT 1 FROM public.services
      WHERE id::text = (storage.foldername(name))[1]
        AND (customer_id = auth.uid() OR driver_id = auth.uid())
    )
  );

-- vehicles: el dueño de la foto, o el cliente que tiene asignado a ese conductor.
DROP POLICY IF EXISTS "vehicles_select_owner_or_customer" ON storage.objects;
CREATE POLICY "vehicles_select_owner_or_customer" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'vehicles'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM public.vehicles v
        JOIN public.services s ON s.driver_id = v.driver_id
        WHERE v.driver_id::text = (storage.foldername(name))[1]
          AND s.customer_id = auth.uid()
          AND s.status IN ('aceptado','en_recogida','en_curso','completado')
      )
    )
  );

-- profiles (avatares): el dueño, o quien comparte un servicio con él.
DROP POLICY IF EXISTS "profiles_select_owner_or_related" ON storage.objects;
CREATE POLICY "profiles_select_owner_or_related" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'profiles'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM public.services
        WHERE customer_id = auth.uid()
          AND driver_id::text = (storage.foldername(name))[1]
        LIMIT 1
      )
      OR EXISTS (
        SELECT 1 FROM public.services
        WHERE driver_id = auth.uid()
          AND customer_id::text = (storage.foldername(name))[1]
        LIMIT 1
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 2) RLS · notifications (SELECT propio + marcar leídas)
-- ---------------------------------------------------------------------------
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
CREATE POLICY "notifications_select_own" ON public.notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
CREATE POLICY "notifications_update_own" ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3) RLS · driver_locations (el conductor escribe la suya; el cliente lee
--    la de su conductor asignado durante un servicio activo)
-- ---------------------------------------------------------------------------
ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_locations FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "driver_locations_upsert_own" ON public.driver_locations;
CREATE POLICY "driver_locations_upsert_own" ON public.driver_locations
  FOR ALL TO authenticated
  USING (driver_id = auth.uid())
  WITH CHECK (driver_id = auth.uid());

DROP POLICY IF EXISTS "driver_locations_select_assigned" ON public.driver_locations;
CREATE POLICY "driver_locations_select_assigned" ON public.driver_locations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.services
      WHERE driver_id = driver_locations.driver_id
        AND customer_id = auth.uid()
        AND status IN ('aceptado','en_recogida','en_curso')
    )
  );

-- ---------------------------------------------------------------------------
-- 4) CRÍTICO-7 · validación server-side del INSERT de services
--    (un cliente no puede inventar conductor, precio, estado ni fee)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.services_before_insert_check()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Solo puedes crear servicios propios.';
  END IF;
  IF NEW.status IS DISTINCT FROM 'solicitado' THEN
    RAISE EXCEPTION 'Los servicios deben crearse como "solicitado".';
  END IF;
  IF NEW.driver_id IS NOT NULL THEN
    RAISE EXCEPTION 'No puedes asignar un conductor manualmente.';
  END IF;
  IF NEW.accepted_at IS NOT NULL THEN
    NEW.accepted_at := NULL;
  END IF;
  IF NEW.estimated_price IS NOT NULL
     AND (NEW.estimated_price <= 0 OR NEW.estimated_price > 1000000) THEN
    RAISE EXCEPTION 'Precio estimado fuera de rango.';
  END IF;
  IF COALESCE(NEW.platform_fee, 0) <> 0 THEN
    NEW.platform_fee := 0;
  END IF;
  NEW.final_price := NULL;
  NEW.driver_earnings := 0;
  NEW.photos := '{}'::text[];
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_services_before_insert ON public.services;
CREATE TRIGGER trg_services_before_insert
  BEFORE INSERT ON public.services
  FOR EACH ROW EXECUTE FUNCTION public.services_before_insert_check();

-- ---------------------------------------------------------------------------
-- 5) Endurecer ejecución de RPCs (ninguna vía público/anon).
--    Solo se tocan las funciones que YA existan; si no existen (porque faltan
--    migraciones: driver_locations, accept_service, update_service_status...),
--    aplicar primero migracion_conductor.sql + migracion_integracion.sql.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regprocedure('public.accept_service(uuid)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.accept_service(uuid) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.accept_service(uuid) TO authenticated;
  END IF;
  IF to_regprocedure('public.update_service_status(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.update_service_status(uuid, text) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.update_service_status(uuid, text) TO authenticated;
  END IF;
  IF to_regprocedure('public.cancel_service(uuid, text)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.cancel_service(uuid, text) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.cancel_service(uuid, text) TO authenticated;
  END IF;
END $$;