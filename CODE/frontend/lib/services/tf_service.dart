import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../model/detection_result.dart';

class TfService {
  TfService._private();
  static final TfService instance = TfService._private();

  Interpreter? _interpreter;
  Map<String, dynamic> _labelMap = {};

  bool get isLoaded => _interpreter != null;

  Future<void> loadModel() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/model/plant_disease_model.tflite',
      );
      final jsonStr = await rootBundle.loadString(
        'assets/model/class_mapping.json',
      );
      _labelMap = json.decode(jsonStr);
      print("TfService: model loaded, labels: ${_labelMap.length}");
    } catch (e) {
      print("TfService loadModel error: $e");
    }
  }

  Future<DetectionResult> predictFromFile(File imageFile) async {
    if (_interpreter == null) await loadModel();


    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception("Could not decode image");
    }
    final resized = img.copyResize(decoded, width: 128, height: 128);


    final input = List.generate(
      1,
      (i) => List.generate(
        128,
        (y) => List.generate(128, (x) {
          final pixel = resized.getPixel(x, y);
          final r = pixel.r / 255.0;
          final g = pixel.g / 255.0;
          final b = pixel.b / 255.0;
          return [r, g, b];
        }),
      ),
    );


    final output = List.filled(16, 0.0).reshape([1, 16]);

    _interpreter!.run(input, output);


    int index = 0;
    double maxVal = output[0][0];
    for (int i = 1; i < output[0].length; i++) {
      if (output[0][i] > maxVal) {
        maxVal = output[0][i];
        index = i;
      }
    }
    final confidence = (maxVal * 100.0);

    final label = _labelMap["$index"];
    final species = label[0];
    final disease = label[1];


    String severity = "Healthy";
    if (disease.toLowerCase().contains("healthy"))
      severity = "Healthy";
    else if (confidence > 85)
      severity = "Severe";
    else if (confidence > 60)
      severity = "Moderate";
    else
      severity = "Mild";


    String recommendation = _getRecommendation(disease);

    return DetectionResult(
      species: species,
      disease: disease,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      severity: severity,
      recommendation: recommendation,
      image: imageFile,
    );
  }

  String _getRecommendation(String disease) {
    final d = disease.toLowerCase();
    if (d.contains("blight") || d.contains("rust") || d.contains("bacterial")) {
      return "Apply recommended fungicide/bactericide. Remove infected leaves and avoid overhead irrigation.";
    } else if (d.contains("powdery")) {
      return "Use sulfur-based fungicide and improve air circulation around plants.";
    } else if (d.contains("healthy")) {
      return "Plant is healthy. Continue regular monitoring and good agronomic practices.";
    } else {
      return "Inspect plant closely; consider expert consultation or lab testing for precise diagnosis.";
    }
  }
}
