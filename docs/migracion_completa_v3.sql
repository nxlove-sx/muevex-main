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
-- ===========================================================================
-- MIGRACIÓN: Facturas / Invoices (MUEVEX)
-- ===========================================================================
-- Cumple requisitos DIAN Colombia:
--   * Consecutivo único por resolución (prefijo + número)
--   * Datos completos de emisor (plataforma) y receptor (cliente)
--   * Desglose: subtotal, IVA (19%), retenciones opcionales, total
--   * Estado: borrador → emitida → anulada
--   * PDF generado y guardado en Storage (bucket: invoices/{invoiceId}.pdf)
--
-- Ejecutar en: Supabase → SQL Editor
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) Tipo de estado de factura
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_status_enum') THEN
    CREATE TYPE invoice_status_enum AS ENUM ('borrador', 'emitida', 'anulada');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2) Tabla invoices
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invoices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Consecutivo DIAN: "FEV-000001" (prefijo configurable + 6 dígitos)
  numero_factura TEXT NOT NULL UNIQUE,

  -- Referencias
  service_id UUID NOT NULL REFERENCES services(id) ON DELETE RESTRICT,
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  driver_id UUID REFERENCES users(id) ON DELETE SET NULL,

  -- Fechas
  fecha_emision TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fecha_vencimiento TIMESTAMPTZ,

  -- Datos emisor (plataforma) - se llenan desde config
  emisor_nit TEXT NOT NULL,
  emisor_nombre TEXT NOT NULL,
  emisor_direccion TEXT NOT NULL,
  emisor_ciudad TEXT NOT NULL,
  emisor_telefono TEXT,
  emisor_email TEXT,
  emisor_resolucion_dian TEXT,        -- número de resolución DIAN
  emisor_fecha_resolucion DATE,       -- fecha resolución
  emisor_prefijo TEXT NOT NULL,       -- ej. "FEV"
  emisor_rango_inicial INTEGER NOT NULL,
  emisor_rango_final INTEGER NOT NULL,

  -- Datos receptor (cliente)
  receptor_nit TEXT,
  receptor_nombre TEXT NOT NULL,
  receptor_direccion TEXT,
  receptor_ciudad TEXT,
  receptor_telefono TEXT,
  receptor_email TEXT,

  -- Detalle del servicio (snapshot al momento de facturar)
  servicio_descripcion TEXT NOT NULL,
  servicio_origen TEXT,
  servicio_destino TEXT,
  servicio_distancia_km NUMERIC(10,2),
  servicio_fecha TIMESTAMPTZ,

  -- Montos
  subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
  iva_porcentaje NUMERIC(5,2) NOT NULL DEFAULT 19.00,
  iva_valor NUMERIC(12,2) NOT NULL DEFAULT 0,
  retencion_fuente_porcentaje NUMERIC(5,2) DEFAULT 0,
  retencion_fuente_valor NUMERIC(12,2) DEFAULT 0,
  retencion_ica_porcentaje NUMERIC(5,2) DEFAULT 0,
  retencion_ica_valor NUMERIC(12,2) DEFAULT 0,
  total NUMERIC(12,2) NOT NULL DEFAULT 0,

  -- Estado y control
  status invoice_status_enum NOT NULL DEFAULT 'borrador',
  pdf_url TEXT,                       -- URL firmada del PDF en Storage
  notas TEXT,                         -- observaciones internas

  -- Auditoría
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  emitted_at TIMESTAMPTZ,
  voided_at TIMESTAMPTZ,
  voided_reason TEXT
);

-- Índices
CREATE INDEX IF NOT EXISTS invoices_customer_idx ON public.invoices (customer_id, fecha_emision DESC);
CREATE INDEX IF NOT EXISTS invoices_driver_idx ON public.invoices (driver_id, fecha_emision DESC);
CREATE INDEX IF NOT EXISTS invoices_service_idx ON public.invoices (service_id);
CREATE INDEX IF NOT EXISTS invoices_status_idx ON public.invoices (status);
CREATE INDEX IF NOT EXISTS invoices_numero_idx ON public.invoices (numero_factura);

-- ---------------------------------------------------------------------------
-- 3) Tabla invoice_items (líneas de factura)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invoice_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  orden INTEGER NOT NULL DEFAULT 1,
  codigo TEXT,                        -- código interno (ej. "TRANS-01")
  descripcion TEXT NOT NULL,
  cantidad NUMERIC(10,2) NOT NULL DEFAULT 1,
  unidad TEXT NOT NULL DEFAULT 'UND', -- UND, KM, KG, M3, etc.
  precio_unitario NUMERIC(12,2) NOT NULL,
  descuento_porcentaje NUMERIC(5,2) DEFAULT 0,
  descuento_valor NUMERIC(12,2) DEFAULT 0,
  subtotal NUMERIC(12,2) NOT NULL,    -- cantidad * precio_unitario - descuento
  iva_porcentaje NUMERIC(5,2) NOT NULL DEFAULT 19.00,
  iva_valor NUMERIC(12,2) NOT NULL DEFAULT 0,
  total NUMERIC(12,2) NOT NULL        -- subtotal + iva
);

CREATE INDEX IF NOT EXISTS invoice_items_invoice_idx ON public.invoice_items (invoice_id, orden);

-- ---------------------------------------------------------------------------
-- 4) Función para generar el siguiente consecutivo (thread-safe)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.next_invoice_number(
  p_prefijo TEXT DEFAULT 'FEV'
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_next INTEGER;
  v_numero TEXT;
BEGIN
  -- Bloquea la fila de configuración para evitar duplicados concurrentes
  LOOP
    BEGIN
      -- Busca o crea la secuencia para este prefijo
      INSERT INTO public.invoice_sequences (prefijo, last_number)
      VALUES (p_prefijo, 0)
      ON CONFLICT (prefijo) DO NOTHING;

      UPDATE public.invoice_sequences
      SET last_number = last_number + 1,
          updated_at = NOW()
      WHERE prefijo = p_prefijo
      RETURNING last_number INTO v_next;

      v_next := COALESCE(v_next, 1);
      v_numero := p_prefijo || '-' || LPAD(v_next::TEXT, 6, '0');

      -- Verifica que no exista ya (doble seguro)
      IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE numero_factura = v_numero) THEN
        RETURN v_numero;
      END IF;
      -- Si colisiona (raro), reintenta
    EXCEPTION WHEN OTHERS THEN
      -- Reintenta en caso de deadlock
      PERFORM pg_sleep(0.01);
    END;
  END LOOP;
END;
$$;

-- Tabla auxiliar para secuencias por prefijo
CREATE TABLE IF NOT EXISTS public.invoice_sequences (
  prefijo TEXT PRIMARY KEY,
  last_number INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 5) Trigger para updated_at
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_invoice_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_invoices_updated_at ON public.invoices;
CREATE TRIGGER trigger_invoices_updated_at
  BEFORE UPDATE ON public.invoices
  FOR EACH ROW EXECUTE FUNCTION public.update_invoice_updated_at();

DROP TRIGGER IF EXISTS trigger_invoice_items_updated_at ON public.invoice_items;
-- invoice_items no tiene updated_at, solo se inserta/borra

-- ---------------------------------------------------------------------------
-- 6) RLS (Row Level Security)
-- ---------------------------------------------------------------------------
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_sequences ENABLE ROW LEVEL SECURITY;

-- El cliente ve SUS facturas
DROP POLICY IF EXISTS invoices_select_own ON public.invoices;
CREATE POLICY invoices_select_own ON public.invoices
  FOR SELECT USING (customer_id = auth.uid());

-- El conductor ve facturas de SUS servicios
DROP POLICY IF EXISTS invoices_select_driver ON public.invoices;
CREATE POLICY invoices_select_driver ON public.invoices
  FOR SELECT USING (driver_id = auth.uid());

-- Solo la plataforma (service_role) inserta/actualiza
DROP POLICY IF EXISTS invoices_insert_platform ON public.invoices;
CREATE POLICY invoices_insert_platform ON public.invoices
  FOR INSERT WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS invoices_update_platform ON public.invoices;
CREATE POLICY invoices_update_platform ON public.invoices
  FOR UPDATE USING (auth.role() = 'service_role');

-- Items siguen la factura padre
DROP POLICY IF EXISTS invoice_items_select ON public.invoice_items;
CREATE POLICY invoice_items_select ON public.invoice_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.invoices i
      WHERE i.id = invoice_items.invoice_id
      AND (i.customer_id = auth.uid() OR i.driver_id = auth.uid())
    )
  );

-- Secuencias solo service_role
DROP POLICY IF EXISTS invoice_sequences_platform ON public.invoice_sequences;
CREATE POLICY invoice_sequences_platform ON public.invoice_sequences
  FOR ALL USING (auth.role() = 'service_role');

-- ---------------------------------------------------------------------------
-- 7) Storage bucket para PDFs
-- ---------------------------------------------------------------------------
-- Ejecutar en Supabase Dashboard → Storage:
--   1. Create bucket: "invoices" (private)
--   2. Policy: service_role puede INSERT/UPDATE/DELETE
--   3. Policy: usuario autenticado puede SELECT solo sus facturas
--      (usar auth.uid() = customer_id o driver_id via join)

-- Nota: El bucket se crea desde Dashboard o CLI, no por SQL.
-- ===========================================================================