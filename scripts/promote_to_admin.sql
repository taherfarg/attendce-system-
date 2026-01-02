-- PROMOTE USER TO ADMIN
-- Replace 'YOUR_USER_ID_HERE' with your actual User UUID from Supabase Authentication tab.

-- 1. Update the role in the 'users' table
UPDATE users 
SET role = 'admin' 
WHERE id = 'YOUR_USER_ID_HERE';

-- 2. Verify the change
SELECT * FROM users WHERE id = 'YOUR_USER_ID_HERE';

-- NOTE: You will need to logout and login again in the app for this to take effect.
