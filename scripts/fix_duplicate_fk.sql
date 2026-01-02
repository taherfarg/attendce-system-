-- Remove the redundant foreign key constraint
ALTER TABLE attendance 
DROP CONSTRAINT fk_attendance_user;
