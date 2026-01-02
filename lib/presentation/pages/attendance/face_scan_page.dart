import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/face/face_service.dart';
import '../../../core/location/location_service.dart';
import '../../../core/wifi/wifi_service.dart';
import '../../../core/services/offline_queue.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../core/auth/auth_service.dart';

/// Face scan page for check-in/check-out with real camera and validation
class FaceScanPage extends StatefulWidget {
  final bool isCheckIn;

  const FaceScanPage({super.key, required this.isCheckIn});

  @override
  State<FaceScanPage> createState() => _FaceScanPageState();
}

class _FaceScanPageState extends State<FaceScanPage> {
  CameraController? _cameraController;
  final FaceService _faceService = FaceService();
  final LocationService _locationService = LocationService();
  final WifiService _wifiService = WifiService();
  final OfflineQueueService _offlineQueue = OfflineQueueService();
  final AttendanceRepository _attendanceRepo = AttendanceRepository();
  final AuthService _authService = AuthService();

  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isVerifying = false;

  String _statusMessage = 'Initializing...';
  String _instruction = '';

  Face? _detectedFace;
  FaceAlignmentResult? _alignment;
  bool _faceReady = false;

  // Validation results
  Map<String, dynamic>? _locationData;
  Map<String, dynamic>? _wifiData;
  List<double>? _faceEmbedding;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // 1. Request permissions explicitly
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.location,
      ].request();

      if (statuses[Permission.camera] != PermissionStatus.granted ||
          statuses[Permission.location] != PermissionStatus.granted) {
        if (mounted) {
          _showPermissionDialog();
          setState(() {
            _isInitializing = false;
            _statusMessage = 'Permissions required';
            _instruction = 'Enable Camera and Location';
          });
        }
        return;
      }

      // 2. Check if Location Services (GPS) are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationServiceDialog();
          setState(() {
            _isInitializing = false;
            _statusMessage = 'GPS Disabled';
            _instruction = 'Turn on Location Services';
          });
        }
        return;
      }

      // 3. Initialize face service
      await _faceService.initialize();

      // 4. Initialize camera
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras found');
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processImage);

      // 5. Pre-fetch location and WiFi
      _prefetchContextData();

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Position your face';
          _instruction = 'Look at the camera';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Initialization error';
          _instruction = e.toString();
        });
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'Camera is needed for face ID.\nLocation is needed for attendance verification.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Go back
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('GPS Required'),
        content: const Text(
          'Please turn on Location Services (GPS) to verify your location.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Go back
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openLocationSettings();
              Navigator.pop(context);
              _initialize(); // Retry
            },
            child: const Text('Turn On'),
          ),
        ],
      ),
    );
  }

  Future<void> _prefetchContextData() async {
    try {
      // Get location
      final location = await _locationService.getCurrentLocation();
      _locationData = location;

      // Check for mock location
      final isMock = await _locationService.isMockLocation();
      if (isMock) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Mock location detected!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Location prefetch error: $e');
    }

    try {
      // Get WiFi info
      final wifi = await _wifiService.getWifiInfo();
      _wifiData = wifi.toJson();
    } catch (e) {
      debugPrint('WiFi prefetch error: $e');
    }
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
            _statusMessage = 'No face detected';
            _instruction = 'Position your face in the frame';
          });
        }
      } else if (faces.length > 1) {
        if (mounted) {
          setState(() {
            _faceReady = false;
            _statusMessage = 'Multiple faces';
            _instruction = 'Only one face should be visible';
          });
        }
      } else {
        final face = faces.first;
        final imageSize = inputImage.metadata!.size;
        final alignment = _faceService.checkFaceAlignment(face, imageSize);

        if (mounted) {
          setState(() {
            _detectedFace = face;
            _alignment = alignment;
            _faceReady = alignment.isAligned;

            if (alignment.isAligned) {
              _statusMessage = 'Face detected!';
              _instruction = 'Tap verify to continue';
              _faceEmbedding = _faceService.generateEmbedding(face);
            } else {
              _statusMessage = 'Adjust position';
              _instruction = alignment.instruction;
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
    if (!_faceReady || _isVerifying || _faceEmbedding == null) return;

    setState(() {
      _isVerifying = true;
      _statusMessage = 'Verifying...';
      _instruction = 'Please wait';
    });

    try {
      await _cameraController?.stopImageStream();

      // Ensure we have location and WiFi data
      _locationData ??= await _locationService.getCurrentLocation();

      if (_wifiData == null) {
        try {
          final wifi = await _wifiService.getWifiInfo();
          _wifiData = wifi.toJson();
        } catch (e) {
          _wifiData = {'ssid': 'unknown', 'bssid': 'unknown'};
        }
      }

      final userId = _authService.currentUserId!;

      // Check if online
      final isOnline = await _offlineQueue.isOnline();

      if (isOnline) {
        // Force session refresh to prevent "Invalid JWT"
        try {
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {
          // Ignore refresh errors
        }

        // Online - submit directly
        if (widget.isCheckIn) {
          await _attendanceRepo.checkIn(
            userId: userId,
            faceEmbedding: _faceEmbedding!,
            location: _locationData!,
            wifiInfo: _wifiData!,
          );
        } else {
          await _attendanceRepo.checkOut(
            userId: userId,
            faceEmbedding: _faceEmbedding!,
            location: _locationData!,
            wifiInfo: _wifiData!,
          );
        }

        if (mounted) {
          _showSuccessAndReturn();
        }
      } else {
        // Offline - queue for later
        await _offlineQueue.queueAttendance(
          userId: userId,
          type: widget.isCheckIn ? 'check_in' : 'check_out',
          faceEmbedding: _faceEmbedding!,
          location: _locationData!,
          wifiInfo: _wifiData!,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📴 Saved offline. Will sync when connected.'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _statusMessage = 'Verification failed';
          _instruction = _parseError(e.toString());
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${_parseError(e.toString())}'),
            backgroundColor: Colors.red,
          ),
        );

        // Restart camera
        await _cameraController?.startImageStream(_processImage);
      }
    }
  }

  String _parseError(String error) {
    if (error.contains('LOCATION_INVALID')) {
      return 'You are too far from the office';
    } else if (error.contains('WIFI_INVALID')) {
      return 'Not connected to authorized WiFi';
    } else if (error.contains('FACE_MISMATCH')) {
      return 'Face verification failed';
    } else if (error.contains('NO_FACE_PROFILE')) {
      return 'Face not enrolled. Please enroll first.';
    } else if (error.contains('NO_ACTIVE_CHECKIN')) {
      return 'No active check-in to check out from';
    }
    return error;
  }

  void _showSuccessAndReturn() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
        title: Text(
          widget.isCheckIn ? 'Check-In Successful!' : 'Check-Out Successful!',
        ),
        content: Text(
          widget.isCheckIn
              ? 'Welcome! Have a productive day.'
              : 'Goodbye! See you tomorrow.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to home
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCheckIn = widget.isCheckIn;

    return Scaffold(
      backgroundColor: Colors.black, // Camera BG is always black
      appBar: AppBar(
        title: Text(
          isCheckIn ? 'Check In' : 'Check Out',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: _isInitializing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: scheme.secondary),
                  const SizedBox(height: 16),
                  const Text(
                    'Starting camera...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // Camera preview
                if (_cameraController != null &&
                    _cameraController!.value.isInitialized)
                  SizedBox.expand(child: CameraPreview(_cameraController!)),

                // Dark overlay with cutout
                ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.black54,
                    BlendMode.srcOut,
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                          backgroundBlendMode: BlendMode.dstOut,
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 280,
                          height: 360,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(140),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Frame Border
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 290,
                    height: 370,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _getFrameColor(scheme),
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(145),
                    ),
                  ),
                ),

                // Status Message (Top)
                Positioned(
                  top: 120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom Control Panel
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Context Indicators
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildContextIndicator(
                              Icons.location_on_outlined,
                              _locationData != null,
                              'GPS',
                              scheme,
                            ),
                            _buildContextIndicator(
                              Icons.wifi,
                              _wifiData != null,
                              'WiFi',
                              scheme,
                            ),
                            _buildContextIndicator(
                              Icons.face_retouching_natural,
                              _faceReady,
                              'Face',
                              scheme,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Instruction
                        Text(
                          _instruction,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.textTheme.bodyLarge?.color
                                ?.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Action Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _faceReady && !_isVerifying
                                ? _verifyAndSubmit
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: scheme.primary, // Slate-900
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: scheme.onSurface
                                  .withOpacity(0.1),
                              disabledForegroundColor: scheme.onSurface
                                  .withOpacity(0.3),
                              elevation: 0,
                            ),
                            icon: _isVerifying
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  )
                                : Icon(isCheckIn ? Icons.login : Icons.logout),
                            label: Text(
                              _isVerifying
                                  ? 'Verifying...'
                                  : (isCheckIn
                                        ? 'Confirm Check In'
                                        : 'Confirm Check Out'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Color _getFrameColor(ColorScheme scheme) {
    if (_detectedFace == null) return Colors.white24;
    if (!_faceReady) return const Color(0xFFF59E0B); // Amber
    return scheme.secondary; // Teal
  }

  Widget _buildContextIndicator(
    IconData icon,
    bool isReady,
    String label,
    ColorScheme scheme,
  ) {
    final color = isReady
        ? scheme.secondary
        : scheme.onSurfaceVariant.withOpacity(0.3);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
