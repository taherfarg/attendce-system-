-- ============================================
-- SYSTEM SETTINGS FOR POLLUX AUTO ATTENDANCE
-- Run this in Supabase SQL Editor
-- ============================================

-- Clear existing settings (optional - be careful in production)
-- DELETE FROM public.system_settings;

-- 1. Office Location: Pollux Auto (Dubai)
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES (
  'office_location',
  '{"lat": 25.17334843606796, "lng": 55.37698469436122}',
  'Pollux Auto office GPS coordinates'
)
ON CONFLICT (setting_key) 
DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = now();

-- 2. Allowed Radius: 10 meters
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES (
  'allowed_radius_meters',
  '10',
  'Maximum distance from office in meters'
)
ON CONFLICT (setting_key) 
DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = now();

-- 3. Allowed WiFi Networks
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES (
  'wifi_allowlist',
  '["Pollux Auto-5G", "Pollux Auto-2G"]',
  'Allowed WiFi SSIDs for check-in'
)
ON CONFLICT (setting_key) 
DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = now();

-- 4. Working Hours (optional - for late detection)
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES (
  'working_hours',
  '{"start": "09:00", "end": "18:00"}',
  'Standard working hours'
)
ON CONFLICT (setting_key) 
DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = now();

-- 5. Admin notification settings
INSERT INTO public.system_settings (setting_key, setting_value, description)
VALUES (
  'admin_notifications',
  '{"enabled": true, "notify_on_checkin": true, "notify_on_checkout": true}',
  'Admin notification preferences'
)
ON CONFLICT (setting_key) 
DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = now();

-- ============================================
-- NOTIFICATIONS TABLE (for admin alerts)
-- ============================================

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL, -- 'check_in', 'check_out'
  title text NOT NULL,
  message text NOT NULL,
  data jsonb,
  is_read boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications (is_read);

-- RLS for notifications (admins only)
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Only admins can read notifications
CREATE POLICY "Admins can read notifications" ON public.notifications
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE users.id = auth.uid() 
      AND users.role = 'admin'
    )
  );

-- Only service role can insert (from Edge Functions)
CREATE POLICY "Service role can insert notifications" ON public.notifications
  FOR INSERT
  WITH CHECK (true);

-- Admins can mark as read
CREATE POLICY "Admins can update notifications" ON public.notifications
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE users.id = auth.uid() 
      AND users.role = 'admin'
    )
  );

-- Verify settings
SELECT * FROM public.system_settings;
