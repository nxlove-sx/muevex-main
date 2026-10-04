-- ===========================================================================
-- MUEVEX — Arreglo del desbordamiento del IVA en la facturación
-- ===========================================================================
-- Pegar esto entero en Supabase → SQL Editor → New query → Run.
--
-- Corrige dos cosas:
--
--   1. `crear_factura_desde_servicio` declaraba `v_iva NUMERIC(5,2)`, que es la
--      precisión de un PORCENTAJE (máximo 999,99) y se estaba usando para
--      guardar el VALOR del IVA en pesos. Cualquier servicio por encima de
--      5.263 COP reventaba con `numeric field overflow` y no se creaba nada.
--
--   2. `emitir_factura` rechazaba una factura que ya estaba emitida, así que
--      pulsar dos veces "Generar factura" ponía un error rojo falso. Ahora es
--      idempotente: si ya está emitida la devuelve tal cual.
--
-- Es idempotente: se puede volver a correr las veces que haga falta.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1) La función que crea la factura
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
  -- abortaba la factura entera con "numeric field overflow". El error salía de
  -- la función y no de ninguna columna, así que no se veía leyendo la
  -- definición de las tablas.
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
-- 2) Marcar la factura como emitida (tras subir el PDF)
-- ---------------------------------------------------------------------------
-- El cliente genera el PDF en el dispositivo y lo sube a Storage; el paso
-- final es marcar la factura como `emitida`. También se hace por función, para
-- no abrir UPDATE a la anon key.
--
-- Idempotente: si ya está emitida se devuelve tal cual, para que pulsar dos
-- veces "Generar factura" no produzca un error rojo falso. Una factura ANULADA
-- sí que no se puede volver a emitir por esta vía.

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


-- ===========================================================================
-- Verificación
-- ===========================================================================

-- V.1 Debe decir numeric(12,2). Si dice numeric(5,2) este script no corrió.
SELECT '1. tipo de v_iva' AS comprobacion,
       (SELECT format_type(atttypid, atttypmod)
        FROM pg_attribute
        WHERE attrelid = 'public.crear_factura_desde_servicio(UUID)'::regprocedure
          AND attname = 'v_iva'
          AND attnum > 0
          AND NOT attisdropped) AS valor,
       'numeric(12,2)' AS esperado;

-- V.2 Prueba de humo: crea una factura de un servicio real, que es el caso que
-- fallaba. Si sale el NOTICE con un número de factura, el arreglo funcionó.
--
-- Busca un servicio completado, sin factura, y por encima de 5.263 COP. Como
-- `crear_factura_desde_servicio` comprueba `auth.uid()` y desde el SQL Editor
-- eso es NULL, se simula la sesión del cliente con el mismo claim que dejaría
-- el JWT de la app, para que la prueba sea idéntica a la que hace el teléfono.
--
-- La factura que cree queda en estado 'borrador' y se borra con
-- docs/limpiar_prueba_facturacion.sql.
DO $$
DECLARE
  v_servicio UUID;
  v_usuario  UUID;
  v_factura  public.invoices%ROWTYPE;
BEGIN
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
      'No hay servicios completados sin facturar por encima de 5.263 COP: '
      'no hay nada que probar aquí. Instala la app y prueba con un servicio real.';
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_usuario::TEXT, TRUE);
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_usuario, 'role', 'authenticated')::TEXT,
                     TRUE);

  v_factura := public.crear_factura_desde_servicio(v_servicio);

  RAISE NOTICE
    'OK — Factura % creada. Subtotal %  IVA %  total %',
    v_factura.numero_factura, v_factura.subtotal,
    v_factura.iva_valor, v_factura.total;
END;
$$;

-- V.3 Lo que ve la prueba de humo: las últimas facturas.
SELECT numero_factura, subtotal, iva_porcentaje, iva_valor, total, status
FROM public.invoices
ORDER BY created_at DESC
LIMIT 5;
