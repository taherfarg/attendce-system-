-- Enable necessary extensions
create extension if not exists "uuid-ossp";

-- Users Table (Extends Supabase Auth)
-- Note: We generally handle user creation via triggers on auth.users, but for this standalone schema we define the public profile table.
create table public.users (
  id uuid references auth.users not null primary key,
  name text not null,
  role text not null check (role in ('admin', 'employee')) default 'employee',
  status text not null check (status in ('active', 'inactive')) default 'active',
  created_at timestamptz default now()
);

-- Face Profiles Table
-- Stores the biometric embedding. 
-- In a real scenario, 'embedding' might be a vector type if using pgvector. 
-- For now, we store it as a float array (jsonb or arrays) or encrypted text. 
-- Let's use validation: 'embedding' should be populated.
create table public.face_profiles (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.users(id) not null,
  -- We assume embedding is a JSON array of floats for compatibility, 
  -- or an encrypted string if strictly following "Encrypt biometric data".
  -- Let's stick to JSONB for flexibility in this schema, representing the vector.
  face_embedding jsonb not null, 
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id)
);

-- System Settings Table
-- Single row configuration or multi-row if we want multiple offices in future (Phase 2).
-- For now, we can assume a single configuration or key-value pairs. 
-- Let's go with a singleton-style row or a flexible config key-value.
-- Given requirements: "office_location", "allowed_radius", "allowed_wifi".
create table public.system_settings (
  id uuid default uuid_generate_v4() primary key,
  setting_key text not null unique,
  setting_value jsonb not null, -- Flexible to store lat/long object, list of SSIDs, etc.
  description text,
  updated_at timestamptz default now()
);

-- Initialize default settings (Example)
-- insert into public.system_settings (setting_key, setting_value) values 
-- ('office_location', '{"lat": 25.2048, "lng": 55.2708}'),
-- ('allowed_radius_meters', '50'),
-- ('wifi_allowlist', '["Office_Wifi_5G", "Guest_Wifi"]');

-- Attendance Table
create table public.attendance (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.users(id) not null,
  check_in_time timestamptz not null default now(),
  check_out_time timestamptz,
  formatted_address text, -- Human readable address snapshot
  gps_coordinates point, -- Or jsonb {"lat":..., "lng":...}
  wifi_ssid text,
  wifi_bssid text,
  status text check (status in ('present', 'late', 'absent', 'early_out')) default 'present',
  total_minutes int default 0,
  -- Metadata to prove verification happened
  verification_method text default 'face_id', 
  created_at timestamptz default now()
);

-- Indexing
create index idx_attendance_user_id on public.attendance(user_id);
create index idx_attendance_date on public.attendance(check_in_time);
