import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/face/face_service.dart';

/// Modern minimal face enrollment page
class EnrollmentPage extends StatefulWidget {
  const EnrollmentPage({super.key});

  @override
  State<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends State<EnrollmentPage> {
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

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
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
                _statusMessage = 'Please blink';
              } else {
                _statusMessage = 'Almost there...';
              }
            } else {
              _statusMessage = 'Ready!';
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

      debugPrint('Enrolling face for user: $userId');
      debugPrint('Embedding size: ${embedding.length}');

      final response = await Supabase.instance.client.functions.invoke(
        'enroll_face',
        body: {'user_id': userId, 'face_embedding': embedding},
      );

      debugPrint('Response status: ${response.status}');
      debugPrint('Response data: ${response.data}');

      if (response.status == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Face enrolled successfully!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } else {
        final errorMsg = response.data is Map
            ? (response.data['error'] ?? 'Unknown error')
            : response.data.toString();
        throw Exception('Status ${response.status}: $errorMsg');
      }
    } catch (e) {
      debugPrint('Enrollment error: $e');
      if (mounted) {
        setState(() {
          _isEnrolling = false;
          _statusMessage = 'Error: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        await _cameraController?.startImageStream(_processImage);
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E293B),
      body: SafeArea(
        child: _isInitializing
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Starting camera...',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  // Camera preview
                  if (_cameraController != null &&
                      _cameraController!.value.isInitialized)
                    Positioned.fill(child: CameraPreview(_cameraController!)),

                  // Gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                          stops: const [0, 0.2, 0.6, 1],
                        ),
                      ),
                    ),
                  ),

                  // Face frame
                  Center(
                    child: Container(
                      width: 260,
                      height: 340,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(130),
                        border: Border.all(color: _getFrameColor(), width: 3),
                      ),
                    ),
                  ),

                  // Top bar
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () =>
                                Supabase.instance.client.auth.signOut(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _getFrameColor().withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  // Bottom panel
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // Progress indicators
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _StepDot(
                                label: 'Detect',
                                isComplete: _detectedFace != null,
                                isActive: _detectedFace == null,
                              ),
                              _StepLine(isComplete: _detectedFace != null),
                              _StepDot(
                                label: 'Align',
                                isComplete: _alignment?.isAligned ?? false,
                                isActive:
                                    _detectedFace != null &&
                                    !(_alignment?.isAligned ?? false),
                              ),
                              _StepLine(
                                isComplete: _alignment?.isAligned ?? false,
                              ),
                              _StepDot(
                                label: 'Verify',
                                isComplete: _livenessVerified,
                                isActive:
                                    (_alignment?.isAligned ?? false) &&
                                    !_livenessVerified,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Enroll button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _livenessVerified && !_isEnrolling
                                  ? _enrollFace
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.shade700,
                                disabledForegroundColor: Colors.grey.shade500,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isEnrolling
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Save Face',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Color _getFrameColor() {
    if (_detectedFace == null) return Colors.grey;
    if (!(_alignment?.isAligned ?? false)) return const Color(0xFFF59E0B);
    if (!_livenessVerified) return const Color(0xFF6366F1);
    return const Color(0xFF10B981);
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool isComplete;
  final bool isActive;

  const _StepDot({
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
      color = Colors.grey.shade600;
    }

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isComplete ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
            shape: BoxShape.circle,
          ),
          child: isComplete
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
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

class _StepLine extends StatelessWidget {
  final bool isComplete;

  const _StepLine({required this.isComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: isComplete ? const Color(0xFF10B981) : Colors.grey.shade600,
    );
  }
}
