# MUEVEX - Guía de Configuración de Backend (Supabase)

## Paso 1: Crear proyecto Supabase (si no tienes uno)

1. Ve a **https://supabase.com** y crea una cuenta (gratuita)
2. Haz clic en **"New project"**
3. Dale un nombre (ej: `muevex`)
4. Configura la **Database Password** (guárdala)
5. Elige una región cercana a tus usuarios (ej: `us-east-1` o `South America`)
6. Espera a que termine de crearse (~2 min)

## Paso 2: Ejecutar el SQL

1. En el dashboard, ve a **SQL Editor** (menú izquierdo)
2. Haz clic en **"New query"**
3. Copia TODO el contenido del archivo:
   ```
   lib\core\supabase\sql\muevex_full_setup.sql
   ```
4. Pega el contenido y haz clic en **"Run"** (o Ctrl+Enter)
5. Debe mostrar "Success. No rows returned" o similar en verde

## Paso 3: Obtener URL y anon key

1. En el dashboard, ve a **Settings** (engranaje) > **API**
2. Copia el valor de **Project URL** (ej: `https://xxxx.supabase.co`)
3. Copia el valor de **anon public** key (o **anon** key)
   - Es la key larga que empieza con `eyJhbGciOi...`

## Paso 4: Desactivar confirmación de email (opcional pero recomendado)

Para que el registro funcione de inmediato:

1. Ve a **Authentication** > **Providers** > **Email**
2. Desactiva **"Confirm email"** (hasta que quieras activarlo)
3. Marca también **"Allow new users to sign up"**

## Paso 5: Actualizar el código

1. Dime aquí los valores de:
   - **Project URL** (el `https://...supabase.co`)
   - **anon key**

2. Yo los actualizo en los archivos:
   - `lib\core\supabase\supabase_client.dart`
   - `lib\core\supabase\supabase_config.dart`

3. Reconstruyo el APK y lo instalo en tu teléfono

## Paso 6: Probar

1. Abre la app MUEVEX
2. Regístrate con un email y contraseña
3. Inicia sesión
