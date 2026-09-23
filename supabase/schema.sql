-- ============================================================
-- SUPABASE DATABASE SCHEMA FOR MUEVEX
-- ============================================================
-- Ejecuta este script en el SQL Editor de Supabase Dashboard
-- ============================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ENUMS PARA ESTADOS Y TIPOS
-- PostgreSQL no soporta "IF NOT EXISTS" en CREATE TYPE, por eso se usa DO $$ $$.

-- Enum para roles de usuario
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE user_role AS ENUM ('customer', 'driver', 'admin');
  END IF;
END $$;

-- Enum para estados del servicio
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'service_status') THEN
    CREATE TYPE service_status AS ENUM (
      'REQUESTED',
      'SEARCHING_DRIVER', 
      'DRIVER_ACCEPTED',
      'DRIVER_ON_WAY',
      'DRIVER_ARRIVED',
      'LOADING',
      'IN_TRANSIT',
      'ARRIVED_DESTINATION',
      'DELIVERED',
      'CANCELLED',
      'COMPLETED'
    );
  END IF;
END $$;

-- Enum para tipos de carga
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'load_type') THEN
    CREATE TYPE load_type AS ENUM ('muebles', 'electrodomesticos', 'cajas', 'otros');
  END IF;
END $$;

-- Enum para disponibilidad conductor
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'driver_availability') THEN
    CREATE TYPE driver_availability AS ENUM ('available', 'unavailable', 'busy');
  END IF;
END $$;

-- 3. TABLA: users (auth.users es gestionado por Supabase Auth, esta es la perfilación)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255), -- Se usa Supabase Auth para la autenticación
  name VARCHAR(255),
  phone VARCHAR(20),
  role user_role NOT NULL DEFAULT 'customer',
  is_email_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. TABLA: customer_profiles
CREATE TABLE IF NOT EXISTS customer_profiles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  phone VARCHAR(20),
  address TEXT,
  rating NUMERIC(3, 2) DEFAULT 0,
  total_services INTEGER DEFAULT 0,
  profile_photo_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. TABLA: driver_profiles
CREATE TABLE IF NOT EXISTS driver_profiles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  is_verified BOOLEAN DEFAULT FALSE,
  rating NUMERIC(3, 2) DEFAULT 0,
  total_services INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. TABLA: vehicles (un conductor puede tener varios vehículos, pero típicamente uno principal)
CREATE TABLE IF NOT EXISTS vehicles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID REFERENCES driver_profiles(id) ON DELETE CASCADE,
  plate VARCHAR(20) NOT NULL,
  brand VARCHAR(100) NOT NULL,
  model VARCHAR(100) NOT NULL,
  type VARCHAR(50) NOT NULL, -- motocarro, furgoneta, etc.
  capacity_kg INTEGER NOT NULL DEFAULT 500,
  photos TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(plate)
);

-- 7. TABLA: services
CREATE TABLE IF NOT EXISTS services (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  driver_id UUID REFERENCES users(id) ON DELETE SET NULL,
  status service_status NOT NULL DEFAULT 'REQUESTED',
  price_base NUMERIC(10, 2) DEFAULT 0,
  price_total NUMERIC(10, 2) DEFAULT 0,
  price_offer NUMERIC(10, 2),
  origin_lat NUMERIC(10, 6),
  origin_lng NUMERIC(10, 6),
  destination_lat NUMERIC(10, 6),
  destination_lng NUMERIC(10, 6),
  description TEXT,
  distance_km NUMERIC(10, 2) DEFAULT 0,
  estimated_time_min INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- 8. TABLA: loads
CREATE TABLE IF NOT EXISTS loads (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID REFERENCES services(id) ON DELETE CASCADE NOT NULL,
  description TEXT NOT NULL,
  type load_type NOT NULL DEFAULT 'muebles',
  weight_kg NUMERIC(10, 2) DEFAULT 0,
  dimensions TEXT, -- "ancho x alto x profundo"
  needs_help BOOLEAN DEFAULT FALSE,
  floors INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. TABLA: load_photos
CREATE TABLE IF NOT EXISTS load_photos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  load_id UUID REFERENCES loads(id) ON DELETE CASCADE NOT NULL,
  storage_path TEXT NOT NULL, -- Ruta en Supabase Storage
  order_index INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. TABLA: driver_offers
CREATE TABLE IF NOT EXISTS driver_offers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID REFERENCES services(id) ON DELETE CASCADE NOT NULL,
  driver_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  price NUMERIC(10, 2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, accepted, rejected
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. TABLA: service_locations
CREATE TABLE IF NOT EXISTS service_locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID REFERENCES services(id) ON DELETE CASCADE NOT NULL,
  type VARCHAR(20) NOT NULL, -- 'origin' o 'destination'
  latitude NUMERIC(10, 6) NOT NULL,
  longitude NUMERIC(10, 6) NOT NULL,
  label VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. TABLA: ratings
CREATE TABLE IF NOT EXISTS ratings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID REFERENCES services(id) ON DELETE CASCADE,
  rater_id UUID NOT NULL, -- usuario que califica
  rated_id UUID NOT NULL, -- usuario que es calificado
  score NUMERIC(2, 1) CHECK (score >= 1 AND score <= 5), -- 1.0 a 5.0
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(service_id, rater_id, rated_id)
);

-- 13. TABLA: payments
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_id UUID REFERENCES services(id) ON DELETE CASCADE NOT NULL,
  amount NUMERIC(10, 2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, completed, failed, refunded
  payment_method VARCHAR(50), -- credit_card, debit_card, cash, transfer
  transaction_id VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  paid_at TIMESTAMPTZ
);

-- 14. TABLA: notifications
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  type VARCHAR(50) NOT NULL, -- offer_received, offer_accepted, status_update, rating, etc.
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 15. ÍNDICES PARA PERFORMANCE
-- Índices en users para búsquedas por email
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Índices en servicios por cliente y conductor
CREATE INDEX IF NOT EXISTS idx_services_customer ON services(customer_id);
CREATE INDEX IF NOT EXISTS idx_services_driver ON services(driver_id);
CREATE INDEX IF NOT EXISTS idx_services_status ON services(status);

-- Índices en cargas por servicio
CREATE INDEX IF NOT EXISTS idx_loads_service ON loads(service_id);

-- Índices en ofertas por servicio y conductor
CREATE INDEX IF NOT EXISTS idx_driver_offers_service ON driver_offers(service_id);
CREATE INDEX IF NOT EXISTS idx_driver_offers_driver ON driver_offers(driver_id);

-- Índices en calificaciones
CREATE INDEX IF NOT EXISTS idx_ratings_service ON ratings(service_id);
CREATE INDEX IF NOT EXISTS idx_ratings_rated ON ratings(rated_id);

-- Índices en pagos
CREATE INDEX IF NOT EXISTS idx_payments_service ON payments(service_id);

-- Índices en notificaciones
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read);

-- 16. POLÍTICAS DE SEGURIDAD (Row Level Security - RLS)
-- Habilitar RLS en todas las tablas

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE services ENABLE ROW LEVEL SECURITY;
ALTER TABLE loads ENABLE ROW LEVEL SECURITY;
ALTER TABLE load_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- POLÍTICAS PARA users (solo acceso propio o admin)
CREATE POLICY "Users can view own profile" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

-- POLÍTICAS PARA customer_profiles
CREATE POLICY "Customers can view own profile" ON customer_profiles
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Customers can insert own profile" ON customer_profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Customers can update own profile" ON customer_profiles
  FOR UPDATE USING (auth.uid() = user_id);

-- POLÍTICAS PARA driver_profiles
CREATE POLICY "Drivers can view own profile" ON driver_profiles
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Drivers can insert own profile" ON driver_profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Drivers can update own profile" ON driver_profiles
  FOR UPDATE USING (auth.uid() = user_id);

-- POLÍTICAS PARA vehicles
CREATE POLICY "Drivers can view own vehicles" ON vehicles
  FOR SELECT USING (auth.uid() = (SELECT user_id FROM driver_profiles WHERE id = vehicles.driver_id));

CREATE POLICY "Drivers can insert own vehicle" ON vehicles
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM driver_profiles WHERE user_id = auth.uid() AND driver_profiles.id = vehicles.driver_id)
  );

CREATE POLICY "Admins can view all vehicles" ON vehicles
  FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- POLÍTICAS PARA services
CREATE POLICY "Customers can create services" ON services
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'customer'));

CREATE POLICY "Customers can view own services" ON services
  FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'customer') AND customer_id = auth.uid());

CREATE POLICY "Drivers can view assigned services" ON services
  FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'driver') AND (driver_id = auth.uid() OR driver_id IS NULL));

CREATE POLICY "Admins can view all services" ON services
  FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "Customers can update own service status" ON services
  FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'customer') AND customer_id = auth.uid());

-- POLÍTICAS PARA loads
CREATE POLICY "Customers can create loads" ON loads
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid()));

CREATE POLICY "Customers can view own loads" ON loads
  FOR SELECT USING (EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid()));

-- POLÍTICAS PARA load_photos
CREATE POLICY "Customers can upload load photos" ON load_photos
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM loads WHERE id = load_id AND service_id IN (SELECT id FROM services WHERE customer_id = auth.uid())));

CREATE POLICY "Drivers can view load photos" ON load_photos
  FOR SELECT USING (EXISTS (SELECT 1 FROM services WHERE id = service_id AND driver_id = auth.uid()));

-- POLÍTICAS PARA driver_offers
CREATE POLICY "Drivers can view offers for their services" ON driver_offers
  FOR SELECT USING (EXISTS (SELECT 1 FROM services WHERE id = service_id AND driver_id = auth.uid()));

CREATE POLICY "Drivers can insert offers" ON driver_offers
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM services WHERE id = service_id AND driver_id = auth.uid()));

CREATE POLICY "Customers can view offers on their services" ON driver_offers
  FOR SELECT USING (EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid()));

-- POLÍTICAS PARA service_locations
CREATE POLICY "Customers can create service locations" ON service_locations
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid()));

CREATE POLICY "Customers can view own service locations" ON service_locations
  FOR SELECT USING (EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid()));

-- POLÍTICAS PARA ratings
CREATE POLICY "Anyone can view ratings" ON ratings
  FOR SELECT USING (true);

CREATE POLICY "Customers can insert ratings" ON ratings
  FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid()));

CREATE POLICY "Admins can update ratings" ON ratings
  FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- POLÍTICAS PARA payments
CREATE POLICY "Customers can view own payments" ON payments
  FOR SELECT USING (EXISTS (SELECT 1 FROM services WHERE id = service_id AND customer_id = auth.uid()));

CREATE POLICY "Admins can view all payments" ON payments
  FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- POLÍTICAS PARA notifications
CREATE POLICY "Users can view own notifications" ON notifications
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "System can insert notifications" ON notifications
  FOR INSERT WITH CHECK (true);

-- ============================================================
-- VIEW: Active services summary (opcional)
-- ============================================================
CREATE OR REPLACE VIEW active_services AS
SELECT 
  s.id,
  s.customer_id,
  s.driver_id,
  s.status,
  s.price_base,
  s.price_total,
  s.price_offer,
  s.distance_km,
  s.estimated_time_min,
  s.created_at,
  s.completed_at,
  c.phone AS customer_phone,
  d.plate AS driver_plate,
  v.brand || ' ' || v.model AS vehicle_info
FROM services s
  LEFT JOIN users c ON s.customer_id = c.id
  LEFT JOIN users d ON s.driver_id = d.id
  LEFT JOIN vehicles v ON v.driver_id = d.id
WHERE s.status NOT IN ('DELIVERED', 'CANCELLED');