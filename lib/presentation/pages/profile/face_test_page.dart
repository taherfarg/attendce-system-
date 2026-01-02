import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../../core/face/face_service.dart';

/// Test page for enrolling face from LOCAL photos
/// Points to: C:\Users\U\StudioProjects\attendance_system\taher farg -it
class FaceTestPage extends StatefulWidget {
  const FaceTestPage({super.key});

  @override
  State<FaceTestPage> createState() => _FaceTestPageState();
}

class _FaceTestPageState extends State<FaceTestPage> {
  final SupabaseClient _client = Supabase.instance.client;
  final FaceService _faceService = FaceService();

  // ⚠️ YOUR LOCAL PHOTO FOLDER PATH
  static const String localPhotoPath =
      r'C:\Users\U\StudioProjects\attendance_system\taher farg -it';

  bool _isLoading = false;
  String _status = 'Ready';
  List<File>? _localFiles;
  File? _selectedFile;
  Uint8List? _imageBytes;
  List<double>? _extractedEmbedding;

  @override
  void initState() {
    super.initState();
    _faceService.initialize();
    _loadLocalFiles();
  }

  @override
  void dispose() {
    _faceService.dispose();
    super.dispose();
  }

  /// Load list of files from local folder
  Future<void> _loadLocalFiles() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading files from local folder...';
    });

    try {
      final directory = Directory(localPhotoPath);

      if (!await directory.exists()) {
        setState(() {
          _isLoading = false;
          _status = 'Folder not found: $localPhotoPath';
        });
        return;
      }

      final allFiles = directory.listSync();
      final imageFiles = <File>[];

      for (final entity in allFiles) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          if (path.endsWith('.jpg') ||
              path.endsWith('.jpeg') ||
              path.endsWith('.png')) {
            imageFiles.add(entity);
          }
        }
      }

      setState(() {
        _localFiles = imageFiles;
        _isLoading = false;
        _status = 'Found ${imageFiles.length} image(s) in local folder';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error loading files: $e';
      });
    }
  }

  /// Load selected local image
  Future<void> _loadLocalImage(File file) async {
    setState(() {
      _isLoading = true;
      _selectedFile = file;
      _status = 'Loading ${file.path.split(Platform.pathSeparator).last}...';
      _extractedEmbedding = null;
    });

    try {
      final bytes = await file.readAsBytes();

      setState(() {
        _imageBytes = bytes;
        _status = 'Loaded! Ready to extract embedding.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Load error: $e';
      });
    }
  }

  /// Extract face embedding from image using file-based InputImage
  Future<void> _extractEmbedding() async {
    if (_selectedFile == null) return;

    setState(() {
      _isLoading = true;
      _status = 'Extracting face embedding...';
    });

    try {
      // Use InputImage.fromFilePath for local files (more reliable)
      final inputImage = InputImage.fromFilePath(_selectedFile!.path);

      // Detect faces
      final faces = await _faceService.detectFaces(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _isLoading = false;
          _status = '❌ No face detected in image!';
        });
        return;
      }

      if (faces.length > 1) {
        setState(() {
          _isLoading = false;
          _status =
              '⚠️ Multiple faces (${faces.length}) detected. Using first face.';
        });
      }

      // Extract embedding from first face
      final embedding = _faceService.generateEmbedding(faces.first);

      setState(() {
        _extractedEmbedding = embedding;
        _isLoading = false;
        _status = '✅ Embedding extracted! (${embedding.length} dimensions)';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Extraction error: $e';
      });
    }
  }

  /// Save embedding to database via Edge Function
  Future<void> _saveEmbedding() async {
    if (_extractedEmbedding == null) return;

    setState(() {
      _isLoading = true;
      _status = 'Saving embedding to database...';
    });

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not logged in! Please login first.');
      }

      // Call the enroll_face edge function
      final response = await _client.functions.invoke(
        'enroll_face',
        body: {'user_id': userId, 'face_embedding': _extractedEmbedding},
      );

      if (response.status == 200) {
        setState(() {
          _status =
              '✅ SUCCESS! Embedding saved. You can now test check-in with camera!';
          _isLoading = false;
        });
      } else {
        final error = response.data is Map
            ? response.data['error']
            : response.data.toString();
        throw Exception(error ?? 'Unknown error');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = '❌ Save error: $e';
      });
    }
  }

  /// Test match with existing stored embedding
  Future<void> _testMatch() async {
    if (_extractedEmbedding == null) return;

    setState(() {
      _isLoading = true;
      _status = 'Fetching stored embedding from database...';
    });

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      // Fetch stored embedding from face_profiles table
      final response = await _client
          .from('face_profiles')
          .select('face_embedding')
          .eq('user_id', userId)
          .single();

      final storedEmbedding = (response['face_embedding'] as List)
          .map((e) => (e as num).toDouble())
          .toList();

      // Compare embeddings using Euclidean distance
      final distance = _faceService.compareEmbeddings(
        _extractedEmbedding!,
        storedEmbedding,
      );

      final isMatch = _faceService.isMatch(
        _extractedEmbedding!,
        storedEmbedding,
      );

      setState(() {
        _isLoading = false;
        _status = isMatch
            ? '✅ MATCH! Distance: ${distance.toStringAsFixed(4)} (< 0.8 threshold)'
            : '❌ NO MATCH. Distance: ${distance.toStringAsFixed(4)} (threshold: 0.8)';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = '❌ Test error: $e';
      });
    }
  }

  String _getFileName(File file) {
    return file.path.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Embedding Test'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLocalFiles,
            tooltip: 'Reload files',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Folder path info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localPhotoPath,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Status card
            Card(
              color: const Color(0xFFF1F5F9),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Step 1: File list
            const Text(
              'Step 1: Select Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            if (_localFiles != null && _localFiles!.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _localFiles!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final file = _localFiles![index];
                    final isSelected = _selectedFile?.path == file.path;
                    return ListTile(
                      leading: Icon(
                        Icons.image,
                        color: isSelected
                            ? const Color(0xFF6366F1)
                            : Colors.grey,
                      ),
                      title: Text(_getFileName(file)),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF10B981),
                            )
                          : null,
                      onTap: () => _loadLocalImage(file),
                    );
                  },
                ),
              )
            else if (_localFiles == null)
              const Center(child: CircularProgressIndicator())
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 48),
                    SizedBox(height: 8),
                    Text('No images found in folder'),
                    Text(
                      'Make sure folder contains .jpg, .jpeg, or .png files',
                    ),
                  ],
                ),
              ),

            // Step 2: Preview and extract
            if (_imageBytes != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Step 2: Preview & Extract',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  height: 250,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _extractEmbedding,
                  icon: const Icon(Icons.face),
                  label: const Text('Extract Face Embedding'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],

            // Step 3: Save or test
            if (_extractedEmbedding != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Step 3: Save or Test',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveEmbedding,
                      icon: const Icon(Icons.save),
                      label: const Text('Save to DB'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _testMatch,
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('Test Match'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // Info section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFF59E0B)),
                      SizedBox(width: 8),
                      Text(
                        'How This Works',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Select a photo from your local folder\n'
                    '2. Extract 128-dimension face embedding\n'
                    '3. Save to database as your reference face\n'
                    '4. Use check-in page to verify with camera!',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
