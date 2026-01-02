-- Enable RLS on attendance table
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "attendance_select_own" ON attendance;
DROP POLICY IF EXISTS "attendance_select_admin" ON attendance;
DROP POLICY IF EXISTS "attendance_insert_service" ON attendance; -- Just in case

-- Allow users to view their OWN attendance records
CREATE POLICY "attendance_select_own" 
ON attendance 
FOR SELECT 
USING (auth.uid() = user_id);

-- Allow admins to view ALL attendance records
CREATE POLICY "attendance_select_admin" 
ON attendance 
FOR SELECT 
USING (is_admin());

-- Verify policies
SELECT * FROM pg_policies WHERE tablename = 'attendance';
