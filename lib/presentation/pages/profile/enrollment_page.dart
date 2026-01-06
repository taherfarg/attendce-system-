import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/face/face_service.dart';
import '../../../core/permissions/permission_service.dart';

/// Modern face enrollment page with step indicators and animations
class EnrollmentPage extends StatefulWidget {
  const EnrollmentPage({super.key});

  @override
  State<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends State<EnrollmentPage>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  final FaceService _faceService = FaceService();

  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isEnrolling = false;
  String _statusMessage = 'Starting camera...';

  // Throttle frame processing to prevent lag
  DateTime _lastProcessedTime = DateTime.now();
  static const _processInterval = Duration(milliseconds: 300);

  Face? _detectedFace;
  FaceAlignmentResult? _alignment;

  bool _hasSeenEyesOpen = false;
  bool _hasSeenBlink = false;
  bool _livenessVerified = false;

  // Multi-pose enrollment
  static const _requiredPoses = 3;
  final List<String> _poseLabels = ['Center', 'Turn Left', 'Turn Right'];
  int _currentPoseIndex = 0;
  List<List<double>> _collectedEmbeddings = [];
  bool _poseReady = false; // Current pose is ready to capture

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _initializeCamera();
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
            const SnackBar(
              content: Text(
                'Permission denied. Please enable camera access in settings.',
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        setState(() => _statusMessage = 'Initializing...');
      }

      // Run face service init and camera enumeration in PARALLEL
      final results = await Future.wait([
        _faceService.initialize(),
        availableCameras(),
      ]);

      final cameras = results[1] as List<CameraDescription>;

      if (cameras.isEmpty) {
        throw Exception('No cameras found on device');
      }

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

      // Small delay to ensure camera is fully ready
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;

      await _cameraController!.startImageStream(_processImage);

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Position your face';
        });
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Camera error';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to start camera: ${e.toString().split('\n').first}',
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _isInitializing = true;
                  _statusMessage = 'Starting camera...';
                });
                _initializeCamera();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing || _isEnrolling) return;

    // Throttle: skip frames that come too quickly
    final now = DateTime.now();
    if (now.difference(_lastProcessedTime) < _processInterval) {
      return;
    }
    _lastProcessedTime = now;

    _isProcessing = true;

    try {
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
            _statusMessage = 'Looking for face...';
          });
        }
      } else if (faces.length > 1) {
        if (mounted) {
          setState(() => _statusMessage = 'One face only');
        }
      } else {
        final face = faces.first;
        final imageSize = inputImage.metadata!.size;
        final alignment = _faceService.checkFaceAlignment(face, imageSize);
        final liveness = _faceService.checkLiveness(face);

        // Check liveness first (only needs to be done once)
        if (!_livenessVerified) {
          if (liveness.eyeOpenScore > 0.8) _hasSeenEyesOpen = true;
          if (_hasSeenEyesOpen && liveness.isBlinking) _hasSeenBlink = true;
          if (_hasSeenEyesOpen &&
              _hasSeenBlink &&
              liveness.eyeOpenScore > 0.7) {
            _livenessVerified = true;
          }
        }

        // Check if current pose is met based on head rotation
        final headY = alignment
            .headRotationY; // Negative = looking left, Positive = looking right
        bool isPoseCorrect = false;
        String poseInstruction = '';

        switch (_currentPoseIndex) {
          case 0: // Center - head should be relatively straight
            isPoseCorrect = headY.abs() < 10;
            poseInstruction = 'Look straight at camera';
            break;
          case 1: // Turn Left - head rotation should be negative
            isPoseCorrect = headY < -8 && headY > -30;
            poseInstruction = 'Turn head slightly LEFT ←';
            break;
          case 2: // Turn Right - head rotation should be positive
            isPoseCorrect = headY > 8 && headY < 30;
            poseInstruction = 'Turn head slightly RIGHT →';
            break;
        }

        if (mounted) {
          setState(() {
            _detectedFace = face;
            _alignment = alignment;
            _poseReady =
                isPoseCorrect && _livenessVerified && alignment.isSizeOk;

            if (!alignment.isSizeOk) {
              _statusMessage = alignment.instruction;
            } else if (!_livenessVerified) {
              if (!_hasSeenEyesOpen) {
                _statusMessage = 'Keep eyes open';
              } else if (!_hasSeenBlink) {
                _statusMessage = 'Blink once';
              } else {
                _statusMessage = 'Almost ready...';
              }
            } else if (!isPoseCorrect) {
              _statusMessage = poseInstruction;
            } else {
              _statusMessage =
                  'Pose ${_currentPoseIndex + 1}/$_requiredPoses ready!';
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Face error: $e');
    }

    _isProcessing = false;
  }

  Future<void> _enrollFace() async {
    if (_detectedFace == null || !_poseReady || _isEnrolling) return;

    // Capture current pose embedding
    final embedding = _faceService.generateEmbedding(_detectedFace!);
    _collectedEmbeddings.add(embedding);

    // Check if we have all required poses
    if (_collectedEmbeddings.length < _requiredPoses) {
      // Move to next pose
      setState(() {
        _currentPoseIndex++;
        _poseReady = false;
        _statusMessage = 'Great! Now: ${_poseLabels[_currentPoseIndex]}';
      });
      return;
    }

    // All poses captured - submit to server
    setState(() {
      _isEnrolling = true;
      _statusMessage = 'Saving all poses...';
    });

    try {
      await _cameraController?.stopImageStream();

      final userId = Supabase.instance.client.auth.currentUser!.id;

      // Send array of embeddings for multi-pose enrollment
      final response = await Supabase.instance.client.functions.invoke(
        'enroll_face',
        body: {
          'user_id': userId,
          'face_embeddings': _collectedEmbeddings, // Multi-pose array
          // Also send first as single for backward compatibility
          'face_embedding': _collectedEmbeddings.first,
        },
      );

      if (response.status == 200) {
        if (mounted) {
          _showSuccessDialog();
        }
      } else {
        final errorMsg = response.data is Map
            ? (response.data['error'] ?? 'Unknown error')
            : response.data.toString();
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint('Enrollment error: $e');
      if (mounted) {
        setState(() {
          _isEnrolling = false;
          _currentPoseIndex = 0;
          _collectedEmbeddings.clear();
          _statusMessage = 'Failed - start over';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _cameraController?.startImageStream(_processImage);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF10B981),
            size: 64,
          ),
        ),
        title: const Text(
          'Face Enrolled!',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Your face has been registered successfully. You can now use Face ID for attendance.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (_) => false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Continue',
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: _isInitializing
            ? _buildLoadingState()
            : Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        _GlassButton(
                          icon: Icons.close_rounded,
                          onTap: () => Supabase.instance.client.auth.signOut(),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: scheme.primary.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.face_retouching_natural,
                                color: scheme.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Face Enrollment',
                                style: TextStyle(
                                  color: scheme.primary,
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
                  ).animate().fade().slideY(begin: -0.2),

                  // Camera area
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Camera preview
                        if (_cameraController != null &&
                            _cameraController!.value.isInitialized)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController!
                                      .value
                                      .previewSize!
                                      .height,
                                  height: _cameraController!
                                      .value
                                      .previewSize!
                                      .width,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            ),
                          ),

                        // Animated face frame
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = 1.0 + (_pulseController.value * 0.02);
                            return Transform.scale(
                              scale: _livenessVerified ? 1.0 : scale,
                              child: Container(
                                width: 260,
                                height: 340,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(130),
                                  border: Border.all(
                                    color: _getFrameColor(),
                                    width: 4,
                                  ),
                                  boxShadow: _livenessVerified
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withOpacity(0.4),
                                            blurRadius: 30,
                                            spreadRadius: 5,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),

                        // Status badge
                        Positioned(
                          top: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _getFrameColor().withOpacity(0.2),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: _getFrameColor().withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_livenessVerified)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(right: 8),
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
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ).animate().fade().slideY(begin: -0.2),
                        ),
                      ],
                    ),
                  ),

                  // Bottom panel with premium glassmorphism
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
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
                      children: [
                        // Pose progress indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF6366F1).withOpacity(0.1),
                                const Color(0xFF8B5CF6).withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF6366F1).withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Capture ${_requiredPoses} Poses',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(_requiredPoses, (
                                  index,
                                ) {
                                  final isComplete =
                                      index < _collectedEmbeddings.length;
                                  final isCurrent = index == _currentPoseIndex;
                                  return Row(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        width: isCurrent ? 48 : 40,
                                        height: isCurrent ? 48 : 40,
                                        decoration: BoxDecoration(
                                          gradient: isComplete
                                              ? const LinearGradient(
                                                  colors: [
                                                    Color(0xFF10B981),
                                                    Color(0xFF059669),
                                                  ],
                                                )
                                              : isCurrent
                                              ? const LinearGradient(
                                                  colors: [
                                                    Color(0xFF6366F1),
                                                    Color(0xFF8B5CF6),
                                                  ],
                                                )
                                              : null,
                                          color: !isComplete && !isCurrent
                                              ? Colors.grey.shade200
                                              : null,
                                          shape: BoxShape.circle,
                                          boxShadow: isCurrent
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFF6366F1,
                                                    ).withOpacity(0.4),
                                                    blurRadius: 12,
                                                    spreadRadius: 2,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Center(
                                          child: isComplete
                                              ? const Icon(
                                                  Icons.check_rounded,
                                                  color: Colors.white,
                                                  size: 20,
                                                )
                                              : Icon(
                                                  index == 0
                                                      ? Icons.person_rounded
                                                      : index == 1
                                                      ? Icons.arrow_back_rounded
                                                      : Icons
                                                            .arrow_forward_rounded,
                                                  color: isCurrent
                                                      ? Colors.white
                                                      : Colors.grey.shade400,
                                                  size: isCurrent ? 22 : 18,
                                                ),
                                        ),
                                      ),
                                      if (index < _requiredPoses - 1)
                                        Container(
                                          width: 32,
                                          height: 3,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                index <
                                                    _collectedEmbeddings.length
                                                ? const Color(0xFF10B981)
                                                : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                }),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _poseLabels[_currentPoseIndex],
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fade(delay: 200.ms),
                        const SizedBox(height: 20),

                        // Capture button with gradient
                        Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: _poseReady && !_isEnrolling
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF10B981),
                                      Color(0xFF059669),
                                    ],
                                  )
                                : LinearGradient(
                                    colors: [
                                      Colors.grey.shade300,
                                      Colors.grey.shade200,
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: _poseReady
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF10B981,
                                      ).withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _poseReady && !_isEnrolling
                                  ? _enrollFace
                                  : null,
                              borderRadius: BorderRadius.circular(18),
                              child: Center(
                                child: _isEnrolling
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
                                            'Saving...',
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
                                            Icons.camera_rounded,
                                            color: _poseReady
                                                ? Colors.white
                                                : Colors.grey.shade500,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _currentPoseIndex ==
                                                        _requiredPoses - 1 &&
                                                    _poseReady
                                                ? 'Complete Enrollment'
                                                : 'Capture ${_poseLabels[_currentPoseIndex]}',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              color: _poseReady
                                                  ? Colors.white
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ).animate().fade(delay: 300.ms).slideY(begin: 0.2),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          // Add sign out button for users stuck on loading
          TextButton.icon(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: Icon(
              Icons.logout,
              color: Colors.white.withOpacity(0.5),
              size: 18,
            ),
            label: Text(
              'Sign Out',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getFrameColor() {
    if (_detectedFace == null) return Colors.white.withOpacity(0.3);
    if (!(_alignment?.isAligned ?? false)) return const Color(0xFFF59E0B);
    if (!_livenessVerified) return const Color(0xFF6366F1);
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
      color: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// Step indicator
class _StepIndicator extends StatelessWidget {
  final int step;
  final String label;
  final bool isComplete;
  final bool isActive;

  const _StepIndicator({
    required this.step,
    required this.label,
    required this.isComplete,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    if (isComplete) {
      color = const Color(0xFF10B981);
    } else if (isActive) {
      color = const Color(0xFF6366F1);
    } else {
      color = Colors.grey.shade300;
    }

    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isComplete ? color : Colors.transparent,
            border: Border.all(color: color, width: 3),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isComplete
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                : Text(
                    '$step',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: isActive || isComplete
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// Step connector line
class _StepLine extends StatelessWidget {
  final bool isComplete;

  const _StepLine({required this.isComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 3,
      margin: const EdgeInsets.only(bottom: 24, left: 8, right: 8),
      decoration: BoxDecoration(
        color: isComplete ? const Color(0xFF10B981) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
