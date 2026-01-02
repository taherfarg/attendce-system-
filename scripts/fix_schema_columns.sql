-- FIX SCHEMA: Add missing columns for attendance tracking
-- The Edge Function attempts to insert 'location_data' and 'wifi_ssid', but they don't exist.

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS location_data jsonb,
ADD COLUMN IF NOT EXISTS wifi_ssid text;

-- Verify columns exist
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'attendance';
