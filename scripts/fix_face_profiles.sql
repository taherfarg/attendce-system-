-- ============================================
-- FIX FACE PROFILES TABLE
-- Run this in Supabase SQL Editor
-- ============================================

-- 1. Make sure face_profiles table exists
CREATE TABLE IF NOT EXISTS public.face_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) UNIQUE,
  face_embedding jsonb NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now()
);

-- 2. Drop existing policies
DROP POLICY IF EXISTS "face_profiles_select" ON public.face_profiles;
DROP POLICY IF EXISTS "face_profiles_insert" ON public.face_profiles;
DROP POLICY IF EXISTS "face_profiles_update" ON public.face_profiles;
DROP POLICY IF EXISTS "Users can view own face profile" ON public.face_profiles;
DROP POLICY IF EXISTS "Service role can manage" ON public.face_profiles;

-- 3. Enable RLS
ALTER TABLE public.face_profiles ENABLE ROW LEVEL SECURITY;

-- 4. Create permissive policies for service role (Edge Functions)
-- Service role bypasses RLS, so we just need policies for users

-- Users can read their own face profile
CREATE POLICY "face_profiles_select_own" 
ON public.face_profiles FOR SELECT 
USING (auth.uid() = user_id);

-- Allow all authenticated users to insert their own
CREATE POLICY "face_profiles_insert_own" 
ON public.face_profiles FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own
CREATE POLICY "face_profiles_update_own" 
ON public.face_profiles FOR UPDATE 
USING (auth.uid() = user_id);

-- 5. Verify
SELECT 'Face profiles table ready!' as status;
SELECT * FROM public.face_profiles;
