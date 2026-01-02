# This file is a placeholder for the FaceNet TFLite model.

#

# To enable true face recognition (embeddings), download a FaceNet or ArcFace model:

#

# Option 1: MobileFaceNet (recommended for mobile)

# - Download from: https://github.com/sirius-ai/MobileFaceNet_TF

# - File: mobilefacenet.tflite (~1MB)

#

# Option 2: FaceNet

# - Download from: https://github.com/davidsandberg/facenet

# - Convert to TFLite format

# - File: facenet.tflite (~90MB)

#

# Option 3: ArcFace

# - Various implementations available

# - Generally better accuracy but larger size

#

# After downloading, place the .tflite file in this directory and update the path in:

# lib/core/face/face_service.dart

#

# Current implementation uses ML Kit landmarks as a simplified embedding.

# For production, integrate a proper TFLite model for accurate face matching.
