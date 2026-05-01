import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  String? _errorMessage;
  MobileScannerController? _controller;
  StreamSubscription<BarcodeCapture>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (kIsWeb) {
      // On web, camera permission is handled by the browser via getUserMedia.
      // We just need to initialize the scanner directly.
      if (mounted) {
        setState(() {
          _permissionGranted = true;
          _isLoadingPermission = false;
        });
        _initializeScanner();
      }
      return;
    }

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
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        // On web/desktop, use front camera since back camera may not exist
        facing: kIsWeb ? CameraFacing.front : CameraFacing.back,
        // Explicitly set formats to QR for faster detection
        formats: const [BarcodeFormat.qrCode],
      );

      _subscription = _controller!.barcodes.listen(_onDetect);

      // Start the camera with error handling
      _controller!.start().then((_) {
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      }).catchError((error) {
        debugPrint('Scanner start error: $error');
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to start camera. Please ensure camera access is allowed in your browser settings.';
            _permissionGranted = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Scanner init error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Camera initialization failed: ${e.toString()}';
          _permissionGranted = false;
          _isLoadingPermission = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_permissionGranted || _controller == null) return;
    if (!_controller!.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _subscription = _controller!.barcodes.listen(_onDetect);
        _controller!.start();
        break;
      case AppLifecycleState.inactive:
        _subscription?.cancel();
        _subscription = null;
        _controller!.stop();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;

    if (code == null || code.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Get location data - gracefully handle web limitations
      Map<String, dynamic> locationData = {'lat': 0.0, 'lng': 0.0};
      try {
        final Position position = await _locationService.getCurrentPosition();
        locationData = {
          'lat': position.latitude,
          'lng': position.longitude,
        };
      } catch (e) {
        debugPrint('Location unavailable (web): $e');
        // On web, location might not be available - continue with defaults
      }

      // Get WiFi data - gracefully handle web limitations
      Map<String, dynamic> wifiInfo = {
        'ssid': kIsWeb ? 'web-browser' : 'Unknown',
        'bssid': '00:00:00:00',
      };
      try {
        final String? wifiSsid = await _wifiService.getCurrentWifiSsid();
        if (wifiSsid != null) {
          wifiInfo['ssid'] = wifiSsid;
        }
      } catch (e) {
        debugPrint('WiFi info unavailable: $e');
      }

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
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        // Resume scanning after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isProcessing = false);
        });
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF10B981),
            size: 56,
          ),
        ),
        title: Text(
          widget.isCheckIn ? 'Checked In!' : 'Checked Out!',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          widget.isCheckIn ? 'Have a productive day!' : 'See you next time!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Return to home
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(
          widget.isCheckIn ? 'Scan QR to Check In' : 'Scan QR to Check Out',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoadingPermission
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  SizedBox(height: 20),
                  Text(
                    'Initializing camera...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            )
          : (!_permissionGranted || _errorMessage != null)
              ? _buildErrorState()
              : _buildScannerView(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.videocam_off_rounded,
                size: 48,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Camera Access Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? (kIsWeb
                  ? 'Please allow camera access in your browser.\nClick the camera icon in the address bar.'
                  : 'Camera permission is required to scan QR codes.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Go Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLoadingPermission = true;
                      _errorMessage = null;
                      _permissionGranted = false;
                    });
                    _checkPermission();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: openAppSettings,
                child: const Text(
                  'Open App Settings',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        // Scanner
        if (_controller != null)
          MobileScanner(controller: _controller!),

        // Scan frame overlay
        Center(
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                // Semi-transparent border
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                // Corner decorations
                const Positioned(
                  top: 0, left: 0,
                  child: _Corner(isTop: true, isLeft: true),
                ),
                const Positioned(
                  top: 0, right: 0,
                  child: _Corner(isTop: true, isLeft: false),
                ),
                const Positioned(
                  bottom: 0, left: 0,
                  child: _Corner(isTop: false, isLeft: true),
                ),
                const Positioned(
                  bottom: 0, right: 0,
                  child: _Corner(isTop: false, isLeft: false),
                ),
              ],
            ),
          ),
        ),

        // Bottom instruction
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                _isProcessing
                    ? 'Verifying...'
                    : 'Point camera at the QR code',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),

        // Torch toggle button (not on web)
        if (!kIsWeb && _controller != null)
          Positioned(
            bottom: 40,
            right: 24,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white.withOpacity(0.2),
              elevation: 0,
              onPressed: () => _controller!.toggleTorch(),
              child: ValueListenableBuilder(
                valueListenable: _controller!,
                builder: (context, state, child) {
                  return Icon(
                    state.torchState == TorchState.on
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    color: Colors.white,
                  );
                },
              ),
            ),
          ),

        // Camera switch button
        if (_controller != null)
          Positioned(
            bottom: 40,
            left: 24,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white.withOpacity(0.2),
              elevation: 0,
              onPressed: () => _controller!.switchCamera(),
              child: const Icon(
                Icons.cameraswitch_rounded,
                color: Colors.white,
              ),
            ),
          ),

        // Processing overlay
        if (_isProcessing)
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    SizedBox(height: 20),
                    Text(
                      'Verifying attendance...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          top: isTop
              ? const BorderSide(color: Color(0xFF6366F1), width: 4)
              : BorderSide.none,
          bottom: !isTop
              ? const BorderSide(color: Color(0xFF6366F1), width: 4)
              : BorderSide.none,
          left: isLeft
              ? const BorderSide(color: Color(0xFF6366F1), width: 4)
              : BorderSide.none,
          right: !isLeft
              ? const BorderSide(color: Color(0xFF6366F1), width: 4)
              : BorderSide.none,
        ),
      ),
    );
  }
}
