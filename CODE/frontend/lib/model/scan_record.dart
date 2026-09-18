import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/disease_kb.dart';

/// Where a scan sits in the expert-review pipeline.
enum ReviewStatus {
  /// Never submitted for review.
  none,

  /// Waiting in the queue, inside the 24 h window.
  pending,

  /// An agronomist agreed with the AI.
  confirmed,

  /// An agronomist disagreed - this is the valuable one for the learning loop.
  corrected,

  /// Nobody answered inside the SLA window.
  expired,
}

extension ReviewStatusX on ReviewStatus {
  String get wire => name;

  String get label => switch (this) {
    ReviewStatus.none => 'Not reviewed',
    ReviewStatus.pending => 'Awaiting expert',
    ReviewStatus.confirmed => 'Expert confirmed',
    ReviewStatus.corrected => 'Expert corrected',
    ReviewStatus.expired => 'No expert response',
  };

  bool get isResolved =>
      this == ReviewStatus.confirmed || this == ReviewStatus.corrected;

  static ReviewStatus fromWire(String? v) => ReviewStatus.values.firstWhere(
    (s) => s.name == v,
    orElse: () => ReviewStatus.none,
  );
}

/// One disease detection, as stored in the cloud.
///
/// This single document backs four features at once: it is the hotspot map
/// data point, the expert review subject, the dashboard statistic, and - once
/// an expert rules on it - a labelled training sample.
class ScanRecord {
  final String id;
  final String uid;
  final String farmerName;

  // --- what the model said ---
  final String species;
  final String disease;
  final String diseaseKey;

  /// Model certainty, 0-100. This is how sure the *classifier* is, and is
  /// deliberately kept separate from [threatLevel], which is how dangerous the
  /// disease is. Conflating the two was a bug in the original build.
  final double confidence;

  /// Threat posed by this disease if genuinely present, from the knowledge
  /// base - not derived from confidence.
  final String threatLevel;

  /// Which model produced this. Essential for the learning loop: without it we
  /// cannot tell whether a later model actually improved on an earlier one.
  final String modelVersion;

  // --- where ---
  final String district;
  final String region;

  /// Coordinates rounded before upload (see AppConfig.publicCoordPrecision).
  /// Precise farm location never leaves the device.
  final double lat;
  final double lng;

  // --- image ---
  /// Compressed JPEG as base64. Only populated when the farmer submits for
  /// review or opts in to sharing - we do not upload every scan by default.
  final String? imageBase64;

  /// Local device path, for the farmer's own history view.
  final String? localImagePath;

  // --- expert review ---
  final ReviewStatus reviewStatus;
  final String? expertUid;
  final String? expertName;
  final String? expertQualification;

  /// The expert's ruling. Equals [disease] when confirmed, differs when
  /// corrected. Null while pending.
  final String? expertDisease;
  final String? expertSpecies;
  final String? expertNote;
  final DateTime? reviewRequestedAt;
  final DateTime? reviewedAt;

  /// Whether this scan counts toward public hotspot aggregates.
  final bool contributesToMap;

  final DateTime createdAt;

  const ScanRecord({
    required this.id,
    required this.uid,
    required this.farmerName,
    required this.species,
    required this.disease,
    required this.diseaseKey,
    required this.confidence,
    required this.threatLevel,
    required this.modelVersion,
    required this.district,
    required this.region,
    required this.lat,
    required this.lng,
    required this.createdAt,
    this.imageBase64,
    this.localImagePath,
    this.reviewStatus = ReviewStatus.none,
    this.expertUid,
    this.expertName,
    this.expertQualification,
    this.expertDisease,
    this.expertSpecies,
    this.expertNote,
    this.reviewRequestedAt,
    this.reviewedAt,
    this.contributesToMap = true,
  });

  DiseaseInfo get info => DiseaseKb.resolve(species, disease);

  bool get isHealthy => info.isHealthy;

  /// The label we currently believe is correct: the expert's if one ruled,
  /// otherwise the model's. This is what the map and dashboard should count.
  String get effectiveDisease => expertDisease ?? disease;
  String get effectiveSpecies => expertSpecies ?? species;

  /// True when an expert overturned the AI. These are the samples worth their
  /// weight in gold for retraining.
  bool get isCorrection => reviewStatus == ReviewStatus.corrected;

  /// True when a human has signed off either way - the only scans we trust as
  /// ground truth.
  bool get isVerified => reviewStatus.isResolved;

  /// Hours left before the SLA window closes, negative once breached.
  double? slaHoursRemaining(Duration window) {
    if (reviewStatus != ReviewStatus.pending || reviewRequestedAt == null) {
      return null;
    }
    final deadline = reviewRequestedAt!.add(window);
    return deadline.difference(DateTime.now()).inMinutes / 60.0;
  }

  factory ScanRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ScanRecord(
      id: doc.id,
      uid: (d['uid'] as String?) ?? '',
      farmerName: (d['farmerName'] as String?) ?? '',
      species: (d['species'] as String?) ?? '',
      disease: (d['disease'] as String?) ?? '',
      diseaseKey: (d['diseaseKey'] as String?) ?? '',
      confidence: (d['confidence'] as num?)?.toDouble() ?? 0,
      threatLevel: (d['threatLevel'] as String?) ?? 'Moderate',
      modelVersion: (d['modelVersion'] as String?) ?? 'unknown',
      district: (d['district'] as String?) ?? 'Unknown',
      region: (d['region'] as String?) ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      imageBase64: d['imageBase64'] as String?,
      localImagePath: d['localImagePath'] as String?,
      reviewStatus: ReviewStatusX.fromWire(d['reviewStatus'] as String?),
      expertUid: d['expertUid'] as String?,
      expertName: d['expertName'] as String?,
      expertQualification: d['expertQualification'] as String?,
      expertDisease: d['expertDisease'] as String?,
      expertSpecies: d['expertSpecies'] as String?,
      expertNote: d['expertNote'] as String?,
      reviewRequestedAt:
          (d['reviewRequestedAt'] as Timestamp?)?.toDate(),
      reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
      contributesToMap: (d['contributesToMap'] as bool?) ?? true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'farmerName': farmerName,
    'species': species,
    'disease': disease,
    'diseaseKey': diseaseKey,
    'confidence': confidence,
    'threatLevel': threatLevel,
    'modelVersion': modelVersion,
    'district': district,
    'region': region,
    'lat': lat,
    'lng': lng,
    if (imageBase64 != null) 'imageBase64': imageBase64,
    'reviewStatus': reviewStatus.wire,
    'expertUid': expertUid,
    'expertName': expertName,
    'expertQualification': expertQualification,
    'expertDisease': expertDisease,
    'expertSpecies': expertSpecies,
    'expertNote': expertNote,
    'reviewRequestedAt': reviewRequestedAt == null
        ? null
        : Timestamp.fromDate(reviewRequestedAt!),
    'reviewedAt':
        reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
    'contributesToMap': contributesToMap,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  ScanRecord copyWith({
    String? id,
    String? imageBase64,
    String? localImagePath,
    ReviewStatus? reviewStatus,
    String? expertUid,
    String? expertName,
    String? expertQualification,
    String? expertDisease,
    String? expertSpecies,
    String? expertNote,
    DateTime? reviewRequestedAt,
    DateTime? reviewedAt,
  }) => ScanRecord(
    id: id ?? this.id,
    uid: uid,
    farmerName: farmerName,
    species: species,
    disease: disease,
    diseaseKey: diseaseKey,
    confidence: confidence,
    threatLevel: threatLevel,
    modelVersion: modelVersion,
    district: district,
    region: region,
    lat: lat,
    lng: lng,
    imageBase64: imageBase64 ?? this.imageBase64,
    localImagePath: localImagePath ?? this.localImagePath,
    reviewStatus: reviewStatus ?? this.reviewStatus,
    expertUid: expertUid ?? this.expertUid,
    expertName: expertName ?? this.expertName,
    expertQualification: expertQualification ?? this.expertQualification,
    expertDisease: expertDisease ?? this.expertDisease,
    expertSpecies: expertSpecies ?? this.expertSpecies,
    expertNote: expertNote ?? this.expertNote,
    reviewRequestedAt: reviewRequestedAt ?? this.reviewRequestedAt,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    contributesToMap: contributesToMap,
    createdAt: createdAt,
  );
}
