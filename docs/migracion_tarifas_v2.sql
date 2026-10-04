-- ===========================================================================
-- MIGRACIÓN: motor de tarifas TRANSPERSQUI  (MUEVEX)
-- ===========================================================================
-- Añade a `services` los datos que necesitan las reglas de tarifa nuevas:
-- artículos, pisos separados, número de viajes, origen del ayudante y el
-- desglose con el que se cotizó.
--
-- Reglas:
--   * Solo ADD COLUMN IF NOT EXISTS / CREATE OR IF NOT EXISTS → se puede correr
--     las veces que haga falta sin romper nada.
--   * No borra ni renombra columnas. `floors`, `load_type`, `loading_help` y
--     `price_base` se conservan: el código viejo y los servicios ya pagados
--     siguen leyéndolos.
--   * `floors` se deja como la suma de recogida + entrega para que las
--     consultas antiguas (conductor, panel) sigan dando un número razonable.
--
-- Ejecutar en: Supabase → SQL Editor. Después, en cada conductor, recargar el
-- perfil de vehículo para que registre la capacidad autorizada (ver abajo).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) Columnas nuevas de `services`
-- ---------------------------------------------------------------------------

-- Artículos elegidos por el cliente. El cliente nunca escribe el peso: elige
-- de un catálogo y la app lo resuelve.
-- Formato: [{"id":"nevera_mediana","cantidad":1}, ...]
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb;

-- Pisos por separado en recogida y en entrega. El documento de tarifas exige
-- calcular cada uno de forma independiente ($10.000 por piso y por viaje).
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS floors_pickup INTEGER DEFAULT 0;
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS floors_delivery INTEGER DEFAULT 0;

-- Varios viajes: 1 = normal, 2 = 85 %, 3+ = 80 % por viaje.
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS trips INTEGER DEFAULT 1;

-- Quién pone el ayudante: 'incluido' | 'cliente' | 'plataforma'.
-- 'plataforma' son $30.000; los otros dos no cuestan nada.
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS helper_origin TEXT DEFAULT 'incluido';

-- Peso total estimado a partir del catálogo de artículos. Se guarda aparte de
-- `load_weight_kg` (que es el peso que declara el cliente a mano) porque de
-- esto depende la asignación de vehículo.
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS estimated_weight_kg NUMERIC(10,2) DEFAULT 0;

-- Volumen estimado en m³, también derivado del catálogo.
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS estimated_volume_m3 NUMERIC(10,2) DEFAULT 0;

-- Categoría de motocarro sugerida por el peso ('200' | '250' | '300' | '500').
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS vehicle_category TEXT;

-- Desglose exacto con el que se cotizó, para que el comprobante pueda explicar
-- el precio meses después sin depender de volver a calcularlo:
--   {"total":80000,"lineas":[{"concepto":"...","monto":50000,"detalle":"..."}],
--    "tipo_carga":"delicada","es_mudanza":true,"viajes":1,
--    "capacidad_minima_kg":410}
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS tariff_breakdown JSONB;

-- Marca de la regla con la que se cotizó, por si un día se cambia la tabla.
-- Permite distinguir los servicios cobran con la fórmula nueva de los
-- antiguos, que eran mucho más baratos.
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS tariff_version TEXT;

-- ---------------------------------------------------------------------------
-- 2) Restricciones de seguridad (evitan datos que rompan el motor)
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.services'::regclass
      AND conname = 'services_trips_check'
  ) THEN
    ALTER TABLE public.services
      ADD CONSTRAINT services_trips_check
      CHECK (trips IS NULL OR trips BETWEEN 1 AND 10);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.services'::regclass
      AND conname = 'services_floors_check'
  ) THEN
    ALTER TABLE public.services
      ADD CONSTRAINT services_floors_check
      CHECK (
        (floors_pickup  IS NULL OR floors_pickup  >= 0) AND
        (floors_delivery IS NULL OR floors_delivery >= 0) AND
        (floors IS NULL OR floors >= 0)
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.services'::regclass
      AND conname = 'services_helper_origin_check'
  ) THEN
    ALTER TABLE public.services
      ADD CONSTRAINT services_helper_origin_check
      CHECK (
        helper_origin IS NULL OR
        helper_origin IN ('incluido', 'cliente', 'plataforma')
      );
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3) Backfill: coherencia con los servicios que ya existen
-- ---------------------------------------------------------------------------

-- Los servicios anteriores solo tienen `floors`, y el formulario viejo no
-- distinguía recogida de entrega: se asume que todos eran de entrega.
--
-- OJO con el orden: `floors` se lee ANTES de reescribirlo como la suma. Si se
-- invirtiera el orden, la suma se calcularía sobre valores ya a cero y se
-- perderían los pisos existentes.
UPDATE public.services
SET
  floors_delivery = COALESCE(floors, 0),
  floors_pickup  = 0,
  trips           = 1,
  helper_origin   = CASE
                       WHEN COALESCE(loading_help, FALSE) THEN 'plataforma'
                       ELSE 'incluido'
                     END,
  items           = COALESCE(items, '[]'::jsonb)
WHERE floors_pickup IS NULL
   OR floors_delivery IS NULL
   OR trips IS NULL
   OR helper_origin IS NULL
   OR items IS NULL;

-- `floors` pasa a ser la suma, para que el conductor y las consultas que ya lo
-- usan sigan viendo el total de pisos.
UPDATE public.services
SET floors = COALESCE(floors_pickup, 0) + COALESCE(floors_delivery, 0)
WHERE COALESCE(floors, -1)
      <> COALESCE(floors_pickup, 0) + COALESCE(floors_delivery, 0);

-- Marca a los servicios ya cotizados con la fórmula antigua, para que quede
-- claro en el comprobante que su precio no viene de la tabla nueva.
UPDATE public.services
SET tariff_version = 'legacy'
WHERE tariff_version IS NULL
  AND estimated_price IS NOT NULL
  AND estimated_price > 0;

-- ---------------------------------------------------------------------------
-- 4) Índice para el historial por conductor
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS services_driver_created_idx
  ON public.services (driver_id, created_at DESC)
  WHERE driver_id IS NOT NULL;

-- ===========================================================================
-- NOTA: capacidad autorizada por vehículo
-- ===========================================================================
-- La tabla `vehicles` YA tiene `capacity INTEGER`, que es la capacidad
-- máxima autorizada de ese vehículo concreto. Es ese campo el que decide si
-- una carga cabe — NO el cilindraje: dos motocarros de 300 cc pueden llevar
-- capacidades distintas y la plataforma no debe asumir 1.000 kg solo por los cc.
--
-- Qué falta y hay que hacer a mano:
--
--   1. Cada conductor debe declarar la capacidad real de su vehículo en su
--      perfil (si no lo ha hecho, `capacity` sale con el valor por defecto de
--      500, que es una suposición, no un dato).
--
--   2. Opcional pero recomendado: guardar el cilindraje como dato informativo,
--      sin usarlo para decidir capacidad:
--
--        ALTER TABLE public.vehicles
--          ADD COLUMN IF NOT EXISTS engine_cc INTEGER;
--
-- ===========================================================================
