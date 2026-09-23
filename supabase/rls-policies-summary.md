# MUEVEX - Row Level Security Policies Summary

## Políticas por Tabla

### users
- **SELECT**: `auth.uid() = id` (solo propio)
- **UPDATE**: `auth.uid() = id` (solo propio)

### customer_profiles
- **SELECT**: `auth.uid() = user_id` (solo cliente propietario)
- **INSERT**: `auth.uid() = user_id` (cliente crea su perfil)
- **UPDATE**: `auth.uid() = user_id` (cliente edita su perfil)

### driver_profiles
- **SELECT**: `auth.uid() = user_id` (solo conductor propietario)
- **INSERT**: `auth.uid() = user_id` (conductor crea perfil)
- **UPDATE**: `auth.uid() = user_id` (conductor edita perfil)

### vehicles
- **SELECT**: 
  - Drivers: `EXISTS (SELECT 1 FROM driver_profiles WHERE user_id = auth.uid() AND driver_profiles.id = vehicles.driver_id)`
  - Admins: `auth.role() = 'admin'`
- **INSERT**: 
  - `EXISTS (SELECT 1 FROM driver_profiles WHERE user_id = auth.uid() AND driver_profiles.id = vehicles.driver_id)`
  - Solo el conductor dueño puede insertar
- **UPDATE**: (Pending - implementar según necesidad)

### services
- **INSERT**: `auth.role() = 'customer'` (solo clientes pueden crear)
- **SELECT**: 
  - Customers: `auth.role() = 'customer' AND customer_id = auth.uid()`
  - Drivers: `auth.role() = 'driver' AND (driver_id = auth.uid() OR driver_id IS NULL)`
  - Admins: `auth.role() = 'admin'`
- **UPDATE**: `auth.role() = 'customer' AND customer_id = auth.uid()` (solo dueño cambia status)

### loads
- **INSERT**: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid())`
- **SELECT**: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid())`

### load_photos
- **INSERT**: `EXISTS (SELECT 1 FROM loads WHERE id = load_id AND service_id IN (SELECT id FROM services WHERE customer_id = auth.uid()))`
- **SELECT**: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND driver_id = auth.uid())`

### driver_offers
- **SELECT**: 
  - For service: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND driver_id = auth.uid())`
  - For customer's service: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid())`
- **INSERT**: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND driver_id = auth.uid())`

### service_locations
- **INSERT**: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid())`
- **SELECT**: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid())`

### ratings
- **SELECT**: `true` (todos pueden ver)
- **INSERT**: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid())`
- **UPDATE**: `auth.role() = 'admin'`

### payments
- **SELECT**: 
  - Own: `EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid())`
  - All: `auth.role() = 'admin'`
- **INSERT**: (Pending - typically system/partner inserts)

### notifications
- **SELECT**: `auth.uid() = user_id` (solo propio)
- **INSERT**: `true` (sistema puede insertar notificaciones)

## Buenas Prácticas Implementadas

1. **UUID como identificadores principales** - Todas las tablas usan `id UUID PRIMARY KEY DEFAULT uuid_generate_v4()`
2. **Timestamps automáticos** - `created_at TIMESTAMPTZ DEFAULT NOW()`, `updated_at TIMESTAMPTZ DEFAULT NOW()`
3. **Foreign keys con ON DELETE CASCADE** - Para mantener integridad referencial
4. **ENUM types definidos**: `user_role`, `service_status`, `load_type`, `driver_availability`
5. **Índices optimizados** para queries comunes (cliente, conductor, status, service_id)
6. **UNIQUE constraints** en fields críticos (users.email, vehicles.plate)
7. **RLS habilitado** en todas las tablas
8. **Políticas por rol**: Clientes, conductores y administradores tienen accesos separados
9. **Sin duplicación**: Cada tabla tiene un propósito claro y relaciones bien definidas
10. **Photos access controlled**: Las fotos tienen políticas que verifican pertenencia antes de permitir acceso

## Variables de Entorno Necesarias

Crear archivo `.env` o configurar en la plataforma:

```
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_ANON_KEY=tu-anon-key-aqui
```

Estos valores se usan en `lib/core/supabase/supabase_config.dart`.

## Próximos Pasos

1. Ejecutar `schema.sql` en el SQL Editor de Supabase Dashboard
2. Verificar que RLS esté habilitado en el dashboard
3. Probar las políticas con diferentes roles de usuario
4. Configurar Storage buckets en Supabase Storage
5. Probar flujo de autenticación registro/login