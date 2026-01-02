-- ============================================
-- COMPLETE SETUP FOR PRODUCTION
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- PART 1: FIX RLS POLICIES
-- ============================================

-- Drop all existing policies on users table
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'users' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.users', pol.policyname);
    END LOOP;
END $$;

-- Create admin check function
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE(
    (SELECT role = 'admin' FROM public.users WHERE id = auth.uid()),
    false
  );
$$;

-- Simple policies
CREATE POLICY "users_select_own" ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "users_select_admin" ON public.users FOR SELECT USING (is_admin());
CREATE POLICY "users_update_admin" ON public.users FOR UPDATE USING (is_admin());
CREATE POLICY "users_insert_self" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- ============================================
-- PART 2: SYSTEM SETTINGS (Pollux Auto)
-- ============================================

-- Office Location
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES ('office_location', '{"lat": 25.17334843606796, "lng": 55.37698469436122}', 'Pollux Auto office GPS')
ON CONFLICT (setting_key) DO UPDATE SET setting_value = EXCLUDED.setting_value;

-- 10 meter radius
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES ('allowed_radius_meters', '10', 'Maximum distance from office')
ON CONFLICT (setting_key) DO UPDATE SET setting_value = EXCLUDED.setting_value;

-- Allowed WiFi
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES ('wifi_allowlist', '["Pollux Auto-5G", "Pollux Auto-2G"]', 'Allowed WiFi SSIDs')
ON CONFLICT (setting_key) DO UPDATE SET setting_value = EXCLUDED.setting_value;

-- Admin notifications
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES ('admin_notifications', '{"enabled": true, "notify_on_checkin": true, "notify_on_checkout": true}', 'Notification settings')
ON CONFLICT (setting_key) DO UPDATE SET setting_value = EXCLUDED.setting_value;

-- ============================================
-- PART 3: NOTIFICATIONS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  data jsonb,
  is_read boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_created ON public.notifications (created_at DESC);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_select" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update" ON public.notifications;

CREATE POLICY "notifications_select" ON public.notifications FOR SELECT USING (is_admin());
CREATE POLICY "notifications_insert" ON public.notifications FOR INSERT WITH CHECK (true);
CREATE POLICY "notifications_update" ON public.notifications FOR UPDATE USING (is_admin());

-- ============================================
-- PART 4: CREATE EMPLOYEE USER (Taher Farg)
-- ============================================

-- First create user in Supabase Dashboard:
-- Email: taher@polluxauto.com
-- Password: 123456

-- Then run this to add to users table:
INSERT INTO public.users (id, name, role, status, created_at)
SELECT 
  id, 
  'Taher Farg', 
  'employee',  -- EMPLOYEE role
  'active',
  now()
FROM auth.users 
WHERE email = 'taher@polluxauto.com'
ON CONFLICT (id) DO UPDATE SET 
  name = 'Taher Farg',
  role = 'employee',
  status = 'active';

-- ============================================
-- PART 5: CREATE ADMIN USER
-- ============================================

-- Create admin in Dashboard:
-- Email: admin@polluxauto.com
-- Password: admin123

INSERT INTO public.users (id, name, role, status, created_at)
SELECT 
  id, 
  'Admin', 
  'admin',  -- ADMIN role
  'active',
  now()
FROM auth.users 
WHERE email = 'admin@polluxauto.com'
ON CONFLICT (id) DO UPDATE SET 
  name = 'Admin',
  role = 'admin',
  status = 'active';

-- ============================================
-- VERIFY SETUP
-- ============================================

SELECT 'SETUP COMPLETE!' as status;
SELECT * FROM public.system_settings;
SELECT id, name, role, status FROM public.users;
