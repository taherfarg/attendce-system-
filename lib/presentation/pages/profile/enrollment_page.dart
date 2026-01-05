import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/face/face_service.dart';

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

  Face? _detectedFace;
  FaceAlignmentResult? _alignment;

  bool _hasSeenEyesOpen = false;
  bool _hasSeenBlink = false;
  bool _livenessVerified = false;

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
      final status = await Permission.camera.request();
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

      await _faceService.initialize();

      final cameras = await availableCameras();
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

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Position your face';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Camera error: $e';
        });
      }
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing || _isEnrolling) return;
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

        if (!_livenessVerified) {
          if (liveness.eyeOpenScore > 0.8) _hasSeenEyesOpen = true;
          if (_hasSeenEyesOpen && liveness.isBlinking) _hasSeenBlink = true;
          if (_hasSeenEyesOpen &&
              _hasSeenBlink &&
              liveness.eyeOpenScore > 0.7) {
            _livenessVerified = true;
          }
        }

        if (mounted) {
          setState(() {
            _detectedFace = face;
            _alignment = alignment;

            if (!alignment.isAligned) {
              _statusMessage = alignment.instruction;
            } else if (!_livenessVerified) {
              if (!_hasSeenEyesOpen) {
                _statusMessage = 'Keep eyes open';
              } else if (!_hasSeenBlink) {
                _statusMessage = 'Blink once';
              } else {
                _statusMessage = 'Almost ready...';
              }
            } else {
              _statusMessage = 'Ready to save!';
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
    if (_detectedFace == null || !_livenessVerified || _isEnrolling) return;

    setState(() {
      _isEnrolling = true;
      _statusMessage = 'Saving...';
    });

    try {
      await _cameraController?.stopImageStream();

      final embedding = _faceService.generateEmbedding(_detectedFace!);
      final userId = Supabase.instance.client.auth.currentUser!.id;

      final response = await Supabase.instance.client.functions.invoke(
        'enroll_face',
        body: {'user_id': userId, 'face_embedding': embedding},
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
          _statusMessage = 'Failed - try again';
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: SizedBox(
                              width: double.infinity,
                              child: CameraPreview(_cameraController!),
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

                  // Bottom panel
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Progress steps
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _StepIndicator(
                              step: 1,
                              label: 'Detect',
                              isComplete: _detectedFace != null,
                              isActive: _detectedFace == null,
                            ),
                            _StepLine(isComplete: _detectedFace != null),
                            _StepIndicator(
                              step: 2,
                              label: 'Align',
                              isComplete: _alignment?.isAligned ?? false,
                              isActive:
                                  _detectedFace != null &&
                                  !(_alignment?.isAligned ?? false),
                            ),
                            _StepLine(
                              isComplete: _alignment?.isAligned ?? false,
                            ),
                            _StepIndicator(
                              step: 3,
                              label: 'Verify',
                              isComplete: _livenessVerified,
                              isActive:
                                  (_alignment?.isAligned ?? false) &&
                                  !_livenessVerified,
                            ),
                          ],
                        ).animate().fade(delay: 200.ms),
                        const SizedBox(height: 28),

                        // Enroll button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _livenessVerified && !_isEnrolling
                                ? _enrollFace
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade200,
                              disabledForegroundColor: Colors.grey.shade400,
                              elevation: _livenessVerified ? 8 : 0,
                              shadowColor: scheme.primary.withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isEnrolling
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
                                      const Text('Saving...'),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.save_rounded),
                                      SizedBox(width: 8),
                                      Text(
                                        'Save Face',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ).animate().fade(delay: 300.ms).scale(),
                        ),
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
