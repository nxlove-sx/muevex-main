-- ======================================================================
-- FIX: RLS en ratings debe bloquear tambi�n al rol 'anon' (clave p�blica)
-- ======================================================================

-- Las pol�ticas actuales son FOR SELECT TO authenticated.
-- El rol 'anon' (clave p�blica del APK) no tiene pol�tica � cae en
-- comportamiento por defecto (en Supabase a veces es PERMITIR).
-- A�adimos USING (auth.uid() IS NOT NULL) para que anon falle la condici�n.

DROP POLICY IF EXISTS "drivers_select_own_received_ratings" ON public.ratings;
CREATE POLICY "drivers_select_own_received_ratings" ON public.ratings
  FOR SELECT TO authenticated, anon
  USING (auth.uid() IS NOT NULL AND rated_id = auth.uid());

DROP POLICY IF EXISTS "customers_select_own_given_ratings" ON public.ratings;
CREATE POLICY "customers_select_own_given_ratings" ON public.ratings
  FOR SELECT TO authenticated, anon
  USING (auth.uid() IS NOT NULL AND rater_id = auth.uid());

-- INSERT ya valida rater_id = auth.uid() (anon no tiene uid -> falla),
-- pero por claridad tambi�n a�adimos el check expl�cito.
DROP POLICY IF EXISTS "customors_insert_own_ratings" ON public.ratings;
CREATE POLICY "customors_insert_own_ratings" ON public.ratings
  FOR INSERT TO authenticated, anon
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND rater_id = auth.uid()
    AND rated_id != auth.uid()
    AND EXISTS (SELECT 1 FROM public.services
                WHERE id = service_id
                  AND customer_id = auth.uid()
                  AND driver_id = rated_id)
  );