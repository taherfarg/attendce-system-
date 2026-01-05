import 'package:geolocator/geolocator.dart';
import 'dart:math' show cos, sqrt, asin, pi;

/// Service for handling GPS location operations
class LocationService {
  /// Check and request location permissions
  Future<bool> checkAndRequestPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Get current GPS coordinates
  Future<Map<String, double>> getCurrentLocation() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw LocationException('Location permission denied');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      return {'lat': position.latitude, 'lng': position.longitude};
    } catch (e) {
      throw LocationException('Failed to get location: $e');
    }
  }

  /// Calculate distance between two coordinates in meters using Haversine formula
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    const double earthRadius = 6371000; // meters

    final dLat = _toRadians(endLat - startLat);
    final dLng = _toRadians(endLng - startLng);

    final a =
        _haversine(dLat) +
        cos(_toRadians(startLat)) * cos(_toRadians(endLat)) * _haversine(dLng);

    final c = 2 * asin(sqrt(a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  double _haversine(double radians) {
    final sinHalf = (1 - cos(radians)) / 2;
    return sinHalf;
  }

  /// Check if current location is within allowed radius of office
  Future<LocationCheckResult> isWithinOfficeRadius({
    required double officeLat,
    required double officeLng,
    required double allowedRadiusMeters,
  }) async {
    final currentLocation = await getCurrentLocation();

    final distance = calculateDistance(
      currentLocation['lat']!,
      currentLocation['lng']!,
      officeLat,
      officeLng,
    );

    return LocationCheckResult(
      isWithinRadius: distance <= allowedRadiusMeters,
      distanceMeters: distance,
      currentLat: currentLocation['lat']!,
      currentLng: currentLocation['lng']!,
    );
  }

  /// Check if device is using mock/fake location
  Future<bool> isMockLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      return position.isMocked;
    } catch (e) {
      return false;
    }
  }
}

/// Result of location check against office
class LocationCheckResult {
  final bool isWithinRadius;
  final double distanceMeters;
  final double currentLat;
  final double currentLng;

  LocationCheckResult({
    required this.isWithinRadius,
    required this.distanceMeters,
    required this.currentLat,
    required this.currentLng,
  });
}

/// Custom exception for location errors
class LocationException implements Exception {
  final String message;
  LocationException(this.message);

  @override
  String toString() => 'LocationException: $message';
}
