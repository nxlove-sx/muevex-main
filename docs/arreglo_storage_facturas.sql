-- ===========================================================================
-- MUEVEX — Arreglo de las políticas de Storage que bloqueaban el PDF
-- ===========================================================================
-- Pegar esto entero en Supabase → SQL Editor → New query → Run.
--
-- EL SÍNTOMA
--   El PDF de la factura nunca se sube. La factura sí se crea y sí se emite,
--   pero `pdf_url` queda apuntando a un archivo que no existe, y el visor
--   avisa "Esta factura todavía no tiene PDF guardado".
--
-- LA CAUSA (medida contra la base, no deducida)
--   La política de `storage.objects` que hay viva castea a UUID la ruta
--   ENTERA del archivo en vez del primer segmento. Comprobado con la anon key:
--
--     invoices/{id}.pdf              -> RLS deniega
--     invoices/basura/{id}.pdf       -> RLS deniega
--     invoices/{id}/{id}.pdf         -> ERROR: invalid input syntax for type
--                                        uuid: "{id}/{id}"
--     invoices/{id}/sub/{id}.pdf      -> ERROR: ... "{id}/sub/{id}"
--
--   Con un "/" en el medio, el valor casteado ya no es un UUID y Postgres
--   aborta la subida. O sea: NO existe ninguna forma de ruta que funcione con
--   la política actual. No es un caso raro ni un dato sucio, es que el paso
--   de subir el PDF es imposible.
--
-- LO QUE HACE ESTE SCRIPT
--   1. Localiza y elimina TODAS las políticas de `storage.objects` que tocan el
--      bucket 'invoices' o la función `es_factura_propia`. Hace falta quitar
--      la vieja: si queda, Postgres sigue evaluándola y el error continúa,
--      porque las políticas se combinan con OR y una que lanza aborta todo.
--   2. Crea un ayudante que saca el id de la factura de la ruta comparando
--      texto, sin castear a UUID nunca. Si alguien sube un archivo con un
--      nombre raro, la función dice "no" en vez de reventar la subida.
--   3. Recrea las políticas de lectura, inserción y actualización con ese
--      ayudante.
--
-- Es idempotente: se puede volver a correr las veces que haga falta.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1) Quitar las políticas viejas (incluida la que castea la ruta entera)
-- ---------------------------------------------------------------------------
-- Se descubren por texto en vez de por nombre porque el problema es
-- justamente que no sabemos qué nombre tienen: hay al menos una que no es
-- el que espera el script v4.
--
-- El filtro es conservador: no se toca ninguna política que mencione
-- 'service-loads', 'profiles' o 'vehicles', porque esas pertenecen a otros
-- buckets y borrarlas dejaría sin fotos de servicio ni avatars.

DO $$
DECLARE
  r           RECORD;
  v_texto     TEXT;
  v_borradas  TEXT := '';
BEGIN
  FOR r IN
    SELECT policyname, COALESCE(qual, '') AS q, COALESCE(with_check, '') AS w
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename   = 'objects'
  LOOP
    v_texto := r.q || ' ' || r.w;

    -- Solo las que hablan del bucket de facturas, de la función de propiedad,
    -- o que castean a UUID algo sacado de la ruta. Ese último caso se busca
    -- por patrón y no por texto fijo a propósito: la política culpable podría
    -- no mencionar la palabra 'invoices' en ninguna parte, y entonces este
    -- script no la encontraría, dejaría la culpable viva y el error seguiría
    -- apareciendo igual. Es justo el fallo que se está arreglando.
    IF v_texto NOT ILIKE '%invoices%'
       AND v_texto NOT ILIKE '%es_factura_propia%'
       AND NOT (v_texto ILIKE '%foldername%' AND v_texto ILIKE '%::uuid%') THEN
      CONTINUE;
    END IF;

    -- Si la política también cubre otro bucket, no es nuestra y se deja.
    IF v_texto ILIKE '%service-loads%'
       OR v_texto ILIKE '%profiles%'
       OR v_texto ILIKE '%vehicles%' THEN
      RAISE NOTICE 'Se conserva % (también cubre otro bucket)', r.policyname;
      CONTINUE;
    END IF;

    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
    v_borradas := v_borradas || ' ' || r.policyname;
  END LOOP;

  RAISE NOTICE 'Políticas del bucket invoices eliminadas:%',
               CASE WHEN v_borradas = '' THEN ' (ninguna)' ELSE v_borradas END;
END;
$$;


-- ---------------------------------------------------------------------------
-- 2) Sacar el id de la factura de la ruta
-- ---------------------------------------------------------------------------
-- El PDF se guarda como invoices/{invoice_id}/{invoice_id}.pdf, así que el id
-- es el PRIMER segmento de la ruta y ya está dentro de una columna TEXT: no
-- hay ningún motivo para castear a UUID.
--
-- Por qué NO se usa `storage.foldername(name)[1]`: es exactamente el punto
-- que fallaba. `foldername` es de la extensión de Storage, su comportamiento
-- ha cambiado entre versiones, y una política que dependa de eso es una
-- política que se rompe sin avisar. `split_part` es SQL estándar y siempre
-- devuelve lo mismo.
--
-- Con un archivo en la raíz (sin "/") `split_part` devuelve el nombre entero,
-- "algo.pdf", que no es el id de ninguna factura, así que el acceso se deniega
-- solo. No hace falta un caso especial para eso.

CREATE OR REPLACE FUNCTION public.invoice_id_de_la_ruta(p_name TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT split_part(COALESCE(p_name, ''), '/', 1);
$$;

GRANT EXECUTE ON FUNCTION public.invoice_id_de_la_ruta(TEXT) TO anon, authenticated;


-- Comprobación de que el ayudante hace lo que se espera, sin castear nada.
SELECT nombre, invoice_id_de_la_ruta(nombre) AS id_extraido, es_factura_propia(invoice_id_de_la_ruta(nombre)) AS propia
FROM (VALUES
  ('90830a17-4480-4ef0-867f-3f8edd8fee46/90830a17-4480-4ef0-867f-3f8edd8fee46.pdf', 'ruta normal'),
  ('basura/90830a17-4480-4ef0-867f-3f8edd8fee46.pdf',                              'carpeta ajena'),
  ('90830a17-4480-4ef0-867f-3f8edd8fee46.pdf',                                   'en la raíz'),
  ('no/es/un/uuid.pdf',                                                         'nombre sin uuid')
) AS t(nombre, descripcion);


-- ---------------------------------------------------------------------------
-- 3) Las políticas, ya sin castear a UUID
-- ---------------------------------------------------------------------------
-- Las cuatro, con el mismo criterio: el primer segmento de la ruta tiene que
-- ser el id de una factura que sea del usuario que pregunta.

-- Subir el PDF (INSERT): lo hace el cliente al pulsar "Generar factura".
DROP POLICY IF EXISTS invoices_storage_insert ON storage.objects;
CREATE POLICY invoices_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'invoices'
    AND public.es_factura_propia(public.invoice_id_de_la_ruta(name))
  );

-- Sobrescribir el PDF (UPDATE): `uploadBinary` usa upsert, así que una
-- segunda pulsación sobre la misma factura llega por aquí, no por INSERT.
DROP POLICY IF EXISTS invoices_storage_update ON storage.objects;
CREATE POLICY invoices_storage_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'invoices'
    AND public.es_factura_propia(public.invoice_id_de_la_ruta(name))
  )
  WITH CHECK (
    bucket_id = 'invoices'
    AND public.es_factura_propia(public.invoice_id_de_la_ruta(name))
  );

-- Leer el PDF (SELECT): "Ver PDF" y "Compartir" en el visor de factura.
DROP POLICY IF EXISTS invoices_storage_read ON storage.objects;
CREATE POLICY invoices_storage_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'invoices'
    AND public.es_factura_propia(public.invoice_id_de_la_ruta(name))
  );

-- NO se crea política de DELETE a propósito. La app no borra PDFs, y una
-- factura anulada tiene que conservar el suyo: es el respaldo de lo que se
-- facturó, y el día que haya que auditar un cobro esa prueba tiene que seguir
-- ahí. Si alguna vez hay que borrar un archivo, se hace desde el panel con la
-- cuenta de servicio, no abriendo el bucket a la anon key.

-- ---------------------------------------------------------------------------
-- Verificación
-- ---------------------------------------------------------------------------

-- V.1 El bucket tiene que existir. Si no sale esta fila, hay que crearlo.
SELECT id, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'invoices';

-- V.2 Las políticas que quedaron en el bucket, y una alarma por si alguna
-- sigue casteando la ruta a UUID. Esa columna tiene que salir vacía: si
-- `castea_uuid` dice 'SI', el error va a seguir apareciendo y el script no
-- atrapó a la política culpable.
SELECT policyname,
       cmd,
       CASE WHEN COALESCE(qual, '') || ' ' || COALESCE(with_check, '')
                 ILIKE '%foldername%'
            AND COALESCE(qual, '') || ' ' || COALESCE(with_check, '')
                 ILIKE '%::uuid%'
            THEN 'SI' ELSE 'no' END AS castea_uuid,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND (COALESCE(qual, '') || ' ' || COALESCE(with_check, ''))
      ILIKE '%invoices%'
ORDER BY policyname;

-- V.3 Lo que ve la app: las facturas del cliente de prueba. La que se creó
-- durante las pruebas tiene `status = 'emitida'` y `pdf_url` con una ruta que
-- aún no existe en Storage; eso es exactamente lo que arregla este script.
SELECT numero_factura, status, pdf_url, total
FROM public.invoices
ORDER BY created_at DESC
LIMIT 5;