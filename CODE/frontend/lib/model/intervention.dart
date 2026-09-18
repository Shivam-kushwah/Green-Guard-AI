import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/disease_kb.dart';

/// Where a district-level outbreak sits in the department's response.
///
/// Deliberately a short, linear list. An officer under pressure needs to see
/// at a glance which outbreaks nobody has touched; a richer workflow with
/// branches would get filled in inconsistently and stop being trustworthy.
enum InterventionStatus {
  /// Flagged by the system, no officer has looked yet.
  unreviewed,

  /// An officer has seen it and accepts it is real.
  acknowledged,

  /// Field staff or inputs have been sent.
  dispatched,

  /// Contained - no new cases expected from this cluster.
  resolved,

  /// Looked at and judged not to need action (bad photos, isolated case).
  dismissed,
}

extension InterventionStatusX on InterventionStatus {
  String get wire => name;

  String get label => switch (this) {
    InterventionStatus.unreviewed => 'Not reviewed',
    InterventionStatus.acknowledged => 'Acknowledged',
    InterventionStatus.dispatched => 'Team dispatched',
    InterventionStatus.resolved => 'Resolved',
    InterventionStatus.dismissed => 'No action needed',
  };

  /// Still demands attention from someone.
  bool get isOpen =>
      this == InterventionStatus.unreviewed ||
      this == InterventionStatus.acknowledged ||
      this == InterventionStatus.dispatched;

  static InterventionStatus fromWire(String? v) =>
      InterventionStatus.values.firstWhere(
        (s) => s.name == v,
        orElse: () => InterventionStatus.unreviewed,
      );
}

/// The department's response to one disease cluster in one district.
///
/// Keyed by district + disease rather than by individual scan: an officer
/// intervenes in a place against a pathogen, not in a single farmer's photo.
class Intervention {
  final String id;
  final String district;
  final String diseaseKey;

  final InterventionStatus status;

  /// Case count at the time the status was last set, so the dashboard can show
  /// whether a cluster has grown since it was acknowledged.
  final int caseCountAtUpdate;

  final String? officerUid;
  final String? officerName;
  final String? note;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Intervention({
    required this.id,
    required this.district,
    required this.diseaseKey,
    required this.status,
    required this.caseCountAtUpdate,
    required this.createdAt,
    required this.updatedAt,
    this.officerUid,
    this.officerName,
    this.note,
  });

  /// Composite id, so one district/disease pair can only ever have one record.
  static String idFor(String district, String diseaseKey) =>
      '${district.toLowerCase().replaceAll(' ', '_')}__$diseaseKey';

  DiseaseInfo? get disease {
    for (final d in DiseaseKb.all) {
      if (d.key == diseaseKey) return d;
    }
    return null;
  }

  int get daysSinceUpdate => DateTime.now().difference(updatedAt).inDays;

  /// An acknowledged outbreak nobody has actioned in a week is drifting.
  bool get isStalled =>
      status == InterventionStatus.acknowledged && daysSinceUpdate >= 7;

  factory Intervention.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Intervention(
      id: doc.id,
      district: (d['district'] as String?) ?? '',
      diseaseKey: (d['diseaseKey'] as String?) ?? '',
      status: InterventionStatusX.fromWire(d['status'] as String?),
      caseCountAtUpdate: (d['caseCountAtUpdate'] as num?)?.toInt() ?? 0,
      officerUid: d['officerUid'] as String?,
      officerName: d['officerName'] as String?,
      note: d['note'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'district': district,
    'diseaseKey': diseaseKey,
    'status': status.wire,
    'caseCountAtUpdate': caseCountAtUpdate,
    'officerUid': officerUid,
    'officerName': officerName,
    'note': note,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };
}
