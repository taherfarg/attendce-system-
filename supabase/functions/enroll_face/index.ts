import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// CORS headers for web compatibility
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Structured logging helper
const log = (level: 'INFO' | 'WARN' | 'ERROR', message: string, data?: object) => {
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), level, message, ...data }));
}

// Expected embedding size (should match ML Kit model output)
const EXPECTED_EMBEDDING_SIZE = 128;

interface EnrollRequest {
  user_id: string;
  face_embedding?: number[];        // Single embedding (backward compat)
  face_embeddings?: number[][];     // Multi-pose embeddings array
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SERVICE_ROLE_KEY');

    if (!serviceRoleKey) {
      log('ERROR', 'Missing SERVICE_ROLE_KEY')
      return new Response(JSON.stringify({ error: 'Server configuration error' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
    }

    // Get the auth header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      log('WARN', 'Missing Authorization header')
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }

    // Create client with anon key for user auth verification
    const anonClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } }
    })

    // Verify the user
    const { data: { user }, error: userError } = await anonClient.auth.getUser()

    if (userError || !user) {
      log('ERROR', 'Authentication failed', { error: userError?.message })
      return new Response(JSON.stringify({ 
        error: 'Invalid or expired token',
        details: {
            message: userError?.message,
            authHeaderLen: authHeader.length,
            authHeaderPrefix: authHeader.substring(0, 10) + '...'
        }
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }

    // Create service role client for DB operations (bypasses RLS)
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey)

    const { user_id, face_embedding, face_embeddings } = await req.json() as EnrollRequest

    if (user.id !== user_id) {
      log('WARN', 'User ID mismatch', { token_user: user.id, request_user: user_id })
      return new Response(JSON.stringify({ error: 'Unauthorized to enroll for another user' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 })
    }

    // Handle multi-pose or single embedding
    let embeddingsArray: number[][] = [];
    let singleEmbedding: number[] | null = null;

    if (face_embeddings && Array.isArray(face_embeddings) && face_embeddings.length > 0) {
      // Multi-pose enrollment
      embeddingsArray = face_embeddings;
      singleEmbedding = face_embeddings[0]; // Use first for backward compat
      log('INFO', 'Multi-pose enrollment', { user_id, pose_count: face_embeddings.length });
    } else if (face_embedding && Array.isArray(face_embedding) && face_embedding.length > 0) {
      // Single embedding (backward compatible)
      singleEmbedding = face_embedding;
      embeddingsArray = [face_embedding]; // Wrap in array
      log('INFO', 'Single-pose enrollment', { user_id });
    } else {
      log('ERROR', 'Invalid embedding format', { user_id })
      return new Response(JSON.stringify({ error: 'Invalid face embedding format' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
    }

    // Validate embedding dimensions
    for (const emb of embeddingsArray) {
      if (emb.length !== EXPECTED_EMBEDDING_SIZE) {
        log('WARN', 'Embedding size mismatch', { expected: EXPECTED_EMBEDDING_SIZE, received: emb.length })
      }
    }

    log('INFO', 'Enrolling face profile', { user_id, embedding_count: embeddingsArray.length })

    // Upsert Profile using admin client - store both single and array for compatibility
    const { data, error } = await supabaseAdmin
        .from('face_profiles')
        .upsert({
            user_id: user_id,
            face_embedding: singleEmbedding,           // Single embedding (backward compat)
            face_embeddings: embeddingsArray,          // Array of all poses
            updated_at: new Date().toISOString()
        }, { onConflict: 'user_id' })
        .select()

    if (error) {
      log('ERROR', 'Database error during enrollment', { error: error.message })
      throw error
    }

    log('INFO', 'Enrollment successful', { user_id, poses_stored: embeddingsArray.length })
    return new Response(JSON.stringify({ 
      success: true, 
      message: 'Enrollment successful', 
      poses_stored: embeddingsArray.length 
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })

  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : 'Unknown error occurred';
    log('ERROR', 'Unexpected error', { error: errorMessage })
    return new Response(JSON.stringify({ error: errorMessage }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
  }
})
