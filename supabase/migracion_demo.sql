-- ============================================================
-- MUEVEX - MIGRACIÓN PARA DEMO EN VIVO
-- ============================================================
-- Ejecuta este script en el SQL Editor del Supabase Dashboard
-- (https://vuglqlpwwuwkvevxqlja.supabase.co)
--
-- Corrige 2 problemas que impedían el flujo de cliente:
--   1) Falta de política de INSERT en la tabla `users` (el registro
--      de una cuenta nueva era rechazado por RLS).
--   2) Añade las columnas extra del modelo Service a la tabla
--      `services` para que la app pueda leer/mostrar peso, tipo,
--      fotos, etc.
-- ============================================================

-- (1) PERMITIR AL USUARIO AUTO-REGISTRARSE: política de INSERT en users
--     auth.uid() == id, de modo que la app inserta su propio perfil.
CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- (2) AÑADIR columnas extra del modelo Service a la tabla services
--     (todas con DEFAULT para no romper las filas existentes).
ALTER TABLE services
  ADD COLUMN IF NOT EXISTS load_photos   TEXT[]       DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS load_details  JSONB        DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS load_weight   NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS load_type     VARCHAR(50)  DEFAULT 'muebles',
  ADD COLUMN IF NOT EXISTS recommended_price NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS needs_help    BOOLEAN      DEFAULT FALSE;

-- (OPCIONAL) Desactivar confirmación de email para pruebas en vivo:
-- En el Dashboard: Authentication -> Providers -> Email -> desmarcar
-- "Confirm email". Si lo mantienes activo, deberás confirmar el correo
-- de cada cuenta de prueba antes de iniciar sesión.

-- ============================================================
-- (OPCIONAL) Datos de ejemplo: un conductor de prueba + un usuario
-- cliente de prueba, para que la demo tenga "movimiento".
-- Revisa que el email exista antes de ejecutar (evita duplicados).
-- ============================================================
-- INSERT INTO users (id, email, name, role)
-- VALUES
--   (gen_random_uuid(), 'conductor@muevex.com', 'Conductor Demo', 'driver'),
--   (gen_random_uuid(), 'cliente@muevex.com',   'Cliente Demo',   'customer');
