/// Attendance record model
class AttendanceModel {
  final String id;
  final String userId;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final String? formattedAddress;
  final Map<String, dynamic>? gpsCoordinates;
  final String? wifiSsid;
  final String status; // 'present', 'late', 'absent', 'early_out'
  final int totalMinutes;
  final String verificationMethod;
  final DateTime createdAt;

  AttendanceModel({
    required this.id,
    required this.userId,
    required this.checkInTime,
    this.checkOutTime,
    this.formattedAddress,
    this.gpsCoordinates,
    this.wifiSsid,
    required this.status,
    required this.totalMinutes,
    required this.verificationMethod,
    required this.createdAt,
  });

  /// Create from Supabase JSON response
  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    try {
      return AttendanceModel(
        id: json['id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        checkInTime: DateTime.parse(json['check_in_time']),
        checkOutTime: json['check_out_time'] != null
            ? DateTime.parse(json['check_out_time'])
            : null,
        formattedAddress: json['formatted_address'] as String?,
        gpsCoordinates: json['location_data'] as Map<String, dynamic>?,
        wifiSsid: json['wifi_ssid'] as String?,
        status: json['status'] as String? ?? 'present',
        totalMinutes: (json['total_minutes'] as num?)?.toInt() ?? 0,
        verificationMethod: json['verification_method'] as String? ?? 'face_id',
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
      );
    } catch (e) {
      throw FormatException('Error parsing AttendanceModel: $e');
    }
  }

  /// Check if this is a complete attendance record (has check-out)
  bool get isComplete => checkOutTime != null;

  /// Check if still checked in (Active)
  bool get isCheckedIn => checkOutTime == null;

  /// Get work duration as Duration object
  Duration get workDuration {
    if (checkOutTime == null) {
      return DateTime.now().difference(checkInTime);
    }
    return checkOutTime!.difference(checkInTime);
  }

  /// Get formatted work duration string (e.g., "8h 30m")
  String get formattedDuration {
    final duration = workDuration;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  /// Get status display text for UI
  String get statusDisplay {
    switch (status) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'absent':
        return 'Absent';
      case 'early_out':
        return 'Left Early';
      default:
        // Capitalize first letter
        if (status.isEmpty) return 'Unknown';
        return status[0].toUpperCase() + status.substring(1);
    }
  }

  /// Check if user was late (check-in after 9 AM by default)
  bool isLate({int workStartHour = 9}) {
    // Assuming checkInTime is already in local/Dubai time from repository or adjusted in utils
    return checkInTime.hour >= workStartHour;
  }

  /// Check if user left early (before 5 PM if totalMinutes < 8 hours)
  bool get isEarlyOut {
    if (!isComplete) return false;
    return totalMinutes < 480; // Less than 8 hours
  }
}
