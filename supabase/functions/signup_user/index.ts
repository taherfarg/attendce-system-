import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface SignupRequest {
  email: string
  password: string
  name: string
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SERVICE_ROLE_KEY')

    if (!serviceRoleKey) {
      return new Response(
        JSON.stringify({ success: false, error: 'Server configuration error' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    const body: SignupRequest = await req.json()
    const { email, password, name } = body

    if (!email || !password || !name) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required fields' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Use service role client to bypass RLS
    const supabaseClient = createClient(supabaseUrl, serviceRoleKey)

    // 1. Create auth user
    const { data: authData, error: authError } = await supabaseClient.auth.admin.createUser({
      email: email.trim(),
      password: password,
      email_confirm: true, // Auto-confirm email
    })

    if (authError || !authData.user) {
      console.error('Auth error:', authError)
      return new Response(
        JSON.stringify({ success: false, error: authError?.message || 'Failed to create user' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    const userId = authData.user.id

    // 2. Insert into users table (bypasses RLS with service role)
    const { error: insertError } = await supabaseClient
      .from('users')
      .insert({
        id: userId,
        name: name.trim(),
        role: 'employee',
        status: 'active', // 'pending' violated check constraint, changed to 'active'
        created_at: new Date().toISOString(),
      })

    if (insertError) {
      console.error('Insert error:', insertError)
      // Try to delete the auth user if profile creation fails
      await supabaseClient.auth.admin.deleteUser(userId)
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: `Failed to create user profile: ${insertError.message}`, 
          details: insertError 
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 3. Sign in the user to get a session token
    const anonClient = createClient(supabaseUrl, supabaseAnonKey)
    const { data: signInData, error: signInError } = await anonClient.auth.signInWithPassword({
      email: email.trim(),
      password: password,
    })

    if (signInError) {
      console.error('Sign-in error:', signInError)
      return new Response(
        JSON.stringify({ 
          success: true, 
          user_id: userId,
          message: 'Account created. Please sign in.',
          session: null
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        user_id: userId,
        session: signInData.session,
        message: 'Account created successfully'
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    console.error('Signup error:', error)
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
