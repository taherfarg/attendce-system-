-- 1. Check Attendance Records for Today
SELECT id, user_id, check_in_time 
FROM attendance 
WHERE check_in_time >= CURRENT_DATE::timestamp;

-- 2. Check Users
SELECT id, name, role FROM users;

-- 3. Check for specific matches (Copy user_ids from step 1 result mentally, or use this join)
SELECT 
    a.id as attendance_id, 
    a.user_id as att_user_id, 
    u.name as user_name
FROM attendance a
LEFT JOIN users u ON a.user_id = u.id
WHERE a.check_in_time >= CURRENT_DATE::timestamp;

-- 4. Check Foreign Key Constraints on 'attendance' table
SELECT
    tc.table_schema, 
    tc.constraint_name, 
    tc.table_name, 
    kcu.column_name, 
    ccu.table_schema AS foreign_table_schema,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name 
FROM 
    information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name='attendance';
