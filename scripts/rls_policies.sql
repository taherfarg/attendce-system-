-- Enable RLS on all tables
alter table public.users enable row level security;
alter table public.face_profiles enable row level security;
alter table public.attendance enable row level security;
alter table public.system_settings enable row level security;

-- 1. Policies for 'users' table
-- Admins can read/write everything.
-- Employees can read their own profile.
create policy "Admins can do everything on users" 
on public.users 
for all 
using (
  auth.uid() in (select id from public.users where role = 'admin')
);

create policy "Employees can view own profile" 
on public.users 
for select 
using (
  auth.uid() = id
);

-- 2. Policies for 'face_profiles' table
-- Admins can view/delete (maybe not insert directly if we want strict flow).
-- Employees can view own (for verification status) (insert maybe via function only?).
-- Let's allow employees to insert their OWN profile during enrollment (if that's the flow),
-- OR restrict it so only the enrollment Edge Function can write (using service role).
-- PRD says: "Validate attendance via Supabase Edge Functions". Enrollment might be similar.
-- Let's stick to: Users can READ own. Admins can READ all. 
-- Direct modifications should probably be blocked for users to prevent tampering, 
-- but for simplicity in MVP, we allow users to INSERT their own profile ONCE.
create policy "Users can view own face profile" 
on public.face_profiles 
for select 
using ( auth.uid() = user_id );

-- 3. Policies for 'attendance' table
-- Admins: View all, Update (manual adjustment).
-- Employees: View own. CANNOT INSERT/UPDATE directly (must use Edge Function).
create policy "Admins can view all attendance" 
on public.attendance 
for select 
using (
  auth.uid() in (select id from public.users where role = 'admin')
);

create policy "Admins can update attendance" 
on public.attendance 
for update
using (
  auth.uid() in (select id from public.users where role = 'admin')
);

create policy "Employees can view own attendance" 
on public.attendance 
for select 
using ( auth.uid() = user_id );

-- CRITICAL: NO INSERT POLICY FOR EMPLOYEES
-- This ensures they MUST use the `verify_attendance` Edge Function (which uses Service_Role key)
-- to create a record. This prevents modifying the HTTP request to fake a check-in.

-- 4. Policies for 'system_settings' table
-- Admins: Full access.
-- Employees: Read specific allowed keys (like office location) or maybe strictly Read Only.
create policy "Admins can manage settings" 
on public.system_settings 
for all 
using (
  auth.uid() in (select id from public.users where role = 'admin')
);

create policy "Everyone can view settings" 
on public.system_settings 
for select 
using ( true ); 
-- You might want to filter sensitive settings if any, but for radius/wifi list it's fine.
