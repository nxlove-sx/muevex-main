-- ============================================================================
-- MUEVEX · VERIFICACIÓN PREVIA A LA DEMO
-- Pegar y ejecutar en Supabase Dashboard > SQL Editor.
-- Todo debe salir "OK". Si algo sale "FALTA", aplicar la migración indicada
-- (base original / migracion_conductor.sql / migracion_integracion.sql /
-- security_fixes.sql) y re-ejecutar.
-- ============================================================================

SELECT
  CASE

    WHEN chk = 'tabla.services'      THEN to_regclass('public.services') IS NOT NULL
    WHEN chk = 'tabla.users'         THEN to_regclass('public.users') IS NOT NULL
    WHEN chk = 'tabla.customer_profiles' THEN to_regclass('public.customer_profiles') IS NOT NULL
    WHEN chk = 'tabla.driver_profiles'   THEN to_regclass('public.driver_profiles') IS NOT NULL
    WHEN chk = 'tabla.vehicles'      THEN to_regclass('public.vehicles') IS NOT NULL
    WHEN chk = 'tabla.driver_locations' THEN to_regclass('public.driver_locations') IS NOT NULL
    WHEN chk = 'tabla.notifications' THEN to_regclass('public.notifications') IS NOT NULL
    WHEN chk = 'tabla.ratings'       THEN to_regclass('public.ratings') IS NOT NULL
    WHEN chk = 'tabla.payments'      THEN to_regclass('public.payments') IS NOT NULL

    WHEN chk = 'col.services.price_recommended' THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='price_recommended')
    WHEN chk = 'col.services.price_offer'       THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='price_offer')
    WHEN chk = 'col.services.status_check'      THEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='services_status_check')
    WHEN chk = 'col.notifications.data'         THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notifications' AND column_name='data')
    WHEN chk = 'col.payments.paid_at'           THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='payments' AND column_name='paid_at')
    WHEN chk = 'col.vehicles.type'              THEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='vehicles' AND column_name='type')

    WHEN chk = 'fn.accept_service'       THEN to_regprocedure('public.accept_service(uuid)') IS NOT NULL
    WHEN chk = 'fn.update_service_status' THEN to_regprocedure('public.update_service_status(uuid,text)') IS NOT NULL
    WHEN chk = 'fn.cancel_service'       THEN to_regprocedure('public.cancel_service(uuid,text)') IS NOT NULL
    WHEN chk = 'fn.notify_user'          THEN to_regprocedure('public.notify_user(uuid,text,text,text,jsonb)') IS NOT NULL

    WHEN chk = 'trg.services_before_insert' THEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_services_before_insert')
    WHEN chk = 'enum.notification_type_enum' THEN EXISTS (SELECT 1 FROM pg_type WHERE typname='notification_type_enum')
    WHEN chk = 'enum.value.service_cancelled_by_driver' THEN
      EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
              WHERE t.typname='notification_type_enum' AND e.enumlabel='service_cancelled_by_driver')

    WHEN chk = 'realtime.services' THEN EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='services')
    WHEN chk = 'realtime.driver_locations' THEN EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='driver_locations')
    WHEN chk = 'replica.services_full' THEN EXISTS (SELECT 1 FROM pg_class WHERE relname='services' AND relreplident='f')

    WHEN chk = 'idx.driver_locations_driver_id' THEN EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='driver_locations' AND indexname='driver_locations_driver_id_key')

    WHEN chk = 'rls.services'      THEN (SELECT relrowsecurity FROM pg_class WHERE relname='services') = true
    WHEN chk = 'rls.driver_locations' THEN (SELECT relrowsecurity FROM pg_class WHERE relname='driver_locations') = true
    WHEN chk = 'rls.notifications' THEN (SELECT relrowsecurity FROM pg_class WHERE relname='notifications') = true

    WHEN chk = 'bucket.profiles'      THEN EXISTS (SELECT 1 FROM storage.buckets WHERE id='profiles')
    WHEN chk = 'bucket.vehicles'      THEN EXISTS (SELECT 1 FROM storage.buckets WHERE id='vehicles')
    WHEN chk = 'bucket.service-loads' THEN EXISTS (SELECT 1 FROM storage.buckets WHERE id='service-loads')

    ELSE true
  END AS ok,
  chk,
  CASE
    WHEN chk NOT IN ('bucket.profiles','bucket.vehicles','bucket.service-loads') THEN 'security_fixes/migraciones'
    ELSE 'migracion_integracion (buckets)'
  END AS migracion_a_aplicar
FROM (VALUES
  ('tabla.services'),('tabla.users'),('tabla.customer_profiles'),
  ('tabla.driver_profiles'),('tabla.vehicles'),('tabla.driver_locations'),
  ('tabla.notifications'),('tabla.ratings'),('tabla.payments'),
  ('col.services.price_recommended'),('col.services.price_offer'),('col.services.status_check'),
  ('col.notifications.data'),('col.payments.paid_at'),('col.vehicles.type'),
  ('fn.accept_service'),('fn.update_service_status'),('fn.cancel_service'),('fn.notify_user'),
  ('trg.services_before_insert'),
  ('enum.notification_type_enum'),('enum.value.service_cancelled_by_driver'),
  ('realtime.services'),('realtime.driver_locations'),('replica.services_full'),
  ('idx.driver_locations_driver_id'),
  ('rls.services'),('rls.driver_locations'),('rls.notifications'),
  ('bucket.profiles'),('bucket.vehicles'),('bucket.service-loads')
) AS t(chk)
ORDER BY ok, chk;
