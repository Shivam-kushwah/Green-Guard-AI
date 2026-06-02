//

import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:frontend/model/detection_result.dart';
import 'package:frontend/model/diagnosis_history_model.dart';
import 'package:frontend/services/history_service.dart';
import 'package:frontend/services/tf_service.dart';
import 'package:image_picker/image_picker.dart';

import 'detection_result_screen.dart';

class ScanCameraScreen extends StatefulWidget {
  const ScanCameraScreen({super.key});

  @override
  State<ScanCameraScreen> createState() => _ScanCameraScreenState();
}

class _ScanCameraScreenState extends State<ScanCameraScreen> {
  bool isLoading = false;
  CameraController? controller;
  List<CameraDescription>? cameras;

  int cameraIndex = 0;

  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    cameras = await availableCameras();

    controller = CameraController(
      cameras![cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await controller!.initialize();

    if (mounted) setState(() {});
  }

  Future<void> captureImage() async {
    if (!controller!.value.isInitialized) return;

    try {
      setState(() {
        isLoading = true;
      });

      /// Take photo
      final image = await controller!.takePicture();

      File file = File(image.path);

      /// Run AI prediction
      final DetectionResult res = await TfService.instance.predictFromFile(
        file,
      );

      /// Save to Hive history
      await HistoryService.saveHistory(
        history: DiagnosisHistory(
          epochTime: DateTime.now().millisecondsSinceEpoch,

          plantName: res.species,

          imagePath: res.imagePath,

          result: res.severity,

          diagnosis: res.disease,

          confidence: res.confidence,
        ),
      );

      setState(() {
        isLoading = false;
      });

      /// Navigate to result screen
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetectionDetailPage(result: res)),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
      });

      print("Prediction Error: $e");
    }
  }

  Future<void> pickGallery() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked == null) return;

    File file = File(picked.path);

    setState(() {
      isLoading = true;
    });

    final DetectionResult res = await TfService.instance.predictFromFile(file);

    await HistoryService.saveHistory(
      history: DiagnosisHistory(
        epochTime: DateTime.now().millisecondsSinceEpoch,

        plantName: res.species,

        imagePath: res.imagePath,

        result: res.severity,

        diagnosis: res.disease,

        confidence: res.confidence,
      ),
    );

    setState(() {
      isLoading = false;
    });

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetectionDetailPage(result: res)),
    );
  }

  Future<void> switchCamera() async {
    cameraIndex = (cameraIndex + 1) % cameras!.length;

    await controller?.dispose();

    initCamera();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          if (isLoading)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),

          /// Camera Preview
          CameraPreview(controller!),

          /// Overlay UI
          SafeArea(
            child: Column(
              children: [
                /// TOP BAR
                Padding(
                  padding: const EdgeInsets.all(16),

                  child: Row(
                    children: [
                      /// Back
                      _circleIcon(
                        Icons.arrow_back,
                        () => Navigator.pop(context),
                      ),

                      const SizedBox(width: 12),

                      /// Title
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              "Green Guard Plant Scan",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            Text(
                              "PRECISION SCAN",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),

                      /// Flash
                      _circleIcon(Icons.flash_on, () {}),
                    ],
                  ),
                ),

                const Spacer(),

                /// SCAN FRAME
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 260,
                        height: 340,

                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),

                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),

                      /// Floating dots
                      Positioned(left: 30, top: 120, child: _dot()),

                      Positioned(right: 30, bottom: 80, child: _dot()),

                      Positioned(left: 120, bottom: 30, child: _dot()),
                    ],
                  ),
                ),

                const Spacer(),

                /// BOTTOM BLUR PANEL
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),

                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),

                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                      ),

                      child: Column(
                        children: [
                          /// Buttons row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,

                            children: [
                              /// Gallery
                              _circleIcon(Icons.image, pickGallery),

                              /// Capture
                              GestureDetector(
                                onTap: captureImage,

                                child: Container(
                                  width: 72,
                                  height: 72,

                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green,
                                  ),

                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),

                              /// Flip
                              _circleIcon(Icons.flip_camera_ios, switchCamera),
                            ],
                          ),

                          const SizedBox(height: 14),

                          /// Cancel
                          GestureDetector(
                            onTap: () => Navigator.pop(context),

                            child: const Text(
                              "CANCEL SCAN",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
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
        ],
      ),
    );
  }

  /// Small dot
  Widget _dot() {
    return Container(
      width: 8,
      height: 8,

      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    );
  }

  /// Circle icon button
  Widget _circleIcon(IconData icon, VoidCallback onTap) {
    return Container(
      width: 46,
      height: 46,

      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),

        shape: BoxShape.circle,
      ),

      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}
