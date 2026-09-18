import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/disease_kb.dart';
import '../data/maharashtra_districts.dart';

/// Aggregated disease reports for one district.
///
/// Maintained by clients via atomic increments (see FirestoreService), because
/// the free Firestore tier has no Cloud Functions to do it server-side. It is
/// a denormalised rollup: reading it costs one document instead of scanning
/// every scan in the district, which is what makes the map and the officer
/// dashboard cheap enough to run on the free quota.
class DistrictStat {
  final String district;
  final String region;
  final double lat;
  final double lng;

  final int totalScans;
  final int diseaseCases;

  /// diseaseKey -> count.
  final Map<String, int> byDisease;

  /// species -> count.
  final Map<String, int> bySpecies;

  final DateTime? lastReportedAt;

  /// Seeded demonstration data rather than real farmer reports.
  ///
  /// This flag exists because a hotspot map with no users is an empty map, and
  /// a demo needs something on screen. Keeping it explicit means demo rows can
  /// always be filtered out and can never be mistaken for real surveillance
  /// data by an officer looking at the dashboard.
  final bool isDemo;

  const DistrictStat({
    required this.district,
    required this.region,
    required this.lat,
    required this.lng,
    required this.totalScans,
    required this.diseaseCases,
    required this.byDisease,
    required this.bySpecies,
    this.lastReportedAt,
    this.isDemo = false,
  });

  /// Share of scans here that found disease, 0-1.
  double get infectionRate =>
      totalScans == 0 ? 0 : diseaseCases / totalScans;

  /// Most-reported disease in this district, or null if none.
  MapEntry<String, int>? get dominantDisease {
    if (byDisease.isEmpty) return null;
    return byDisease.entries.reduce((a, b) => a.value >= b.value ? a : b);
  }

  DiseaseInfo? get dominantDiseaseInfo {
    final key = dominantDisease?.key;
    if (key == null) return null;
    for (final d in DiseaseKb.all) {
      if (d.key == key) return d;
    }
    return null;
  }

  /// True when a notifiable disease (late blight, red rot, yellow rust) has
  /// been reported here - the cases a state officer needs to see first.
  bool get hasNotifiableDisease {
    for (final d in DiseaseKb.notifiable) {
      if ((byDisease[d.key] ?? 0) > 0) return true;
    }
    return false;
  }

  /// How stale this district's data is. An officer must be able to tell "no
  /// disease here" apart from "nobody has scanned here in a month".
  int? get daysSinceLastReport => lastReportedAt == null
      ? null
      : DateTime.now().difference(lastReportedAt!).inDays;

  bool get isActive {
    final days = daysSinceLastReport;
    return days != null && days <= 14;
  }

  /// 0-100 hotspot intensity for the map ramp.
  ///
  /// Combines how many cases there are with what share of scans they
  /// represent, then decays with age. Raw case count alone would just draw a
  /// population map - the districts with the most farmers would always look
  /// worst regardless of actual disease pressure.
  double get hotspotScore {
    if (diseaseCases == 0) return 0;

    // Volume, saturating at 25 cases. Beyond that the advice does not change.
    final volume = (diseaseCases / 25.0).clamp(0.0, 1.0);

    // Prevalence, which is what separates a genuine outbreak from a busy
    // district. Needs a minimum sample before it means anything.
    final prevalence = totalScans >= 5 ? infectionRate : 0.0;

    // Reports older than three weeks stop counting as current.
    final days = daysSinceLastReport ?? 0;
    final recency = (1.0 - days / 21.0).clamp(0.0, 1.0);

    var score = 100 * (0.45 * volume + 0.55 * prevalence) * recency;

    // A notifiable disease anywhere in the district floors the score at
    // "high", because those spread fast enough that a small count still
    // warrants attention.
    if (hasNotifiableDisease && score < 45) score = 45;

    return double.parse(score.clamp(0, 100).toStringAsFixed(1));
  }

  District? get districtRef => MaharashtraDistricts.byName(district);

  factory DistrictStat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DistrictStat(
      district: (d['district'] as String?) ?? doc.id,
      region: (d['region'] as String?) ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      totalScans: (d['totalScans'] as num?)?.toInt() ?? 0,
      diseaseCases: (d['diseaseCases'] as num?)?.toInt() ?? 0,
      byDisease: _intMap(d['byDisease']),
      bySpecies: _intMap(d['bySpecies']),
      lastReportedAt: (d['lastReportedAt'] as Timestamp?)?.toDate(),
      isDemo: (d['isDemo'] as bool?) ?? false,
    );
  }

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return {};
    return raw.map(
      (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
    );
  }

  Map<String, dynamic> toMap() => {
    'district': district,
    'region': region,
    'lat': lat,
    'lng': lng,
    'totalScans': totalScans,
    'diseaseCases': diseaseCases,
    'byDisease': byDisease,
    'bySpecies': bySpecies,
    'lastReportedAt':
        lastReportedAt == null ? null : Timestamp.fromDate(lastReportedAt!),
    'isDemo': isDemo,
  };
}
