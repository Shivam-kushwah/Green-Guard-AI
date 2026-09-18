import 'dart:io';

import '../config/app_config.dart';
import '../data/disease_kb.dart';

/// The outcome of one on-device inference.
class DetectionResult {
  final String species;
  final String disease;

  /// How sure the *model* is, 0-100.
  ///
  /// This is a property of the classifier, not of the plant. A crisp photo of
  /// a mildly infected leaf scores high; a blurry photo of a dying one scores
  /// low. Do not present it as disease severity - use [threat] for that.
  final double confidence;

  /// Full class-probability vector, kept so a low-confidence result can show
  /// the runner-up instead of pretending the top guess is the only candidate.
  final List<double> probabilities;

  /// Which model produced this. Stamped onto every cloud record so the
  /// learning loop can compare model versions against expert ground truth.
  final String modelVersion;

  final File? image;
  final DateTime time;
  final String imagePath;

  DetectionResult({
    required this.species,
    required this.disease,
    required this.confidence,
    required this.imagePath,
    required this.modelVersion,
    this.probabilities = const [],
    this.image,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  /// Agronomic facts for this class.
  DiseaseInfo get info => DiseaseKb.resolve(species, disease);

  /// How dangerous the disease is if genuinely present. Comes from the
  /// knowledge base, never from [confidence].
  ThreatLevel get threat => info.threat;

  bool get isHealthy => info.isHealthy;

  /// Kept for the existing result and history screens, but now meaning
  /// "threat posed by this disease" rather than the old confidence banding.
  String get severity => threat.label;

  String get recommendation => info.treatment;

  /// Below this the model is effectively guessing between classes, and we say
  /// so rather than presenting a diagnosis the farmer might spray against.
  bool get isLowCertainty => confidence < AppConfig.lowCertaintyThreshold;

  /// Whether the farmer should be actively pushed toward expert review:
  /// either the model is unsure, or the call is serious enough that a human
  /// should confirm before an expensive or irreversible intervention.
  bool get shouldSeekExpert =>
      !isHealthy &&
      (isLowCertainty ||
          threat == ThreatLevel.critical ||
          info.notifiable);

  /// Second-best class, for the "it might also be" hint on low-certainty
  /// results. Null when we have no probability vector or no clear runner-up.
  ({String species, String disease, double confidence})? get runnerUp {
    if (probabilities.length < 2) return null;
    var bestIdx = 0, secondIdx = -1;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[bestIdx]) bestIdx = i;
    }
    for (var i = 0; i < probabilities.length; i++) {
      if (i == bestIdx) continue;
      if (secondIdx == -1 || probabilities[i] > probabilities[secondIdx]) {
        secondIdx = i;
      }
    }
    if (secondIdx == -1) return null;
    final labels = _labelsByIndex;
    if (secondIdx >= labels.length) return null;
    final l = labels[secondIdx];
    return (
      species: l.$1,
      disease: l.$2,
      confidence: probabilities[secondIdx] * 100,
    );
  }

  /// Set by TfService once the label map is loaded, so the runner-up lookup
  /// can name an index without re-reading the asset.
  static List<(String, String)> _labelsByIndex = const [];
  static set labelIndex(List<(String, String)> labels) =>
      _labelsByIndex = labels;
}
