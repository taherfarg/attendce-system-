import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/face/face_service.dart';
import '../../../core/location/location_service.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../../core/services/offline_queue.dart';
import '../../../data/repositories/attendance_repository.dart';

/// Modern face scan page with properly centered camera
class FaceScanPage extends StatefulWidget {
  final bool isCheckIn;

  const FaceScanPage({super.key, required this.isCheckIn});

  @override
  State<FaceScanPage> createState() => _FaceScanPageState();
}

class _FaceScanPageState extends State<FaceScanPage>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  final FaceService _faceService = FaceService();
  final LocationService _locationService = LocationService();
  final WifiService _wifiService = WifiService();
  final AttendanceRepository _attendanceRepo = AttendanceRepository();
  final OfflineQueueService _offlineQueue = OfflineQueueService();

  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isVerifying = false;

  String _statusMessage = 'Starting camera...';
  String _instruction = 'Position your face in the frame';

  Face? _detectedFace;
  bool _faceReady = false;
  List<double>? _currentEmbedding;

  Map<String, double>? _locationData;
  Map<String, dynamic>? _wifiData;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _initializeCamera();
    _prefetchContextData();
  }

  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _statusMessage = 'Camera permission denied';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable camera access')),
          );
        }
        return;
      }

      await _faceService.initialize();
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high, // Higher resolution for better detection
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processImage);

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Looking for face...';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Camera error';
        });
      }
    }
  }

  Future<void> _prefetchContextData() async {
    try {
      _locationData = await _locationService.getCurrentLocation();
      final isMock = await _locationService.isMockLocation();
      if (isMock && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mock location detected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }

    try {
      final wifiInfo = await _wifiService.getWifiInfo();
      _wifiData = wifiInfo.toJson();
    } catch (e) {
      debugPrint('WiFi error: $e');
    }

    if (mounted) setState(() {});
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing || _isVerifying) return;
    _isProcessing = true;

    try {
      final inputImage = _faceService.convertCameraImageToInputImage(
        image,
        _cameraController!.description,
        _cameraController!.description.sensorOrientation,
      );

      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final faces = await _faceService.detectFaces(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _detectedFace = null;
            _faceReady = false;
            _statusMessage = 'Looking for face...';
            _instruction = 'Position your face in the frame';
          });
        }
      } else if (faces.length > 1) {
        if (mounted) {
          setState(() {
            _statusMessage = 'One face only';
            _faceReady = false;
          });
        }
      } else {
        final face = faces.first;
        final imageSize = inputImage.metadata!.size;
        final alignment = _faceService.checkFaceAlignment(face, imageSize);
        final liveness = _faceService.checkLiveness(face);

        final isAligned = alignment.isAligned;
        final isLive = liveness.eyeOpenScore > 0.5 && !liveness.isBlinking;

        if (mounted) {
          setState(() {
            _detectedFace = face;
            _faceReady = isAligned && isLive;

            if (!isAligned) {
              _statusMessage = alignment.instruction;
              _instruction = 'Adjust your position';
            } else if (!isLive) {
              _statusMessage = 'Look at the camera';
              _instruction = 'Keep eyes open naturally';
            } else {
              _statusMessage = 'Face detected!';
              _instruction = 'Ready to verify';
              _currentEmbedding = _faceService.generateEmbedding(face);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Face processing error: $e');
    }

    _isProcessing = false;
  }

  Future<void> _verifyAndSubmit() async {
    if (_currentEmbedding == null || _isVerifying) return;

    setState(() {
      _isVerifying = true;
      _statusMessage = 'Verifying...';
    });

    try {
      await _cameraController?.stopImageStream();
      final isOnline = await _checkConnectivity();

      if (isOnline) {
        await _submitOnline();
      } else {
        await _queueOffline();
      }
    } catch (e) {
      final error = e.toString();
      if (error.contains('JWT') || error.contains('401')) {
        _showSessionExpired();
      } else {
        _showError(error);
      }
    }

    setState(() => _isVerifying = false);
  }

  Future<bool> _checkConnectivity() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _submitOnline() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      if (widget.isCheckIn) {
        await _attendanceRepo.checkIn(
          userId: userId,
          faceEmbedding: _currentEmbedding!,
          location: _locationData ?? {'lat': 0.0, 'lng': 0.0},
          wifiInfo: _wifiData ?? {'ssid': 'unknown', 'bssid': 'unknown'},
        );
      } else {
        await _attendanceRepo.checkOut(
          userId: userId,
          faceEmbedding: _currentEmbedding!,
          location: _locationData ?? {'lat': 0.0, 'lng': 0.0},
          wifiInfo: _wifiData ?? {'ssid': 'unknown', 'bssid': 'unknown'},
        );
      }
      _showSuccessAndReturn();
    } catch (e) {
      _showError(e.toString());
      await _cameraController?.startImageStream(_processImage);
    }
  }

  Future<void> _queueOffline() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    await _offlineQueue.queueAttendance(
      userId: userId,
      type: widget.isCheckIn ? 'check_in' : 'check_out',
      faceEmbedding: _currentEmbedding!,
      location: _locationData ?? {'lat': 0.0, 'lng': 0.0},
      wifiInfo: _wifiData ?? {'ssid': 'unknown', 'bssid': 'unknown'},
    );
    _showOfflineQueued();
  }

  void _showError(String message) {
    if (!mounted) return;

    // Parse common errors for user-friendly messages
    String displayMessage = message;
    if (message.contains('FACE_MISMATCH')) {
      displayMessage =
          'Face not recognized. Please make sure: \n1. It is you\n2. Lighting is good\n3. You are looking at the camera';
    } else if (message.contains('LOCATION_INVALID')) {
      displayMessage = 'You are too far from the office location.';
    } else if (message.contains('WIFI_INVALID')) {
      displayMessage = 'Please connect to the office Wi-Fi network.';
    } else if (message.contains('NO_FACE_PROFILE')) {
      displayMessage = 'Face data not found. Please re-enroll from profile.';
    } else if (message.contains('NO_ACTIVE_CHECKIN')) {
      displayMessage = 'No active check-in found. You need to Check In first.';
    } else {
      // Clean up raw exception text if possible
      if (message.contains('FunctionException')) {
        final start = message.indexOf('message: ');
        if (start != -1) {
          final end = message.indexOf('}', start);
          if (end != -1) {
            displayMessage = message.substring(start + 9, end);
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.error_outline_rounded,
            color: Colors.red.shade400,
            size: 48,
          ),
        ),
        title: const Text('Verification Failed'),
        content: Text(displayMessage, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _showSessionExpired() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.lock_clock_rounded,
            color: Colors.orange.shade400,
            size: 48,
          ),
        ),
        title: const Text('Session Expired'),
        content: const Text(
          'Your security session has expired.\nPlease sign in again to continue.',
          textAlign: TextAlign.center,
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context).pop(); // Go back
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade400,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign In Again'),
          ),
        ],
      ),
    );
  }

  void _showOfflineQueued() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_off_rounded,
            color: Colors.orange.shade400,
            size: 48,
          ),
        ),
        title: const Text('Saved Offline'),
        content: const Text(
          'Your attendance will sync when online.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessAndReturn() {
    if (!mounted) return;
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
                Navigator.pop(context);
                Navigator.pop(context);
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
  void dispose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCheckIn = widget.isCheckIn;
    final accentColor = isCheckIn ? scheme.primary : scheme.secondary;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: _isInitializing
          ? _buildLoadingState(accentColor)
          : Column(
              children: [
                // Camera section (takes most of the screen)
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      // Camera preview - properly centered
                      if (_cameraController != null &&
                          _cameraController!.value.isInitialized)
                        Positioned.fill(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width:
                                  _cameraController!
                                      .value
                                      .previewSize
                                      ?.height ??
                                  screenSize.width,
                              height:
                                  _cameraController!.value.previewSize?.width ??
                                  screenSize.height,
                              child: CameraPreview(_cameraController!),
                            ),
                          ),
                        ),

                      // Dark vignette overlay
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.6),
                              ],
                              radius: 0.8,
                            ),
                          ),
                        ),
                      ),

                      // Top gradient for header
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 120,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Header
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              _GlassButton(
                                icon: Icons.arrow_back_rounded,
                                onTap: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: accentColor.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isCheckIn
                                          ? Icons.login_rounded
                                          : Icons.logout_rounded,
                                      color: accentColor,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isCheckIn ? 'Check In' : 'Check Out',
                                      style: TextStyle(
                                        color: accentColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                      ),

                      // Face frame - centered in view
                      Center(
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = 1.0 + (_pulseController.value * 0.02);
                            return Transform.scale(
                              scale: _faceReady ? 1.0 : scale,
                              child: Container(
                                width: 260,
                                height: 340,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(130),
                                  border: Border.all(
                                    color: _getFrameColor(),
                                    width: 4,
                                  ),
                                  boxShadow: _faceReady
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withOpacity(0.5),
                                            blurRadius: 30,
                                            spreadRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Status badge - below face frame
                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _getFrameColor().withOpacity(0.2),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: _getFrameColor().withOpacity(0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_faceReady)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  _statusMessage,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom panel
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Context indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ContextChip(
                            icon: Icons.location_on_rounded,
                            label: 'GPS',
                            isReady: _locationData != null,
                          ),
                          _ContextChip(
                            icon: Icons.wifi_rounded,
                            label: 'WiFi',
                            isReady: _wifiData != null,
                          ),
                          _ContextChip(
                            icon: Icons.face_retouching_natural,
                            label: 'Face',
                            isReady: _faceReady,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Instruction
                      Text(
                        _instruction,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Action button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _faceReady && !_isVerifying
                              ? _verifyAndSubmit
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade200,
                            disabledForegroundColor: Colors.grey.shade400,
                            elevation: _faceReady ? 8 : 0,
                            shadowColor: accentColor.withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isVerifying
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Verifying...'),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isCheckIn
                                          ? Icons.login_rounded
                                          : Icons.logout_rounded,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isCheckIn
                                          ? 'Confirm Check In'
                                          : 'Confirm Check Out',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLoadingState(Color accentColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Preparing camera...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Color _getFrameColor() {
    if (_detectedFace == null) return Colors.white.withOpacity(0.4);
    if (!_faceReady) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }
}

// Glass button
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// Context chip
class _ContextChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isReady;

  const _ContextChip({
    required this.icon,
    required this.label,
    required this.isReady,
  });

  @override
  Widget build(BuildContext context) {
    final color = isReady ? const Color(0xFF10B981) : Colors.grey.shade400;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReady)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
