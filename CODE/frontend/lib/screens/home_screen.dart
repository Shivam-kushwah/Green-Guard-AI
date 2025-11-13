import 'package:flutter/material.dart';
import 'package:frontend/screens/detect_screen.dart';

import '../model/detection_result.dart';
import '../widgets/detection_card.dart';

List<DetectionResult> recentDetections = [];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text(" ")),
        body: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DetectScreen()),
                  );
                },
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    color: Colors.green,
                  ),

                  width: double.infinity,
                  height: 50,
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Upload Photo",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 50),
              Expanded(
                child: recentDetections.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.energy_savings_leaf,
                              size: 80,
                              color: Colors.green,
                            ),
                            SizedBox(height: 12),
                            Text(
                              "No detections yet.\nTry capturing a leaf photo.",
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: recentDetections.length,
                        itemBuilder: (context, index) {
                          final r = recentDetections[index];
                          return DetectionCard(
                            result: r,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DetectionDetailPage(result: r),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetectionDetailPage extends StatelessWidget {
  final DetectionResult result;
  const DetectionDetailPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Result"),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  result.image!,
                  height: 240,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              result.disease,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.species,
              style: TextStyle(color: Colors.green.shade700, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              "Confidence: ${result.confidence.toStringAsFixed(2)}%",
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Chip(
              label: Text(result.severity),
              backgroundColor: result.severity == "Severe"
                  ? Colors.red.shade100
                  : (result.severity == "Moderate"
                        ? Colors.orange.shade100
                        : Colors.green.shade100),
            ),
            const SizedBox(height: 18),
            const Text(
              "Recommendations",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(result.recommendation),
            const SizedBox(height: 30),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: const Text("Save Result"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(180, 45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
