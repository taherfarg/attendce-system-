import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> checkIn({
    required String userId,
    required List<double> faceEmbedding,
    required Map<String, dynamic> location,
    required Map<String, dynamic> wifiInfo,
  }) async {
    final response = await _client.functions.invoke(
      'verify_attendance',
      body: {
        'user_id': userId,
        'face_embedding': faceEmbedding,
        'location': location,
        'wifi_info': wifiInfo,
        'type': 'check_in',
      },
    );

    if (response.status != 200) {
      // Parse error message
      throw Exception('Check-in failed: ${response.data}');
    }
  }

  Future<void> checkOut({
    required String userId,
    required List<double>
    faceEmbedding, // Even checkout might need verification if stricter
    required Map<String, dynamic> location,
    required Map<String, dynamic> wifiInfo,
  }) async {
    final response = await _client.functions.invoke(
      'verify_attendance',
      body: {
        'user_id': userId,
        'face_embedding': faceEmbedding,
        'type': 'check_out',
        // We might relax location/wifi for checkout or fail if they left?
        // Generally we want to allow checkout even if outside to stop clock,
        // but maybe flag it. For now, pass same data.
        'location': location,
        'wifi_info': wifiInfo,
      },
    );

    if (response.status != 200) {
      throw Exception('Check-out failed: ${response.data}');
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final userId = _client.auth.currentUser!.id;
    return await _client
        .from('attendance')
        .select()
        .eq('user_id', userId)
        .order('check_in_time', ascending: false);
  }
}
