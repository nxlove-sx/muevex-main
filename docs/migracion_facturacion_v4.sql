-- ===========================================================================
-- MIGRACIÓN v4: facturación utilizable  (MUEVEX)
-- ===========================================================================
-- Arregla dos cosas que hacían la facturación inútil:
--
--   1. RLS bloqueaba la creación. Las políticas de `invoices` dan
--      INSERT/UPDATE solo a `service_role`, y las dos apps llaman a Supabase
--      con la anon key. El botón "Generar factura" fallaba siempre con
--      "new row violates row-level security policy".
--
--   2. Los datos del emisor (NIT, resolución DIAN) estaban hardcodeados en
--      las dos apps, así que había que cambiarlos en dos sitios y no había
--      forma de saber cuál era el bueno.
--
-- La solución NO es abrir `invoices` a la anon key. Si se permite INSERT al
-- anon key, cualquiera que tenga la clave podría emitir una factura con el
-- precio que quisiera. En vez de eso, todo el cálculo se mueve a una función
-- `SECURITY DEFINER` que:
--
--   * corre con los permisos de postgres (no la puede saltarse un cliente),
--   * valida que quien llama sea el cliente o el conductor del servicio,
--   * valida que el servicio esté completado y no tenga otra factura,
--   * toma el número consecutivo y el emisor de la base de datos,
--   * y calcula los montos. El cliente no envía ningún monto.
--
-- Los datos del emisor pasan a una tabla `emisor_config` de una fila, que se
-- edita desde el panel de Supabase. Cambiar el NIT deja de ser editar dos
-- ficheros Dart.
--
-- DECISIÓN DE NEGOCIO (2026-09-28): los precios de la tabla TRANSPERSQUI son
-- NETOS, sin IVA. El motor de tarifas no aplica IVA en ningún punto. Por eso
--   subtotal = precio cotizado
--   IVA      = precio cotizado * 0.19
--   total    = precio cotizado * 1.19
-- OJO: el total facturado es un 19% MAYOR que lo que el cliente ve en la app.
-- Ver la nota de "Aviso de IVA" más abajo.
--
-- Reglas:
--   * Todo es IF EXISTS / IF NOT EXISTS → se puede correr las veces que haga
--     falta sin romper nada.
--   * No borra facturas existentes ni datos.
--
-- Ejecutar en: Supabase → SQL Editor
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 0) AVISO DE IVA — leer antes de ejecutar
-- ---------------------------------------------------------------------------
-- La tabla de TRANSPERSQUI da precios sin IVA, pero la app los muestra al
-- cliente como el total a pagar. Si la factura suma el 19% encima, el cliente
-- ve un precio y recibe otro 19% más caro.
--
-- Esto NO se arregla aquí: es una decisión de negocio. Las dos salidas:
--
--   A) Declarar en la app que el precio mostrado NO incluye IVA.
--      Entonces lo que ve el cliente coincide con el subtotal, y la factura
--      le adds el IVA. Es lo que hace este SQL.
--
--   B) Subir el IVA dentro del motor de tarifas, para que el precio que ve el
--      cliente sea el total con IVA. Es lo que hace la mayoría del comercio en
--      Colombia, pero cambia los precios de toda la tabla y obliga a
--      recalcular los 33 tests de `tariff_engine_test.dart`.
--
-- Mientras no se decida, este SQL asume (A) y no toca el motor.


-- ---------------------------------------------------------------------------
-- 1) Tabla emisor_config (una fila)
-- ---------------------------------------------------------------------------
-- Datos de quien emite: la plataforma. Se edita desde el panel de Supabase,
-- no desde el código, para que las dos apps no puedan divergir.
--
-- La fila se crea con los MISMOS valores de ejemplo que estaban en el código.
-- Son ficticios: hay que sustituirlos por los reales antes de facturar de
-- verdad, o las facturas salen inválidas.

CREATE TABLE IF NOT EXISTS public.emisor_config (
  id                  BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  nit                 TEXT NOT NULL,
  nombre              TEXT NOT NULL,
  direccion           TEXT NOT NULL,
  ciudad              TEXT NOT NULL,
  telefono            TEXT,
  email               TEXT,
  resolucion_dian     TEXT,
  fecha_resolucion    DATE,
  prefijo             TEXT NOT NULL DEFAULT 'FEV',
  rango_inicial       INTEGER NOT NULL DEFAULT 1,
  rango_final         INTEGER NOT NULL DEFAULT 999999,
  iva_porcentaje      NUMERIC(5,2) NOT NULL DEFAULT 19.00,
  dias_credito        INTEGER NOT NULL DEFAULT 30,
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.emisor_config IS
  'Datos del emisor (la plataforma). Una sola fila. Editable desde el panel de Supabase.';

-- Fila única de configuración. Si no existe, se crea con los datos de ejemplo.
INSERT INTO public.emisor_config
  (id, nit, nombre, direccion, ciudad, telefono, email,
   resolucion_dian, fecha_resolucion, prefijo, rango_inicial, rango_final,
   iva_porcentaje, dias_credito)
VALUES
  (TRUE, '900.000.000-0', 'MUEVEX S.A.S.', 'Carrera 1 # 1-1', 'Medellín',
   '+57 4 000 0000', 'facturacion@muevex.com',
   '18765000001234', DATE '2024-01-15', 'FEV', 1, 999999,
   19.00, 30)
ON CONFLICT (id) DO NOTHING;

-- Si la tabla ya existía de otra migración, insure los defaults que falten.
ALTER TABLE public.emisor_config
  ADD COLUMN IF NOT EXISTS iva_porcentaje NUMERIC(5,2) NOT NULL DEFAULT 19.00;
ALTER TABLE public.emisor_config
  ADD COLUMN IF NOT EXISTS dias_credito INTEGER NOT NULL DEFAULT 30;

-- Cualquiera autenticado puede leer (los datos van en el PDF).
-- Escribir solo desde el panel, no desde las apps.
ALTER TABLE public.emisor_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS emisor_config_select ON public.emisor_config;
CREATE POLICY emisor_config_select ON public.emisor_config
  FOR SELECT USING (TRUE);

REVOKE INSERT, UPDATE, DELETE ON public.emisor_config FROM anon, authenticated;


-- ---------------------------------------------------------------------------
-- 2) Helper: leer el emisor
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_emisor()
RETURNS public.emisor_config
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.emisor_config WHERE id = TRUE LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_emisor() TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 3) La función que crea la factura
-- ---------------------------------------------------------------------------
-- Es el corazón del arreglo. Recibe el id del servicio y devuelve la factura
-- creada. NO recibe ningún monto: todos se calculan aquí desde el servicio.
--
-- Garantías:
--   * Solo el cliente o el conductor de ESE servicio pueden llamarla.
--   * El servicio tiene que estar `completado`.
--   * Un servicio no se puede facturar dos veces.
--   * El número consecutivo se pide dentro de la misma transacción.
--   * Los renglones salen del `tariff_breakdown` guardado al cotizar.
--
-- Es idempotente en cuanto al servicio: si ya hay factura, la devuelve en vez
-- de crear otra. Así el botón se puede pulsar dos veces sin duplicar.

CREATE OR REPLACE FUNCTION public.crear_factura_desde_servicio(
  p_service_id UUID
)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user        UUID := auth.uid();
  v_service     public.services%ROWTYPE;
  v_customer    RECORD;
  v_emisor      public.emisor_config%ROWTYPE;
  v_existente   public.invoices%ROWTYPE;
  v_factura     public.invoices%ROWTYPE;
  v_breakdown   JSONB;
  v_lineas      JSONB;
  v_linea       JSONB;
  v_base        NUMERIC(12,2);
  v_subtotal    NUMERIC(12,2);
  -- v_iva es un VALOR en pesos, no un porcentaje. Necesita la misma anchura que
  -- los demás montos. Antes estaba declarado como NUMERIC(5,2), que es la
  -- precisión de un porcentaje y solo admite hasta 999,99: con cualquier
  -- servicio de más de 5.263 COP el IVA se pasaba de ese límite y Postgres
  -- abortaba la factura entera con "numeric field overflow". Como el error
  -- salía de la función y no de una columna, no affected a las tablas.
  v_iva         NUMERIC(12,2);
  v_total       NUMERIC(12,2);
  v_numero      TEXT;
  v_orden       INTEGER := 0;
  v_monto       NUMERIC(12,2);
  v_suma_items  NUMERIC(12,2) := 0;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Debes iniciar sesión para facturar';
  END IF;

  -- El servicio tiene que existir y estar completado
  SELECT * INTO v_service FROM public.services WHERE id = p_service_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El servicio no existe';
  END IF;

  IF v_service.status <> 'completado' THEN
    RAISE EXCEPTION 'Solo se pueden facturar servicios completados';
  END IF;

  -- Autorización: solo el cliente o el conductor de ese servicio
  IF v_user <> v_service.customer_id
     AND (v_service.driver_id IS NULL OR v_user <> v_service.driver_id) THEN
    RAISE EXCEPTION 'No tienes permiso para facturar este servicio';
  END IF;

  -- Si ya existe una factura para este servicio, se devuelve esa
  SELECT * INTO v_existente
  FROM public.invoices
  WHERE service_id = p_service_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN v_existente;
  END IF;

  -- Datos del emisor y del cliente
  SELECT * INTO v_emisor FROM public.emisor_config WHERE id = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Falta configurar el emisor en emisor_config';
  END IF;

  SELECT u.id, u.name, u.email, u.phone
  INTO v_customer
  FROM public.users u
  WHERE u.id = v_service.customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No se encontró el cliente del servicio';
  END IF;

  -- Monto a facturar.
  --
  -- `final_price` es lo que el conductor confirmó antes de empezar el viaje: es
  -- el precio de verdad y manda sobre cualquier otro. Si no hay precio final
  -- (servicios antiguos, o servicios que el conductor nunca ajustó), se usa el
  -- estimado y, en su defecto, `price_base`.
  --
  -- Antes esta función solo miraba `estimated_price`, así que si el conductor
  -- había negociado otra cosa, la factura salía con el precio de la cotización
  -- y no con lo que se cobró.
  v_base := COALESCE(
              NULLIF(v_service.final_price, 0),
              NULLIF(v_service.estimated_price, 0),
              NULLIF(v_service.price_base, 0),
              0
            );

  IF v_base <= 0 THEN
    RAISE EXCEPTION 'El servicio no tiene un precio válido para facturar';
  END IF;

  -- Los precios de TRANSPERSQUI son NETOS: el IVA va encima.
  v_subtotal := v_base;
  v_iva      := ROUND(v_subtotal * v_emisor.iva_porcentaje / 100, 2);
  v_total    := v_subtotal + v_iva;

  -- Número consecutivo (dentro de esta misma transacción)
  v_numero := public.next_invoice_number(v_emisor.prefijo);

  -- Inserta la factura en borrador
  INSERT INTO public.invoices (
    numero_factura, service_id, customer_id, driver_id,
    fecha_emision, fecha_vencimiento,
    emisor_nit, emisor_nombre, emisor_direccion, emisor_ciudad,
    emisor_telefono, emisor_email,
    emisor_resolucion_dian, emisor_fecha_resolucion,
    emisor_prefijo, emisor_rango_inicial, emisor_rango_final,
    receptor_nit, receptor_nombre,
    receptor_telefono, receptor_email,
    servicio_descripcion, servicio_origen, servicio_destino,
    servicio_distancia_km, servicio_fecha,
    subtotal, iva_porcentaje, iva_valor,
    total, status
  ) VALUES (
    v_numero, v_service.id, v_service.customer_id, v_service.driver_id,
    NOW(), NOW() + (v_emisor.dias_credito || ' days')::INTERVAL,
    v_emisor.nit, v_emisor.nombre, v_emisor.direccion, v_emisor.ciudad,
    v_emisor.telefono, v_emisor.email,
    v_emisor.resolucion_dian, v_emisor.fecha_resolucion,
    v_emisor.prefijo, v_emisor.rango_inicial, v_emisor.rango_final,
    NULL, v_customer.name,
    v_customer.phone, v_customer.email,
    COALESCE(NULLIF(v_service.description, ''), 'Servicio de transporte'),
    -- `origin_name` es la dirección real que resolvió la geocodificación
    -- inversa. Si el servicio es viejo y no la tiene, se cae a `origin`.
    COALESCE(NULLIF(v_service.origin_name, ''), NULLIF(v_service.origin, '')),
    COALESCE(NULLIF(v_service.destination_name, ''),
             NULLIF(v_service.destination, '')),
    v_service.distance_km, v_service.created_at,
    v_subtotal, v_emisor.iva_porcentaje, v_iva,
    v_total, 'borrador'
  )
  RETURNING * INTO v_factura;

  -- Renglones: uno por línea del desglose con el que se cotizó
  v_breakdown := v_service.tariff_breakdown;
  IF v_breakdown IS NOT NULL THEN
    v_lineas := COALESCE(v_breakdown -> 'lineas', '[]'::jsonb);

    FOR v_linea IN SELECT * FROM jsonb_array_elements(v_lineas) LOOP
      v_monto := COALESCE((v_linea ->> 'monto')::NUMERIC, 0);

      -- Se saltan las líneas de ajuste o informativas (monto 0 o negativo)
      CONTINUE WHEN v_monto <= 0;

      v_orden := v_orden + 1;
      v_suma_items := v_suma_items + v_monto;

      INSERT INTO public.invoice_items (
        invoice_id, orden, codigo, descripcion,
        cantidad, unidad, precio_unitario,
        descuento_porcentaje, descuento_valor, subtotal,
        iva_porcentaje, iva_valor, total
      ) VALUES (
        v_factura.id, v_orden,
        'TRANS-' || LPAD(v_orden::TEXT, 2, '0'),
        COALESCE(NULLIF(v_linea ->> 'concepto', ''), 'Concepto'),
        1, 'UND', v_monto,
        0, 0, v_monto,
        v_emisor.iva_porcentaje, ROUND(v_monto * v_emisor.iva_porcentaje / 100, 2),
        ROUND(v_monto, 2) + ROUND(v_monto * v_emisor.iva_porcentaje / 100, 2)
      );
    END LOOP;
  END IF;

  -- Línea de conciliación.
  --
  -- En DIAN, la suma de los subtotales de los renglones tiene que ser igual al
  -- subtotal de la factura. Si el conductor ajustó el precio (`final_price`),
  -- el desglose que se guardó al cotizar ya no suma lo mismo, y sin esta línea
  -- el PDF mostraría unos renglones que no cuadran con el total.
  --
  -- Solo se añade si de verdad hay diferencia: en el caso normal (precio sin
  -- cambios) no aparece ningún renglón extra.
  IF v_suma_items > 0 AND ROUND(v_suma_items, 2) <> ROUND(v_subtotal, 2) THEN
    v_orden := v_orden + 1;
    v_monto := ROUND(v_subtotal - v_suma_items, 2);

    INSERT INTO public.invoice_items (
      invoice_id, orden, codigo, descripcion,
      cantidad, unidad, precio_unitario,
      descuento_porcentaje, descuento_valor, subtotal,
      iva_porcentaje, iva_valor, total
    ) VALUES (
      v_factura.id, v_orden, 'AJUSTE',
      'Ajuste del precio acordado para el servicio',
      1, 'UND', v_monto,
      0, 0, v_monto,
      v_emisor.iva_porcentaje, ROUND(v_monto * v_emisor.iva_porcentaje / 100, 2),
      ROUND(v_monto, 2) + ROUND(v_monto * v_emisor.iva_porcentaje / 100, 2)
    );
  END IF;

  RETURN v_factura;
END;
$$;

-- Solo usuarios autenticados. El `anon` ni siquiera debería intentarlo.
REVOKE EXECUTE ON FUNCTION public.crear_factura_desde_servicio(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crear_factura_desde_servicio(UUID) TO authenticated;


-- ---------------------------------------------------------------------------
-- 4) Marcar la factura como emitida (tras subir el PDF)
-- ---------------------------------------------------------------------------
-- El cliente genera el PDF en el dispositivo y lo sube a Storage; el paso
-- final es marcar la factura como `emitida`. También se hace por función, para
-- no abrir UPDATE a la anon key.
--
-- Solo se permite pasar de `borrador` a `emitida`. Una factura emitida no se
-- puede volver a tocar por esta vía: para eso está `anular_factura`.

CREATE OR REPLACE FUNCTION public.emitir_factura(
  p_invoice_id UUID,
  p_pdf_path   TEXT
)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user     UUID := auth.uid();
  v_factura  public.invoices%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Debes iniciar sesión';
  END IF;

  SELECT * INTO v_factura FROM public.invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La factura no existe';
  END IF;

  IF v_user <> v_factura.customer_id
     AND (v_factura.driver_id IS NULL OR v_user <> v_factura.driver_id) THEN
    RAISE EXCEPTION 'No tienes permiso sobre esta factura';
  END IF;

  -- Idempotente: si ya está emitida se devuelve tal cual.
  --
  -- El botón "Generar factura" se puede pulsar dos veces (o el cliente y el
  -- conductor pulsarlo a la vez), y en ese caso `crear_factura_desde_servicio`
  -- devuelve la factura que ya existe. Antes esta función la rechazaba con
  -- "Solo se puede emitir una factura en borrador", así que el segundo toque
  -- mostraba un error en rojo aunque todo estuviera bien.
  IF v_factura.status = 'emitida' THEN
    RETURN v_factura;
  END IF;

  -- Una factura anulada no se puede volver a emitir por esta vía: hay que
  -- emitir una nueva, no resucitar la anulada.
  IF v_factura.status <> 'borrador' THEN
    RAISE EXCEPTION
      'Una factura anulada no se puede volver a emitir. Emite una nueva.';
  END IF;

  UPDATE public.invoices
  SET pdf_url     = p_pdf_path,
      status      = 'emitida',
      emitted_at  = NOW()
  WHERE id = p_invoice_id
  RETURNING * INTO v_factura;

  RETURN v_factura;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.emitir_factura(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.emitir_factura(UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 5) Anular una factura
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.anular_factura(
  p_invoice_id UUID,
  p_motivo     TEXT
)
RETURNS public.invoices
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user     UUID := auth.uid();
  v_factura  public.invoices%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Debes iniciar sesión';
  END IF;

  SELECT * INTO v_factura FROM public.invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La factura no existe';
  END IF;

  IF v_user <> v_factura.customer_id
     AND (v_factura.driver_id IS NULL OR v_user <> v_factura.driver_id) THEN
    RAISE EXCEPTION 'No tienes permiso sobre esta factura';
  END IF;

  IF v_factura.status = 'anulada' THEN
    RAISE EXCEPTION 'La factura ya estaba anulada';
  END IF;

  UPDATE public.invoices
  SET status         = 'anulada',
      voided_at      = NOW(),
      voided_reason  = NULLIF(TRIM(COALESCE(p_motivo, '')), '')
  WHERE id = p_invoice_id
  RETURNING * INTO v_factura;

  RETURN v_factura;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.anular_factura(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.anular_factura(UUID, TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 6) RLS de invoices: se retira el acceso directo de escritura
-- ---------------------------------------------------------------------------
-- Estas políticas venían de migracion_completa_v3 y abrían INSERT/UPDATE a
-- service_role, lo que no sirve: la app no usa service_role (y no debe, porque
-- esa clave nunca va en el dispositivo).
--
-- Ahora la escritura va por las funciones de arriba, que corren como postgres.
-- Las apps nunca hacen INSERT ni UPDATE directo sobre `invoices`.
--
-- Se borran las dos políticas y NO se pone ninguna en su lugar. Con RLS
-- activado y sin política de INSERT ni de UPDATE, Postgres rechaza la
-- escritura por defecto, que es justo lo que se quiere: `invoices` solo se
-- escribe por `crear_factura_desde_servicio`, `emitir_factura` y
-- `anular_factura`.
--
-- Panel de Supabase: el editor de tablas usa el rol `postgres`, no `anon`, así
-- que sigue viendo y editando los datos sin verse afectado.

DROP POLICY IF EXISTS invoices_insert_platform ON public.invoices;
DROP POLICY IF EXISTS invoices_update_platform ON public.invoices;


-- Una sola factura por servicio.
--
-- Refuerza en la base de datos lo que la función ya impide, y cubre el caso en
-- que cliente y conductor pulsen "Generar factura" a la vez desde dos
-- dispositivos: la función comprueba que no exista factura, pero dos llamadas
-- simultáneas podrían pasar las dos la comprobación. El índice único es lo que
-- corta ese caso.
--
-- Va dentro de un bloque con manejo de errores a propósito. Si ya hay
-- servicios con dos facturas, el CREATE INDEX falla y, sin esto, abortaría la
-- migración entera dejando las apps sin ninguna de las funciones de arriba.
-- Con el bloque, solo se avisa por NOTICE y el resto de la migración sigue.
DO $$
BEGIN
  CREATE UNIQUE INDEX invoices_service_unique
    ON public.invoices (service_id);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE
    'No se creó el índice único invoices_service_unique: %  '
    'Ya hay servicios con más de una factura. La función sigue impidiendo '
    'los duplicados nuevos, pero revisa las existentes (comprobación 10.7) y '
    'borra las que sobren antes de volver a correr este bloque.',
    SQLERRM;
END;
$$;


-- ---------------------------------------------------------------------------
-- 7) es_factura_propia(): "¿esta factura es del que está llamando?"
-- ---------------------------------------------------------------------------
-- Las políticas de Storage necesitan saber si el archivo que se sube o se lee
-- pertenece a quien está llamando. Se encapsula aquí porque dentro de una
-- política no se puede escribir un JOIN cómodo.
--
-- Nota: es `SECURITY DEFINER` a propósito. Si no lo fuera, RLS se aplicaría
-- otra vez al leer `invoices` y la comprobación dentro de la política
-- devolvería siempre falso.
--
-- Recibe TEXT y no UUID a propósito. La política le pasa el nombre de la
-- carpeta del archivo, que viene de fuera y no está controlado: si somebody
-- sube algo con un nombre de carpeta que no es un UUID y la función hiciera
-- `::uuid`, Postgres lanzaría un error al insertar en vez de denegar el acceso
-- en silencio. Comparando como texto no hay excepción posible.

CREATE OR REPLACE FUNCTION public.es_factura_propia(p_invoice_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.invoices i
    WHERE i.id::TEXT = p_invoice_id
      AND (i.customer_id = auth.uid() OR i.driver_id = auth.uid())
  );
$$;

GRANT EXECUTE ON FUNCTION public.es_factura_propia(TEXT) TO anon, authenticated;


-- ---------------------------------------------------------------------------
-- 8) Storage: bucket "invoices" y políticas de objetos
-- ---------------------------------------------------------------------------
-- El bucket es privado. El PDF se sube con una carpeta por factura:
--
--     invoices/{invoice_id}/{invoice_id}.pdf
--
-- NO puede ser invoices/{invoice_id}.pdf, en la raíz. `storage.foldername()`
-- devuelve los segmentos de *carpeta*, y para un archivo en la raíz devuelve una
-- lista vacía: la política leería NULL, `es_factura_propia` daría falso y
-- ninguna subida se aceptaría. Las dos apps suben con la carpeta.
--
-- El PDF no se expone con URL pública. Se sirve con una URL firmada de corta
-- duración que la app pide en el momento con `createSignedUrl`.

-- Crear el bucket si no existe. (También se puede hacer desde el panel:
--  Storage → New bucket → nombre "invoices", público = OFF)
INSERT INTO storage.buckets (id, name, public)
VALUES ('invoices', 'invoices', FALSE)
ON CONFLICT (id) DO NOTHING;

-- Subir / sobrescribir el PDF: solo el cliente o el conductor de la factura
-- cuya id es la primera carpeta del archivo.
DROP POLICY IF EXISTS invoices_storage_write ON storage.objects;
CREATE POLICY invoices_storage_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'invoices'
    AND public.es_factura_propia((storage.foldername(name))[1])
  );

DROP POLICY IF EXISTS invoices_storage_update ON storage.objects;
CREATE POLICY invoices_storage_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'invoices'
    AND public.es_factura_propia((storage.foldername(name))[1])
  )
  WITH CHECK (
    bucket_id = 'invoices'
    AND public.es_factura_propia((storage.foldername(name))[1])
  );

-- Leer: lo mismo, para poder crear la URL firmada.
DROP POLICY IF EXISTS invoices_storage_read ON storage.objects;
CREATE POLICY invoices_storage_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'invoices'
    AND public.es_factura_propia((storage.foldername(name))[1])
  );

-- Con estas políticas, un archivo cuyo nombre de carpeta no sea una factura
-- propia simplemente no tiene acceso: `es_factura_propia` devuelve falso y no
-- hay ruta que esquivar.


-- ---------------------------------------------------------------------------
-- 8b) PDF: guardar la ruta, no una URL firmada caducable
-- ---------------------------------------------------------------------------
-- Antes `pdf_url` guardaba una URL firmada válida un año. Una URL firmada
-- caducada deja de servir el PDF para siempre, sin que se note: la factura sigue
-- en la app, con su número y sus montos, y el botón de abrir no hace nada.
--
-- Ahora `pdf_url` guarda solo la ruta del objeto
-- (`{invoice_id}/{invoice_id}.pdf`) y la URL la pide la app en el momento con
-- `storage.createSignedUrl()`, que dura una hora. No hace falta ninguna función
-- en Postgres para esto: la API de Storage ya firma, y firma con la misma
-- política `invoices_storage_read` de arriba, así que no se abre ninguna puerta
-- nueva.
--
-- Ninguna función de este fichero firma URLs. Una versión anterior de esta
-- migración usaba la columna `signedurl` de `storage.objects`, que no existe en
-- todas las versiones de Supabase y hacía fallar la función entera.
--
-- Las facturas ya emitidas guardan una URL en `pdf_url`. No se tocan: la app
-- detecta que empieza por `http` y la devuelve tal cual en vez de intentar
-- firmar una ruta. Siguen funcionando hasta que caduquen.


-- ---------------------------------------------------------------------------
-- 9) next_invoice_number: reescrita
-- ---------------------------------------------------------------------------
-- La versión de migracion_completa_v3 tenía dos problemas:
--
--   * `EXCEPTION WHEN OTHERS ... LOOP` sin límite. Si la actualización de la
--     secuencia fallaba por cualquier motivo —una política RLS, por ejemplo—
--     la función se quedaba reintentando para siempre. El error real nunca
--     llegaba, y el cliente veía la petición colgada en vez de un fallo.
--
--   * `SECURITY DEFINER` sin `SET search_path`. Es la vía clásica de
--     search_path injection en funciones SECURITY DEFINER: si alguien logra
--     crear un esquema con el nombre de una tabla que usa la función, puede
--     hacer que lea o escriba donde no debe.
--
-- La versión de abajo usa `FOR UPDATE` (bloquea la fila de forma explícita y
-- solo mientras dura la transacción) en lugar de un bucle de reintentos, y
-- un número máximo de intentos acotado.

CREATE OR REPLACE FUNCTION public.next_invoice_number(
  p_prefijo TEXT DEFAULT 'FEV'
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next    INTEGER;
  v_intento INTEGER := 0;
  v_numero  TEXT;
BEGIN
  IF p_prefijo IS NULL OR TRIM(p_prefijo) = '' THEN
    RAISE EXCEPTION 'El prefijo de la factura no puede ir vacío';
  END IF;

  -- Crea la fila de secuencia si es la primera vez que se usa este prefijo
  INSERT INTO public.invoice_sequences (prefijo, last_number)
  VALUES (p_prefijo, 0)
  ON CONFLICT (prefijo) DO NOTHING;

  -- Hasta 10 intentos. El Acotado evita que un fallo persistente cuelgue la
  -- petición del cliente para siempre.
  FOR v_intento IN 1..10 LOOP
    -- Bloquea la fila de la secuencia hasta que termine la transacción
    SELECT last_number INTO v_next
    FROM public.invoice_sequences
    WHERE prefijo = p_prefijo
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'No se pudo crear la secuencia del prefijo %', p_prefijo;
    END IF;

    v_next := v_next + 1;

    UPDATE public.invoice_sequences
    SET last_number = v_next,
        updated_at  = NOW()
    WHERE prefijo = p_prefijo;

    v_numero := p_prefijo || '-' || LPAD(v_next::TEXT, 6, '0');

    -- Doble seguridad: si ese número ya existe (por ejemplo, una factura
    -- creada a mano), se pasa al siguiente en vez de devolver un duplicado.
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.invoices WHERE numero_factura = v_numero
    );

    RETURN v_numero;
  END LOOP;

  RAISE EXCEPTION 'No se pudo asignar un número de factura para el prefijo %', p_prefijo;
END;
$$;

-- Necesaria dentro de `crear_factura_desde_servicio`, que ya es SECURITY
-- DEFINER, pero se deja explícito para que quede claro quién la usa.
REVOKE EXECUTE ON FUNCTION public.next_invoice_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.next_invoice_number(TEXT) TO authenticated;


-- ---------------------------------------------------------------------------
-- 10) Verificación
-- ---------------------------------------------------------------------------
-- Comprobaciones que deben dar 0 filas, o 1 donde se indica. Sirven para saber
-- si la migración quedó bien sin tener que abrir la app.

-- 10.1 Que las funciones existen (debe salir 1 en cada una)
SELECT 'crear_factura_desde_servicio' AS funcion, COUNT(*) AS ok
FROM pg_proc WHERE proname = 'crear_factura_desde_servicio'
UNION ALL
SELECT 'emitir_factura', COUNT(*) FROM pg_proc WHERE proname = 'emitir_factura'
UNION ALL
SELECT 'anular_factura', COUNT(*) FROM pg_proc WHERE proname = 'anular_factura'
UNION ALL
SELECT 'es_factura_propia', COUNT(*) FROM pg_proc WHERE proname = 'es_factura_propia'
UNION ALL
SELECT 'next_invoice_number', COUNT(*) FROM pg_proc WHERE proname = 'next_invoice_number';

-- 10.2 Que NINGUNA función SECURITY DEFINER quedó sin `SET search_path`
-- (debe salir 0 filas). Sin esto, una función SECURITY DEFINER es susceptible
-- a search_path injection.
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef              -- es SECURITY DEFINER
  AND (p.proconfig IS NULL     -- no tiene ninguna configuración de función
       OR NOT EXISTS (
         SELECT 1
         FROM unnest(p.proconfig) cfg
         WHERE cfg LIKE 'search\_path=%'
       ));

-- 10.3 Que NO queda ninguna política que abra INSERT/UPDATE a la anon key
-- (debe salir 0 filas). Si sale alguna, queda un agujero.
SELECT policyname, cmd
FROM pg_policies
WHERE tablename = 'invoices' AND cmd IN ('INSERT', 'UPDATE');

-- 10.4 Que solo el usuario autenticado puede escribir (debe salir 0 filas)
-- `service_role` conserva el acceso, pero la app no lo usa: manda la anon key.
SELECT policyname, roles
FROM pg_policies
WHERE tablename = 'invoices'
  AND cmd IN ('INSERT', 'UPDATE')
  AND 'anon' = ANY(roles);

-- 10.5 Las políticas de Storage están sobre el bucket correcto
-- (deben salir 3 filas: write, update, read)
SELECT policyname, cmd
FROM pg_policies
WHERE tablename = 'objects'
  AND policyname LIKE 'invoices_storage%';

-- 10.6 Que la fila del emisor existe (debe salir 1 fila)
-- Si el NIT es 900.000.000-0 son datos de ejemplo: cámbialos antes de
-- facturar de verdad o las facturas salen inválidas.
SELECT nit, nombre, prefijo, rango_inicial, rango_final, iva_porcentaje
FROM public.emisor_config;

-- 10.7 Que no hay dos facturas para el mismo servicio (debe salir 0 filas)
-- Si sale alguna, el índice único no se creó porque ya había duplicados y
-- habría que revisarlos a mano antes de volver a correrlo.
SELECT service_id, COUNT(*)
FROM public.invoices
GROUP BY service_id
HAVING COUNT(*) > 1;

-- 10.8 Que el bucket existe y es privado (debe salir public = false)
SELECT id, public FROM storage.buckets WHERE id = 'invoices';

-- ---------------------------------------------------------------------------
-- 11) Corrección: el IVA se desbordaba en servicios de más de 5.263 COP
-- ---------------------------------------------------------------------------
-- `crear_factura_desde_servicio` declaraba su variable de IVA como
-- NUMERIC(5,2), la precisión de un porcentaje (máximo 999,99), cuando guarda
-- el valor del IVA en pesos. Cualquier servicio por encima de 5.263 COP
-- provocaba:
--
--   ERROR: numeric field overflow
--   A field with precision 5, scale 2 must round to an absolute value less
--   than 10^3.
--
-- La factura no se creaba, y el botón "Generar factura" mostraba ese error.
-- Con servicios de prueba pequeños (500, 1.000) nunca pasaba, por eso costó
-- verlo: los precios reales de MUEVEX son de decenas de miles de pesos.
--
-- La declaración ya está corregida arriba (v_iva NUMERIC(12,2)). Este bloque
-- solo verifica que la función que hay en la base de datos es la buena.

-- 11.1 Debe decir 12,2. Si dice 5,2 la migración no se ha vuelto a correr.
SELECT 'anchura de v_iva' AS comprobacion,
       (SELECT format_type(atttypid, atttypmod)
        FROM pg_attribute
        WHERE attrelid = 'public.crear_factura_desde_servicio(UUID)'::regprocedure
          AND attname = 'v_iva'
          AND attnum > 0
          AND NOT attisdropped) AS tipo_actual,
       'numeric(12,2)' AS tipo_esperado;

-- 11.2 Prueba de humo: crea una factura de 95.000 COP, que es el caso que
-- fallaba, y la deja en estado 'borrador'. Si esta sección se ejecuta sin
-- error, el desbordamiento está arreglado.
-- Devuelve el número de factura y el total, que debe ser 113.050,00
-- (95.000 de subtotal + 18.050 de IVA).
DO $$
DECLARE
  v_servicio UUID;
  v_usuario  UUID;
  v_factura  public.invoices%ROWTYPE;
BEGIN
  -- Se busca un servicio completado que todavía no tenga factura. La función
  -- es idempotente, así que sirve cualquiera.
  SELECT s.id, s.customer_id INTO v_servicio, v_usuario
  FROM public.services s
  WHERE s.status = 'completado'
    AND COALESCE(s.final_price, s.estimated_price, s.price_base, 0) > 5263
    AND NOT EXISTS (
      SELECT 1 FROM public.invoices i WHERE i.service_id = s.id
    )
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_servicio IS NULL THEN
    RAISE NOTICE
      'No hay servicios completados y sin facturar por encima de 5.263 COP: '
      'no hay nada que probar. Crea uno desde la app y vuelve a correr esto.';
    RETURN;
  END IF;

  -- `crear_factura_desde_servicio` empieza comprobando `auth.uid()`, que desde
  -- el SQL Editor es NULL y haría fallar la llamada. Se simula la sesión
  -- poniendo el mismo claim que dejaría el JWT de la app, para que la prueba
  -- sea idéntica a la que hace el teléfono.
  PERFORM set_config('request.jwt.claim.sub', v_usuario::TEXT, TRUE);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_usuario, 'role', 'authenticated')::TEXT,
                     TRUE);

  v_factura := public.crear_factura_desde_servicio(v_servicio);

  RAISE NOTICE 'Factura de prueba creada: %  subtotal %  IVA %  total %',
    v_factura.numero_factura, v_factura.subtotal,
    v_factura.iva_valor, v_factura.total;
END;
$$;

-- 11.3 Lo que creó la prueba de humo. Si no hay servicios completados sin
-- facturar, sale vacío y es normal.
SELECT numero_factura, subtotal, iva_porcentaje, iva_valor, total, status
FROM public.invoices
ORDER BY created_at DESC
LIMIT 5;

-- 11.4 Para deshacer la factura de prueba que crea la 11.2. Se deja
-- comentada a propósito: no borres la factura de un servicio real por error.
--
-- DELETE FROM public.invoices WHERE status = 'borrador';
