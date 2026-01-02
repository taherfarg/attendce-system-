import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class TimeUtils {
  static const String _dubaiTimeZone = 'Asia/Dubai';

  /// Initialize timezone database - must be called in main()
  static void initialize() {
    tz_data.initializeTimeZones();
  }

  /// Convert any DateTime to Dubai time (UTC+4)
  static DateTime toDubai(DateTime dateTime) {
    try {
      final dubaiLocation = tz.getLocation(_dubaiTimeZone);
      return tz.TZDateTime.from(dateTime, dubaiLocation);
    } catch (e) {
      // Fallback if TZ data fails: UTC+4
      return dateTime.toUtc().add(const Duration(hours: 4));
    }
  }

  /// Get current time in Dubai
  static DateTime nowDubai() {
    return toDubai(DateTime.now());
  }
}
