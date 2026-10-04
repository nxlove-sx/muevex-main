-- ======================================================================
-- FIX: Añadir tablas faltantes a supabase_realtime
-- ======================================================================
-- services: cambios de estado (solicitado -> aceptado -> en_recogida -> en_curso -> completado)
-- notifications: avisos al usuario (nueva calificación, servicio aceptado, etc.)
-- driver_profiles: actualización de rating/total_services (para "Mi reputación")
-- ======================================================================

-- services
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'services'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.services;
  END IF;
END $$;

-- notifications
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;

-- driver_profiles
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'driver_profiles'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_profiles;
  END IF;
END $$;

-- Verificar
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime';