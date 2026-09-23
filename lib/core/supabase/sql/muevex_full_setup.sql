-- ============================================================
-- MUEVEX - Configuración completa de la base de datos
-- EJECUTA ESTE SCRIPT en: Supabase Dashboard > SQL Editor > New query
-- ============================================================

-- 1. Extensiones
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 2. Enums (deben crearse ANTES que las tablas que los usan)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role_enum') THEN
    CREATE TYPE user_role_enum AS ENUM ('customer', 'driver', 'admin');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vehicle_status_enum') THEN
    CREATE TYPE vehicle_status_enum AS ENUM ('offline', 'online', 'busy', 'offline_maintenance');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'service_status_enum') THEN
    CREATE TYPE service_status_enum AS ENUM (
      'REQUESTED', 'SEARCHING_DRIVER', 'DRIVER_ACCEPTED', 'DRIVER_ON_WAY',
      'DRIVER_ARRIVED', 'LOADING', 'IN_TRANSIT', 'ARRIVED_DESTINATION',
      'DELIVERED', 'CANCELLED', 'COMPLETED'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'offer_status_enum') THEN
    CREATE TYPE offer_status_enum AS ENUM ('pending', 'accepted', 'rejected');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status_enum') THEN
    CREATE TYPE payment_status_enum AS ENUM ('pending', 'completed', 'refunded', 'failed');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type_enum') THEN
    CREATE TYPE notification_type_enum AS ENUM (
      'service_request', 'offer', 'counter_offer', 'status_update',
      'delivery_complete', 'rating_received', 'system'
    );
  END IF;
END $$;

-- 3. Tabla: users
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email VARCHAR(255) NOT NULL,
  role user_role_enum NOT NULL DEFAULT 'customer',
  name VARCHAR(100),
  phone VARCHAR(20),
  is_email_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Tabla: customer_profiles
CREATE TABLE IF NOT EXISTS customer_profiles (
  id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  phone VARCHAR(20),
  rating DECIMAL(3, 2) DEFAULT 0.0,
  total_services INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Tabla: driver_profiles
CREATE TABLE IF NOT EXISTS driver_profiles (
  id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  vehicle_id UUID,
  license_number VARCHAR(50),
  rating DECIMAL(3, 2) DEFAULT 0.0,
  total_services INTEGER DEFAULT 0,
  is_verified BOOLEAN DEFAULT FALSE,
  status vehicle_status_enum DEFAULT 'offline',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Tabla: vehicles
CREATE TABLE IF NOT EXISTS vehicles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID REFERENCES driver_profiles(id) ON DELETE SET NULL,
  plate VARCHAR(20) NOT NULL,
  brand VARCHAR(100) NOT NULL,
  model VARCHAR(100) NOT NULL,
  capacity INTEGER DEFAULT 500,
  color VARCHAR(30),
  vehicle_type VARCHAR(50) DEFAULT 'motocarro',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Tabla: services
CREATE TABLE IF NOT EXISTS services (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES users(id) ON DELETE SET NULL,
  status service_status_enum DEFAULT 'REQUESTED',
  price_base DECIMAL(12, 2) DEFAULT 0.0,
  price_recommended DECIMAL(12, 2),
  price_offer DECIMAL(12, 2),
  origin_lat DECIMAL(10, 6) NOT NULL DEFAULT 0,
  origin_lng DECIMAL(10, 6) NOT NULL DEFAULT 0,
  destination_lat DECIMAL(10, 6) NOT NULL DEFAULT 0,
  destination_lng DECIMAL(10, 6) NOT NULL DEFAULT 0,
  origin TEXT,
  destination TEXT,
  distance_km DECIMAL(10, 2) DEFAULT 0,
  estimated_time_min INTEGER DEFAULT 0,
  description TEXT,
  load_type VARCHAR(50) DEFAULT 'muebles',
  needs_help BOOLEAN DEFAULT FALSE,
  floors INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- 8. Tabla: load_photos
CREATE TABLE IF NOT EXISTS load_photos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  uploaded_by VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Tabla: driver_offers
CREATE TABLE IF NOT EXISTS driver_offers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  price DECIMAL(12, 2) NOT NULL,
  status offer_status_enum DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(service_id, driver_id)
);

-- 10. Tabla: service_locations
CREATE TABLE IF NOT EXISTS service_locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES users(id),
  lat DECIMAL(10, 6) NOT NULL,
  lng DECIMAL(10, 6) NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- 11. Tabla: payments
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  amount DECIMAL(12, 2) NOT NULL,
  payment_method VARCHAR(50),
  status payment_status_enum DEFAULT 'pending',
  transaction_id VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. Tabla: notifications
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type notification_type_enum NOT NULL,
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  related_id UUID,
  related_type VARCHAR(50),
  read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. Tabla: ratings
CREATE TABLE IF NOT EXISTS ratings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  rater_id UUID NOT NULL REFERENCES users(id),
  rated_id UUID NOT NULL REFERENCES users(id),
  score NUMERIC(3, 2) CHECK (score >= 1 AND score <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. Índices
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_services_status ON services(status);
CREATE INDEX IF NOT EXISTS idx_services_customer ON services(customer_id);
CREATE INDEX IF NOT EXISTS idx_driver_offers_service ON driver_offers(service_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);

-- 15. Trigger para updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_customer_profiles_updated_at ON customer_profiles;
CREATE TRIGGER update_customer_profiles_updated_at BEFORE UPDATE ON customer_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_driver_profiles_updated_at ON driver_profiles;
CREATE TRIGGER update_driver_profiles_updated_at BEFORE UPDATE ON driver_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 16. ROW LEVEL SECURITY - HABILITADO para que la app funcione
-- Permite INSERT/SELECT a usuarios autenticados
-- ============================================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE services ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE load_photos ENABLE ROW LEVEL SECURITY;

-- POLÍTICAS (permiten acceso total durante desarrollo)
CREATE POLICY "Allow all" ON users FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON customer_profiles FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON driver_profiles FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON vehicles FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON services FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON driver_offers FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON payments FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON notifications FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON ratings FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON service_locations FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all" ON load_photos FOR ALL USING (true) WITH CHECK (true);

-- ============================================================
-- ACTUALIZA EL URL Y LA ANON KEY EN EL CÓDIGO DESPUÉS DE EJECUTAR
-- ============================================================
