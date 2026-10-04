-- ======================================================================
-- FIX DEFINITIVO v4: RLS en ratings bloquea al rol 'anon'
-- ======================================================================

-- 1) FORCE RLS (aplica también al owner)
ALTER TABLE public.ratings FORCE ROW LEVEL SECURITY;

-- 2) Revocar SELECT explícito a anon (por si hay GRANT que bypassa RLS)
REVOKE ALL ON public.ratings FROM anon;

-- 3) Eliminar TODAS las políticas existentes en ratings
DROP POLICY IF EXISTS "drivers_select_own_received_ratings" ON public.ratings;
DROP POLICY IF EXISTS "customers_select_own_given_ratings" ON public.ratings;
DROP POLICY IF EXISTS "customers_insert_own_ratings" ON public.ratings;
DROP POLICY IF EXISTS "customors_insert_own_ratings" ON public.ratings;
DROP POLICY IF EXISTS "anon_deny_select_ratings" ON public.ratings;
DROP POLICY IF EXISTS "anon_deny_insert_ratings" ON public.ratings;
DROP POLICY IF EXISTS "anon_deny_update_ratings" ON public.ratings;
DROP POLICY IF EXISTS "anon_deny_delete_ratings" ON public.ratings;

-- 4) Políticas para USUARIOS AUTENTICADOS
-- Conductor ve calificaciones que RECIBIÓ
CREATE POLICY "drivers_select_own_received_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rated_id = auth.uid());

-- Cliente ve calificaciones que DIÓ
CREATE POLICY "customers_select_own_given_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rater_id = auth.uid());

-- Cliente inserta calificación a conductor de su servicio
CREATE POLICY "customers_insert_own_ratings" ON public.ratings
  FOR INSERT TO authenticated
  WITH CHECK (
    rater_id = auth.uid()
    AND rated_id != auth.uid()
    AND EXISTS (SELECT 1 FROM public.services
                WHERE id = service_id
                  AND customer_id = auth.uid()
                  AND driver_id = rated_id)
  );

-- 5) Políticas explícitas DENEGADORAS para ANON (USING false / WITH CHECK false)
--    Estas DEBEN ir después de las de authenticated para tener precedencia
CREATE POLICY "anon_deny_select" ON public.ratings
  FOR SELECT TO anon
  USING (false);

CREATE POLICY "anon_deny_insert" ON public.ratings
  FOR INSERT TO anon
  WITH CHECK (false);

CREATE POLICY "anon_deny_update" ON public.ratings
  FOR UPDATE TO anon
  USING (false) WITH CHECK (false);

CREATE POLICY "anon_deny_delete" ON public.ratings
  FOR DELETE TO anon
  USING (false);

-- 6) Verificación: las políticas creadas
-- SELECT policyname, cmd, roles, qual, with_check FROM pg_policies WHERE tablename = 'ratings';