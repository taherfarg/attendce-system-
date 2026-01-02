-- ============================================
-- COMPLETE RLS FIX - Run this EXACTLY as is
-- ============================================

-- Step 1: Drop ALL existing policies on users table
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

-- Step 2: Create the is_admin function (SECURITY DEFINER bypasses RLS)
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

-- Step 3: Create simple, non-recursive policies

-- Allow users to see their own row
CREATE POLICY "allow_own_select" ON public.users
FOR SELECT USING (auth.uid() = id);

-- Allow admins to see all (using function to avoid recursion)  
CREATE POLICY "allow_admin_select" ON public.users
FOR SELECT USING (is_admin());

-- Allow admins to update
CREATE POLICY "allow_admin_update" ON public.users
FOR UPDATE USING (is_admin());

-- Allow insert for authenticated users (for signup)
CREATE POLICY "allow_insert" ON public.users
FOR INSERT WITH CHECK (auth.uid() = id);

-- Step 4: Ensure RLS is enabled
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Verify
SELECT 'SUCCESS! Policies fixed.' as status;
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'users';
