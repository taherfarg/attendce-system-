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
import '../../../core/permissions/permission_service.dart';
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
  String? _cameraError;

  Face? _detectedFace;
  bool _faceReady = false;
  List<double>? _currentEmbedding;

  // Collect multiple embeddings for averaging (more stable verification)
  List<List<double>> _collectedEmbeddings = [];
  static const _requiredEmbeddingCount = 3;

  // Throttle frame processing to prevent lag
  DateTime _lastProcessedTime = DateTime.now();
  static const _processInterval = Duration(milliseconds: 300);

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
      // Use centralized permission service to prevent race conditions
      final permissionService = PermissionService();
      final status = await permissionService.requestPermission(
        Permission.camera,
      );

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
        ResolutionPreset.low, // Use low resolution to prevent lag
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
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Camera error';
          _cameraError = e.toString().split('\n').first;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start camera: $_cameraError'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _isInitializing = true;
                  _statusMessage = 'Starting camera...';
                  _cameraError = null;
                });
                _initializeCamera();
              },
            ),
          ),
        );
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

    // Throttle: skip frames that come too quickly
    final now = DateTime.now();
    if (now.difference(_lastProcessedTime) < _processInterval) {
      return;
    }
    _lastProcessedTime = now;

    _isProcessing = true;

    // Validate image planes are accessible
    if (image.planes.isEmpty) {
      _isProcessing = false;
      return;
    }

    // Check if buffer is accessible (avoid the "buffer is inaccessible" error)
    try {
      final _ = image.planes.first.bytes;
    } catch (e) {
      // Buffer is not accessible, skip this frame
      _isProcessing = false;
      return;
    }

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
            _collectedEmbeddings.clear(); // Reset when face lost
            _statusMessage = 'Looking for face...';
            _instruction = 'Position your face in the frame';
          });
        }
      } else if (faces.length > 1) {
        if (mounted) {
          setState(() {
            _statusMessage = 'One face only';
            _faceReady = false;
            _collectedEmbeddings.clear(); // Reset when multiple faces
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
              // Generate embedding and collect for averaging
              final embedding = _faceService.generateEmbedding(face);
              final quality = _faceService.calculateEmbeddingQuality(face);

              // Only accept high-quality embeddings
              if (quality > 0.6) {
                _collectedEmbeddings.add(embedding);

                // Keep only the most recent embeddings
                if (_collectedEmbeddings.length > _requiredEmbeddingCount) {
                  _collectedEmbeddings.removeAt(0);
                }

                if (_collectedEmbeddings.length >= _requiredEmbeddingCount) {
                  // Average embeddings for stable verification
                  _currentEmbedding = _faceService.averageEmbeddings(
                    _collectedEmbeddings,
                  );
                  _statusMessage = 'Face detected!';
                  _instruction = 'Ready to verify';
                } else {
                  _statusMessage = 'Analyzing face...';
                  _instruction =
                      'Hold still (${_collectedEmbeddings.length}/$_requiredEmbeddingCount)';
                }
              } else {
                _statusMessage = 'Improve lighting';
                _instruction = 'Move to better lit area';
              }
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

                // Bottom panel with premium glassmorphism
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withOpacity(0.95), Colors.white],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(36),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 30,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Enhanced context indicators
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor.withOpacity(0.08),
                              accentColor.withOpacity(0.04),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: accentColor.withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatusIndicator(
                              Icons.location_on_rounded,
                              'GPS',
                              _locationData != null,
                              accentColor,
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.grey.shade200,
                            ),
                            _buildStatusIndicator(
                              Icons.wifi_rounded,
                              'WiFi',
                              _wifiData != null,
                              accentColor,
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.grey.shade200,
                            ),
                            _buildStatusIndicator(
                              Icons.face_retouching_natural,
                              'Face',
                              _faceReady,
                              accentColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Instruction with icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _faceReady
                                ? Icons.check_circle_rounded
                                : Icons.info_outlined,
                            size: 18,
                            color: _faceReady
                                ? const Color(0xFF10B981)
                                : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _instruction,
                            style: TextStyle(
                              fontSize: 15,
                              color: _faceReady
                                  ? const Color(0xFF10B981)
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Gradient action button
                      Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: _faceReady && !_isVerifying
                              ? LinearGradient(
                                  colors: isCheckIn
                                      ? [
                                          const Color(0xFF10B981),
                                          const Color(0xFF059669),
                                        ]
                                      : [
                                          const Color(0xFFF59E0B),
                                          const Color(0xFFD97706),
                                        ],
                                )
                              : LinearGradient(
                                  colors: [
                                    Colors.grey.shade300,
                                    Colors.grey.shade200,
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: _faceReady
                              ? [
                                  BoxShadow(
                                    color:
                                        (isCheckIn
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFF59E0B))
                                            .withOpacity(0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _faceReady && !_isVerifying
                                ? _verifyAndSubmit
                                : null,
                            borderRadius: BorderRadius.circular(18),
                            child: Center(
                              child: _isVerifying
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Verifying...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isCheckIn
                                              ? Icons.login_rounded
                                              : Icons.logout_rounded,
                                          color: _faceReady
                                              ? Colors.white
                                              : Colors.grey.shade500,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          isCheckIn
                                              ? 'Confirm Check In'
                                              : 'Confirm Check Out',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: _faceReady
                                                ? Colors.white
                                                : Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
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

  Widget _buildStatusIndicator(
    IconData icon,
    String label,
    bool isReady,
    Color accentColor,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: isReady
                ? const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  )
                : null,
            color: isReady ? null : Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isReady ? Icons.check_rounded : icon,
            color: isReady ? Colors.white : Colors.grey.shade400,
            size: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isReady ? const Color(0xFF10B981) : Colors.grey.shade500,
          ),
        ),
      ],
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
