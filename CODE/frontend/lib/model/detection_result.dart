import 'dart:io';

class DetectionResult {
  final String species;
  final String disease;
  final double confidence;
  final String severity; // Healthy/Moderate/Severe
  final String recommendation;
  final File? image;
  final DateTime time;

  DetectionResult({
    required this.species,
    required this.disease,
    required this.confidence,
    required this.severity,
    required this.recommendation,
    this.image,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}
