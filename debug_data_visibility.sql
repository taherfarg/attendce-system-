-- DEBUG SCRIPT: Open up attendance table visibility
-- WARNING: This is for debugging only.

ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;

-- 1. Drop existing policies
DROP POLICY IF EXISTS "attendance_select_own" ON attendance;
DROP POLICY IF EXISTS "attendance_select_admin" ON attendance;
DROP POLICY IF EXISTS "attendance_select_all_debug" ON attendance;

-- 2. Create a "Permissive" policy
-- This allows anyone (logged in) to see ALL attendance records
CREATE POLICY "attendance_select_all_debug" 
ON attendance 
FOR SELECT 
USING (true);

-- 3. Verify
SELECT * FROM pg_policies WHERE tablename = 'attendance';

-- 4. Check if data exists (for your own sanity in SQL Editor)
SELECT count(*) as total_records FROM attendance;
