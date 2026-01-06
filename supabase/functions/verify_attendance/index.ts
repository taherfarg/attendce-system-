import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// CORS headers for web compatibility
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Types
interface AttendanceRequest {
  user_id: string;
  face_embedding?: number[];
  qr_code?: string;
  location: { lat: number; lng: number };
  wifi_info: { ssid: string; bssid: string };
  type: 'check_in' | 'check_out';
}

// Structured logging helper
const log = (level: 'INFO' | 'WARN' | 'ERROR', message: string, data?: object) => {
  console.log(JSON.stringify({ timestamp: new Date().toISOString(), level, message, ...data }));
}

// Helper to send notification to all admins
const notifyAdmins = async (
  supabaseClient: any, 
  type: 'check_in' | 'check_out', 
  userName: string, 
  details: object
) => {
  try {
    // Get notification settings
    const { data: settingsData } = await supabaseClient
      .from('system_settings')
      .select('setting_value')
      .eq('setting_key', 'admin_notifications')
      .single();
    
    const notifSettings = settingsData?.setting_value || { enabled: true };
    
    if (!notifSettings.enabled) {
      log('INFO', 'Admin notifications disabled');
      return;
    }

    if ((type === 'check_in' && !notifSettings.notify_on_checkin) ||
        (type === 'check_out' && !notifSettings.notify_on_checkout)) {
      return;
    }

    // Create notification record for admins
    const message = type === 'check_in' 
      ? `${userName} checked in` 
      : `${userName} checked out`;

    await supabaseClient
      .from('notifications')
      .insert({
        type: type,
        title: type === 'check_in' ? '🟢 Check-In' : '🔴 Check-Out',
        message: message,
        data: details,
        created_at: new Date().toISOString()
      });

    log('INFO', 'Admin notification sent', { type, userName });
  } catch (err) {
    log('WARN', 'Failed to send admin notification', { error: String(err) });
    // Don't throw - notification failure shouldn't block attendance
  }
}

serve(async (req) => {
  log('INFO', 'Starting verify_attendance [VERSION: 2.2 - QR Support]')

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

    // 1. Authorization Check
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      log('WARN', 'Missing Authorization header')
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }

    // Extract JWT token from Authorization header
    const token = authHeader.replace('Bearer ', '');
    
    if (!token || token === authHeader) {
      log('WARN', 'Invalid Authorization header format')
      return new Response(JSON.stringify({ error: 'Invalid Authorization header format. Expected: Bearer <token>' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }

    // Create client with anon key for user auth verification
    const anonClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } }
    })

    // Verify User Token using the extracted JWT
    const { data: { user }, error: userError } = await anonClient.auth.getUser(token)
    
    if (userError || !user) {
      log('ERROR', 'Auth failed', { error: userError?.message, code: userError?.code })
      return new Response(JSON.stringify({ 
        error: `Authentication failed: ${userError?.message || 'User session not found'}`, 
        code: userError?.code,
        hint: 'Please sign out and sign in again to refresh your session.',
        details: {
            message: userError?.message,
            code: userError?.code,
            tokenLen: token.length,
        }
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 })
    }

    // Initialize Supabase Client (Service Role needed for secure reads/writes)
    // This client bypasses RLS
    const supabaseClient = createClient(supabaseUrl, serviceRoleKey)

    log('INFO', 'User authenticated', { user_id: user.id })

    const body: AttendanceRequest = await req.json()
    const { user_id, face_embedding, qr_code, location, wifi_info, type } = body

    if (user.id !== user_id) {
       log('WARN', 'User ID mismatch', { token_user: user.id, request_user: user_id })
       return new Response(JSON.stringify({ error: 'User ID mismatch' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 })
    }

    log('INFO', 'Processing attendance', { type, user_id, method: qr_code ? 'QR' : 'FACE' })

    // Fetch user name for notifications
    const { data: userData } = await supabaseClient
      .from('users')
      .select('name')
      .eq('id', user_id)
      .single();
    const userName = userData?.name || user.email || 'Employee';

    // 2. Fetch System Settings
    const { data: settings, error: settingsError } = await supabaseClient
      .from('system_settings')
      .select('setting_key, setting_value')
    
    if (settingsError) throw settingsError

    // Helper to get setting
    const getSetting = (key: string) => settings.find(s => s.setting_key === key)?.setting_value

    const officeLocation = getSetting('office_location') // { lat, lng }
    const allowedRadius = getSetting('allowed_radius_meters') // number
    const allowedWifiList = getSetting('wifi_allowlist') // string[]
    const activeQrSecret = getSetting('active_qr_secret') // string

    // 3. Validate Location (Haversine Formula)
    const getDistanceFromLatLonInM = (lat1: number, lon1: number, lat2: number, lon2: number) => {
      var R = 6371; // Radius of the earth in km
      var dLat = deg2rad(lat2-lat1);
      var dLon = deg2rad(lon2-lon1); 
      var a = 
        Math.sin(dLat/2) * Math.sin(dLat/2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * 
        Math.sin(dLon/2) * Math.sin(dLon/2)
        ; 
      var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
      var d = R * c; // Distance in km
      return d * 1000; // in meters
    }
    const deg2rad = (deg: number) => deg * (Math.PI/180)

    // Track validation flags for check-out
    let locationFlag = 'valid';
    let wifiFlag = 'valid';

    if (officeLocation) {
        const dist = getDistanceFromLatLonInM(location.lat, location.lng, officeLocation.lat, officeLocation.lng)
        if (dist > (allowedRadius || 100)) {
            // For check-out, just flag but don't block
            if (type === 'check_out') {
                locationFlag = 'outside_radius';
                log('WARN', 'Check-out from outside radius', { distance: Math.round(dist), allowed: allowedRadius })
            } else {
                log('WARN', 'Location invalid for check-in', { distance: Math.round(dist), allowed: allowedRadius })
                return new Response(JSON.stringify({ success: false, error: 'LOCATION_INVALID', message: `You are ${Math.round(dist)}m away. Max allowed: ${allowedRadius}m.` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
            }
        }
    }

    // 4. Validate Wi-Fi
    if (allowedWifiList) {
        if (!allowedWifiList.includes(wifi_info.ssid)) {
            // For check-out, just flag but don't block
            if (type === 'check_out') {
                wifiFlag = 'unauthorized';
                log('WARN', 'Check-out from unauthorized WiFi', { ssid: wifi_info.ssid })
            } else {
                log('WARN', 'WiFi not authorized for check-in', { ssid: wifi_info.ssid })
                return new Response(JSON.stringify({ success: false, error: 'WIFI_INVALID', message: `Wi-Fi ${wifi_info.ssid} not authorized.` }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
            }
        }
    }

    let verificationMethod = 'face_id_secure';

    // 5. Verification Strategy: QR Code OR Face ID
    if (qr_code) {
        // --- QR CODE VERIFICATION ---
        if (!activeQrSecret) {
            log('ERROR', 'No active QR secret configured on server')
            return new Response(JSON.stringify({ success: false, error: 'SERVER_CONFIG_ERROR', message: 'QR Code verification not configured.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
        }

        if (qr_code !== activeQrSecret) {
            log('WARN', 'Invalid QR Code scanned', { provided: qr_code })
            return new Response(JSON.stringify({ success: false, error: 'INVALID_QR', message: 'Invalid QR Code.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
        }
        
        verificationMethod = 'qr_code';
        log('INFO', 'QR Code verified successfully')

    } else if (face_embedding) {
        // --- FACE ID VERIFICATION ---
        
        const { data: faceProfile, error: faceError } = await supabaseClient
            .from('face_profiles')
            .select('face_embedding, face_embeddings')
            .eq('user_id', user_id)
            .single()
        
        if (faceError || !faceProfile) {
            log('ERROR', 'Face profile not found', { user_id })
            return new Response(JSON.stringify({ success: false, error: 'NO_FACE_PROFILE', message: 'User verification profile not found.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
        }

        // Use multi-pose embeddings if available, fallback to single embedding
        const storedEmbeddings: number[][] = faceProfile.face_embeddings && faceProfile.face_embeddings.length > 0
            ? faceProfile.face_embeddings 
            : faceProfile.face_embedding 
                ? [faceProfile.face_embedding]
                : [];

        if (storedEmbeddings.length === 0) {
            log('ERROR', 'No stored embeddings found', { user_id })
            return new Response(JSON.stringify({ success: false, error: 'NO_FACE_PROFILE', message: 'User verification profile not found.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
        }

        // Validate dimensions match
        if (storedEmbeddings[0].length !== face_embedding.length) {
            log('ERROR', 'Embedding dimension mismatch', { stored: storedEmbeddings[0].length, provided: face_embedding.length })
            return new Response(JSON.stringify({ success: false, error: 'EMBEDDING_MISMATCH', message: 'Face data format invalid. Please re-enroll your face.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
        }

        // Cosine similarity function - measures directional alignment of embeddings
        const cosineSimilarity = (a: number[], b: number[]): number => {
            let dot = 0, normA = 0, normB = 0;
            for (let i = 0; i < a.length; i++) {
                dot += a[i] * b[i];
                normA += a[i] * a[i];
                normB += b[i] * b[i];
            }
            if (normA === 0 || normB === 0) return 0;
            return dot / (Math.sqrt(normA) * Math.sqrt(normB));
        };

        // Compare against ALL stored embeddings, use BEST match
        let bestDistance = Infinity;
        let bestSimilarity = -1;
        let bestPoseIndex = 0;

        for (let poseIdx = 0; poseIdx < storedEmbeddings.length; poseIdx++) {
            const storedEmb = storedEmbeddings[poseIdx];
            
            // Euclidean distance
            let sum = 0;
            for (let i = 0; i < storedEmb.length; i++) {
                sum += Math.pow(storedEmb[i] - face_embedding[i], 2);
            }
            const distance = Math.sqrt(sum);
            
            // Cosine similarity
            const similarity = cosineSimilarity(storedEmb, face_embedding);
            
            if (distance < bestDistance) {
                bestDistance = distance;
                bestSimilarity = similarity;
                bestPoseIndex = poseIdx;
            }
        }

        // STRICT thresholds - ML Kit embeddings are geometric, not identity-based
        // Euclidean: Lower = more similar (0 = identical)
        // Cosine: Higher = more similar (1 = identical direction)
        const DISTANCE_THRESHOLD = storedEmbeddings.length > 1 ? 0.25 : 0.20;
        const SIMILARITY_THRESHOLD = 0.92;

        log('INFO', 'Face comparison result', {
            bestDistance: bestDistance.toFixed(4),
            bestSimilarity: bestSimilarity.toFixed(4),
            distanceThreshold: DISTANCE_THRESHOLD,
            similarityThreshold: SIMILARITY_THRESHOLD,
            matchedPose: bestPoseIndex + 1,
            totalPoses: storedEmbeddings.length
        });

        // DUAL CHECK: Must pass BOTH distance AND similarity thresholds
        if (bestDistance > DISTANCE_THRESHOLD || bestSimilarity < SIMILARITY_THRESHOLD) {
            log('WARN', 'Face verification FAILED', { 
                bestDistance: bestDistance.toFixed(4), 
                bestSimilarity: bestSimilarity.toFixed(4),
                distanceOk: bestDistance <= DISTANCE_THRESHOLD,
                similarityOk: bestSimilarity >= SIMILARITY_THRESHOLD,
                posesTested: storedEmbeddings.length 
            })
            return new Response(JSON.stringify({ 
                success: false, 
                error: 'FACE_MISMATCH', 
                message: `Face verification failed. Your face does not match the enrolled profile.`,
                debug: {
                    distance: bestDistance.toFixed(3),
                    similarity: bestSimilarity.toFixed(3),
                    distanceThreshold: DISTANCE_THRESHOLD,
                    similarityThreshold: SIMILARITY_THRESHOLD
                }
            }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
        }

        log('INFO', 'Face verified successfully', { 
            bestDistance: bestDistance.toFixed(4), 
            bestSimilarity: bestSimilarity.toFixed(4),
            matchedPose: bestPoseIndex + 1,
            totalPoses: storedEmbeddings.length
        })

    } else {
        log('ERROR', 'No verification data provided')
        return new Response(JSON.stringify({ success: false, error: 'MISSING_DATA', message: 'Face data or QR code required.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
    }

    // 6. Handle Check-In or Check-Out
    if (type === 'check_out') {
        // CHECK-OUT: Find and update existing open record (do NOT create a new one)
        const { data: latest, error: findError } = await supabaseClient
            .from('attendance')
            .select('id, check_in_time')
            .eq('user_id', user_id)
            .is('check_out_time', null)
            .order('check_in_time', { ascending: false })
            .limit(1)
            .single()
        
        if (findError && findError.code !== 'PGRST116') {
             // PGRST116 means "no rows found" - that's expected when there's no active check-in
             // Any other error is a real database problem
             log('ERROR', 'Database error finding check-in', { error: findError.message })
             return new Response(JSON.stringify({ success: false, error: 'DATABASE_ERROR', message: 'Failed to check attendance status.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
        }

        if (!latest) {
             log('WARN', 'No active check-in found', { user_id })
             return new Response(JSON.stringify({ success: false, error: 'NO_ACTIVE_CHECKIN', message: 'No active check-in found to check out from.' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 })
        }

        const checkOutTime = new Date();
        const checkInTime = new Date(latest.check_in_time);
        const duration = (checkOutTime.getTime() - checkInTime.getTime()) / 1000 / 60; // minutes

        const { error: updateError } = await supabaseClient
            .from('attendance')
            .update({ 
                check_out_time: checkOutTime.toISOString(),
                total_minutes: Math.round(duration),
                status: 'present'
             })
            .eq('id', latest.id)

        if (updateError) {
            log('ERROR', 'Database update failed', { error: updateError.message })
            throw updateError
        }

        // Send notification to admins
        await notifyAdmins(supabaseClient, 'check_out', userName, {
           user_id,
           total_minutes: Math.round(duration),
           time: checkOutTime.toISOString(),
           location: locationFlag,
           wifi: wifiFlag,
           method: verificationMethod
        });

        log('INFO', 'Check-out successful', { user_id, total_minutes: Math.round(duration), locationFlag, wifiFlag })
        return new Response(JSON.stringify({ 
            success: true, 
            message: 'Check-out successful', 
            total_minutes: Math.round(duration),
            flags: { location: locationFlag, wifi: wifiFlag }
        }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })

    } else {
        // CHECK-IN: Create a new attendance record
        const { data: insertData, error: insertError } = await supabaseClient
            .from('attendance')
            .insert({
                user_id,
                check_in_time: new Date().toISOString(),
                status: 'present',
                location_data: location,
                wifi_ssid: wifi_info.ssid,
                verification_method: verificationMethod
            })
            .select()
            .single()

        if (insertError) {
          log('ERROR', 'Database insert failed', { error: insertError.message })
          throw insertError
        }

        // Send notification to admins for check-in
        await notifyAdmins(supabaseClient, 'check_in', userName, {
          user_id,
          time: new Date().toISOString(),
          location: location,
          wifi: wifi_info.ssid,
          method: verificationMethod
        });

        log('INFO', 'Check-in successful', { user_id })
        return new Response(JSON.stringify({ success: true, message: 'Check-in successful', data: insertData }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 })
    }

  } catch (err: any) {
    const errorDetails = err?.message || err?.error || err;
    log('ERROR', 'Unexpected error', { error: errorDetails, fullError: err })
    
    // Ensure we return a JSON object, even if err is a string
    const responseBody = typeof errorDetails === 'object' 
        ? { error: errorDetails.message || 'Unknown error', details: errorDetails }
        : { error: String(errorDetails) };

    return new Response(JSON.stringify(responseBody), { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
        status: 500 
    })
  }
})
