-- ======================================================================
-- ARREGLO SISTEMA DE CALIFICACIONES (spec 65) — orden seguro
-- ======================================================================

-- 0) LIMPIEZA PREVIA (antes del índice único)
--    Deja la MÁS RECIENTE por (service_id, rater_id, rated_id)
WITH dup AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY service_id, rater_id, rated_id ORDER BY created_at DESC) AS rn
  FROM public.ratings
)
DELETE FROM public.ratings
WHERE id IN (SELECT id FROM dup WHERE rn > 1);

--    Borra auto-calificaciones históricas (rater_id == rated_id)
DELETE FROM public.ratings WHERE rater_id = rated_id;

-- 1) Índice único: ahora sí puede crearse sin colisiones
CREATE UNIQUE INDEX IF NOT EXISTS uq_ratings_service_rater_rated
  ON public.ratings (service_id, rater_id, rated_id);

-- 2) RLS en ratings
ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

-- 3) Políticas SELECT
DROP POLICY IF EXISTS "drivers_select_own_received_ratings" ON public.ratings;
CREATE POLICY "drivers_select_own_received_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rated_id = auth.uid());

DROP POLICY IF EXISTS "customers_select_own_given_ratings" ON public.ratings;
CREATE POLICY "customers_select_own_given_ratings" ON public.ratings
  FOR SELECT TO authenticated
  USING (rater_id = auth.uid());

-- 4) Política INSERT reforzada
DROP POLICY IF EXISTS "customers_insert_own_ratings" ON public.ratings;
CREATE POLICY "customors_insert_own_ratings" ON public.ratings
  FOR INSERT TO authenticated
  WITH CHECK (
    rater_id = auth.uid()
    AND rated_id != auth.uid()
    AND EXISTS (SELECT 1 FROM public.services
                WHERE id = service_id
                  AND customer_id = auth.uid()
                  AND driver_id = rated_id)
  );

-- 5) Trigger on_rating_inserted (crea driver_profiles si falta)
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
BEGIN
  SELECT id INTO v_driver_profiles_id
    FROM public.driver_profiles
   WHERE user_id = NEW.rated_id;

  IF NOT FOUND THEN
    INSERT INTO public.driver_profiles (user_id, rating, total_services, is_verified, status, availability)
    VALUES (NEW.rated_id, 0, 0, false, 'offline', 'offline')
    RETURNING id INTO v_driver_profiles_id;
  END IF;

  UPDATE public.driver_profiles
     SET rating = COALESCE((
           SELECT AVG(score)::numeric(3,2)
             FROM public.ratings
            WHERE rated_id = NEW.rated_id
         ), 0),
         updated_at = NOW()
   WHERE id = v_driver_profiles_id;

  BEGIN
    PERFORM public.notify_user(
      NEW.rated_id, 'new_rating',
      'Nueva calificación',
      'Un cliente te calificó con ' || NEW.score::text || ' estrellas.',
      jsonb_build_object('service_id', NEW.service_id, 'rating', NEW.score, 'comment', NEW.comment)
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
END $$;

CREATE TRIGGER trig_on_rating
  AFTER INSERT ON public.ratings
  FOR EACH ROW EXECUTE FUNCTION public.on_rating_inserted();