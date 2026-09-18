import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../config/app_config.dart';
import '../model/detection_result.dart';

class TfService {
  TfService._private();
  static final TfService instance = TfService._private();

  Interpreter? _interpreter;
  Map<String, dynamic> _labelMap = {};

  /// Ordered class labels, index-aligned with the model output.
  List<(String, String)> _labels = const [];

  /// Identifies the weights currently in use.
  ///
  /// Stamped onto every scan record. Without it the learning loop cannot tell
  /// whether a later model actually beat an earlier one on expert-verified
  /// cases - the comparison would silently mix predictions from both.
  String _modelVersion = 'bundled-v1';
  String get modelVersion => _modelVersion;

  /// Input edge length, read from the interpreter rather than hardcoded so a
  /// retrained model at a different resolution keeps working.
  int _inputSize = 128;

  bool get isLoaded => _interpreter != null;
  int get numClasses => _labels.length;

  Future<void> loadModel() async {
    if (_interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/model/plant_disease_model.tflite',
      );

      final jsonStr = await rootBundle.loadString(
        'assets/model/class_mapping.json',
      );
      _labelMap = json.decode(jsonStr) as Map<String, dynamic>;

      // Build an index-ordered label list. Sorting numerically matters -
      // JSON object key order is not guaranteed, and "10" sorts before "2"
      // as a string, which would silently mislabel every prediction.
      final indices = _labelMap.keys.map(int.parse).toList()..sort();
      _labels = [
        for (final i in indices)
          (
            (_labelMap['$i'] as List)[0] as String,
            (_labelMap['$i'] as List)[1] as String,
          ),
      ];
      DetectionResult.labelIndex = _labels;

      // Derive tensor shapes instead of assuming them, so a retrained model
      // with more classes or a different input size does not need a code edit.
      final inShape = _interpreter!.getInputTensor(0).shape;
      if (inShape.length >= 3) _inputSize = inShape[1];

      debugPrint(
        'TfService: model loaded - $_inputSize px input, '
        '${_labels.length} classes, version $_modelVersion',
      );
    } catch (e) {
      debugPrint('TfService loadModel error: $e');
    }
  }

  /// Swap in a model downloaded at runtime (the learning loop ships improved
  /// weights this way, without an app-store release).
  Future<void> loadModelFromFile(File modelFile, String version) async {
    _interpreter?.close();
    _interpreter = Interpreter.fromFile(modelFile);
    _modelVersion = version;
    final inShape = _interpreter!.getInputTensor(0).shape;
    if (inShape.length >= 3) _inputSize = inShape[1];
    debugPrint('TfService: swapped to model $version');
  }

  Future<DetectionResult> predictFromFile(File imageFile) async {
    if (_interpreter == null) await loadModel();
    if (_interpreter == null) {
      throw Exception('Model failed to load');
    }

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Could not decode image');
    }

    final resized = img.copyResize(
      decoded,
      width: _inputSize,
      height: _inputSize,
    );

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        }),
      ),
    );

    // Size the output buffer from the label map rather than a literal 16.
    // The hardcoded value was a latent break the moment the model is
    // retrained with additional classes.
    final classCount = _labels.length;
    final output = List.filled(classCount, 0.0).reshape([1, classCount]);

    _interpreter!.run(input, output);

    final probs = List<double>.from(output[0] as List);

    var index = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[index]) index = i;
    }

    final confidence = probs[index] * 100.0;
    final (species, disease) = _labels[index];

    return DetectionResult(
      species: species,
      disease: disease,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      probabilities: probs,
      modelVersion: _modelVersion,
      imagePath: imageFile.path,
      image: imageFile,
    );
  }

  /// Shrink and re-encode a leaf photo for upload.
  ///
  /// Runs on a background isolate because a 12 MP decode plus JPEG encode
  /// takes long enough to drop frames on a budget phone, and this happens
  /// right as the farmer is looking at the result screen.
  ///
  /// The size target is what lets the whole cloud layer stay on Firestore's
  /// free tier: a 640 px JPEG at quality 70 is ~60-90 KB, and base64 inflates
  /// that by a third, so it still fits the 1 MB document limit comfortably.
  static Future<String?> compressForUpload(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final b64 = await compute(_encodeForUpload, bytes);
      return b64;
    } catch (e) {
      debugPrint('TfService compressForUpload error: $e');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// Top-level so it can run via [compute].
String? _encodeForUpload(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final longest = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;

  final scaled = longest <= AppConfig.uploadMaxEdge
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height
              ? AppConfig.uploadMaxEdge
              : null,
          height: decoded.height > decoded.width
              ? AppConfig.uploadMaxEdge
              : null,
        );

  final jpeg = img.encodeJpg(scaled, quality: AppConfig.uploadJpegQuality);
  return base64Encode(jpeg);
}
