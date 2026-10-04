-- ======================================================================
-- FIX DEFINITIVO: RLS en ratings bloquea al rol 'anon' (clave pública APK)
-- ======================================================================

-- 1) Asegurar FORCE RLS en la tabla
ALTER TABLE public.ratings FORCE ROW LEVEL SECURITY;

-- 2) Eliminar políticas existentes
DROP POLICY IF EXISTS "drivers_select_own_received_ratings" ON public.ratings;
DROP POLICY IF EXISTS "customers_select_own_given_ratings" ON public.ratings;
DROP POLICY IF EXISTS "customors_insert_own_ratings" ON public.ratings;

-- 3) Política para autenticados (conductores): ven las que RECIBIERON
CREATE POLICY "drivers_select_own_received_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rated_id = auth.uid());

-- 4) Política para autenticados (clientes): ven las que DIERON
CREATE POLICY "customers_select_own_given_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rater_id = auth.uid());

-- 5) Política INSERT para autenticados (clientes califican conductores de sus servicios)
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

-- 6) POLÍTICAS EXPLÍCITAS PARA ANON: deniegan todo (USING false / WITH CHECK false)
--    Esto es más seguro que depender de auth.uid() IS NOT NULL
CREATE POLICY "anon_deny_select_ratings" ON public.ratings
  FOR SELECT TO anon
  USING (false);

CREATE POLICY "anon_deny_insert_ratings" ON public.ratings
  FOR INSERT TO anon
  WITH CHECK (false);

CREATE POLICY "anon_deny_update_ratings" ON public.ratings
  FOR UPDATE TO anon
  USING (false) WITH CHECK (false);

CREATE POLICY "anon_deny_delete_ratings" ON public.ratings
  FOR DELETE TO anon
  USING (false);