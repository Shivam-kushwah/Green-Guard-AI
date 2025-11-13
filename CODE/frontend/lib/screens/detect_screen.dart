import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../model/detection_result.dart';
import '../services/tf_service.dart';
import 'home_screen.dart';

class DetectScreen extends StatefulWidget {
  const DetectScreen({super.key});
  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  File? _image;
  bool _loading = false;

  Future<void> _pick(ImageSource src) async {
    final pick = ImagePicker();
    final picked = await pick.pickImage(source: src, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _loading = true;
    });

    final DetectionResult res = await TfService.instance.predictFromFile(
      _image!,
    );

    recentDetections.insert(0, res);

    setState(() {
      _loading = false;
    });

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetectionDetailPage(result: res)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text("Detect Disease")),
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _image != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                _image!,
                                height: 180,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container(
                              height: 180,
                              color: Colors.grey[100],
                              child: const Center(
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _pick(ImageSource.camera),
                            icon: const Icon(
                              Icons.camera_alt,
                              color: Colors.green,
                            ),
                            label: const Text(
                              "Take Photo",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _pick(ImageSource.gallery),
                            icon: const Icon(Icons.photo, color: Colors.green),
                            label: const Text(
                              "Choose Gallery",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_loading) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Tips: Make sure the leaf fills the frame, good lighting, single leaf preferred.",
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
