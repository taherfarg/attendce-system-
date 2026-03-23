import 'package:flutter/material.dart';

class FaceTestPage extends StatelessWidget {
  const FaceTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Embedding Test')),
      body: const Center(
        child: Text(
            'This feature relies on local file access and is not supported on web.',),
      ),
    );
  }
}
