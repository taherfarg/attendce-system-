import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/error_handler.dart';
import '../models/attendance_model.dart';
import 'package:flutter/foundation.dart';

class AttendanceRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> checkIn({
    required String userId,
    required List<double> faceEmbedding,
    required Map<String, dynamic> location,
    required Map<String, dynamic> wifiInfo,
  }) async {
    try {
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
        throw response.data?.toString() ?? 'Unknown error from server';
      }
    } catch (e) {
      debugPrint('Check-in Error: $e');
      throw AppErrorHandler.parse(e);
    }
  }

  Future<void> checkOut({
    required String userId,
    required List<double> faceEmbedding,
    required Map<String, dynamic> location,
    required Map<String, dynamic> wifiInfo,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'verify_attendance',
        body: {
          'user_id': userId,
          'face_embedding': faceEmbedding,
          'location': location,
          'wifi_info': wifiInfo,
          'type': 'check_out',
        },
      );

      if (response.status != 200) {
        throw response.data?.toString() ?? 'Unknown error from server';
      }
    } catch (e) {
      debugPrint('Check-out Error: $e');
      throw AppErrorHandler.parse(e);
    }
  }

  /// Returns sorted list of attendance history
  Future<List<AttendanceModel>> getHistory() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw 'User not authenticated';

      final List<dynamic> data = await _client
          .from('attendance')
          .select()
          .eq('user_id', userId)
          .order('check_in_time', ascending: false);

      return data.map((json) => AttendanceModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Fetch History Error: $e');
      throw AppErrorHandler.parse(e);
    }
  }
}
