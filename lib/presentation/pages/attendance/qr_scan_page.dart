import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/wifi_service.dart';

class QrScanPage extends StatefulWidget {
  final bool isCheckIn;

  const QrScanPage({super.key, required this.isCheckIn});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> with WidgetsBindingObserver {
  final _repository = AttendanceRepository();
  final _locationService = LocationService();
  final _wifiService = WifiService();

  bool _isProcessing = false;
  bool _permissionGranted = false;
  bool _isLoadingPermission = true;
  late final MobileScannerController _controller;
  StreamSubscription<BarcodeCapture>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _permissionGranted = status.isGranted;
        _isLoadingPermission = false;
      });

      if (_permissionGranted) {
        _initializeScanner();
      }
    }
  }

  void _initializeScanner() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    _subscription = _controller.barcodes.listen(_onDetect);
    // Start the camera
    _controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_permissionGranted)
      return; // Only manage lifecycle if permission was granted
    if (!_controller.value.isInitialized)
      return; // Ensure controller is initialized
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _subscription = _controller.barcodes.listen(_onDetect);
        _controller.start();
        break;
      case AppLifecycleState.inactive:
        _subscription?.cancel();
        _subscription = null;
        _controller.stop();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    if (_permissionGranted) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;

    if (code == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Re-fetch location/wifi just to be sure (though pre-scan checked it)
      final Position position = await _locationService.getCurrentPosition();
      final String? wifiSsid = await _wifiService.getCurrentWifiSsid();

      final locationData = {
        'lat': position.latitude,
        'lng': position.longitude,
      };

      final wifiInfo = {
        'ssid': wifiSsid ?? 'Unknown',
        'bssid':
            '00:00:00:00', // BSSID not always available on mobile without strict permissions
      };

      if (widget.isCheckIn) {
        await _repository.checkIn(
          userId: userId,
          qrCode: code,
          location: locationData,
          wifiInfo: wifiInfo,
        );
      } else {
        await _repository.checkOut(
          userId: userId,
          qrCode: code,
          location: locationData,
          wifiInfo: wifiInfo,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isCheckIn
                  ? 'Checked in successfully!'
                  : 'Checked out successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Return to home
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
        // Resume scanning after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isProcessing = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isCheckIn ? 'Scan QR to Check In' : 'Scan QR to Check Out',
        ),
        centerTitle: true,
      ),
      body: _isLoadingPermission
          ? const Center(child: CircularProgressIndicator())
          : !_permissionGranted
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Camera permission is required'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: openAppSettings,
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                MobileScanner(controller: _controller),

                // Overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        // Corners
                        Positioned(
                          top: 0,
                          left: 0,
                          child: _Corner(isTop: true, isLeft: true),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: _Corner(isTop: true, isLeft: false),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: _Corner(isTop: false, isLeft: true),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: _Corner(isTop: false, isLeft: false),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Verifying...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Corner extends StatelessWidget {
  final bool isTop;
  final bool isLeft;

  const _Corner({required this.isTop, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          top: isTop
              ? const BorderSide(color: Colors.teal, width: 4)
              : BorderSide.none,
          bottom: !isTop
              ? const BorderSide(color: Colors.teal, width: 4)
              : BorderSide.none,
          left: isLeft
              ? const BorderSide(color: Colors.teal, width: 4)
              : BorderSide.none,
          right: !isLeft
              ? const BorderSide(color: Colors.teal, width: 4)
              : BorderSide.none,
        ),
      ),
    );
  }
}
