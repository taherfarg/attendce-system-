-- Migration: Add face_embeddings array column for multi-pose enrollment
-- Date: 2026-01-06
-- Description: Adds a new column to store multiple face embeddings (one per pose)
--              for improved face recognition accuracy

-- Add the new face_embeddings column (array of embeddings)
ALTER TABLE face_profiles 
ADD COLUMN IF NOT EXISTS face_embeddings double precision[][] DEFAULT NULL;

-- Add a comment describing the column
COMMENT ON COLUMN face_profiles.face_embeddings IS 'Array of face embeddings from multiple poses (center, left, right) for improved matching accuracy';

-- Migrate existing single embeddings to array format
-- This preserves backward compatibility while upgrading existing users
UPDATE face_profiles 
SET face_embeddings = ARRAY[face_embedding]::double precision[][]
WHERE face_embedding IS NOT NULL 
  AND (face_embeddings IS NULL OR array_length(face_embeddings, 1) IS NULL);

-- Create an index for faster lookups (optional, based on query patterns)
-- CREATE INDEX IF NOT EXISTS idx_face_profiles_user_embeddings ON face_profiles(user_id);
