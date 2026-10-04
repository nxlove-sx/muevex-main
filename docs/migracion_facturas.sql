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