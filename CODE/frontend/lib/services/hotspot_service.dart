import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/disease_kb.dart';
import '../data/maharashtra_districts.dart';
import '../model/district_stat.dart';
import '../model/scan_record.dart';
import 'firestore_service.dart';

/// Reads the district-level outbreak picture that the map and the officer
/// dashboard both draw from.
class HotspotService {
  HotspotService._();
  static final HotspotService instance = HotspotService._();

  final FirestoreService _fs = FirestoreService.instance;

  /// Live district aggregates.
  ///
  /// One document per district - 36 docs for the whole state - so this stays
  /// within the free tier no matter how many scans accumulate underneath.
  Stream<List<DistrictStat>> watchDistricts({bool includeDemo = true}) {
    return _fs.districtStats.snapshots().map((q) {
      final stats = q.docs.map(DistrictStat.fromDoc).toList();
      final filtered =
          includeDemo ? stats : stats.where((s) => !s.isDemo).toList();
      filtered.sort((a, b) => b.hotspotScore.compareTo(a.hotspotScore));
      return filtered;
    });
  }

  Future<List<DistrictStat>> getDistricts({bool includeDemo = true}) async {
    final q = await _fs.districtStats.get();
    final stats = q.docs.map(DistrictStat.fromDoc).toList();
    final filtered =
        includeDemo ? stats : stats.where((s) => !s.isDemo).toList();
    filtered.sort((a, b) => b.hotspotScore.compareTo(a.hotspotScore));
    return filtered;
  }

  /// Recent individual reports in one district, for the detail sheet.
  ///
  /// Capped deliberately: an unbounded query here is the easiest way to blow
  /// through the free read quota.
  Future<List<ScanRecord>> recentInDistrict(
    String district, {
    int limit = 20,
  }) async {
    final q = await _fs.scans
        .where('district', isEqualTo: district)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return q.docs.map(ScanRecord.fromDoc).toList();
  }

  /// Districts adjacent enough to matter for wind-borne diseases.
  ///
  /// Wheat yellow rust in particular travels on the wind across district
  /// lines, so a neighbouring outbreak is a genuine early warning rather than
  /// a statistic. Uses a simple radius rather than true shared borders -
  /// adequate at this scale and avoids shipping a polygon topology.
  Future<List<DistrictStat>> neighboursAtRisk(
    String district, {
    double radiusKm = 150,
  }) async {
    final home = MaharashtraDistricts.byName(district);
    if (home == null) return [];

    final all = await getDistricts();
    return all.where((s) {
      if (s.district == district) return false;
      if (s.hotspotScore < 30) return false;
      final ref = s.districtRef;
      if (ref == null) return false;
      return _distanceKm(home.lat, home.lng, ref.lat, ref.lng) <= radiusKm;
    }).toList();
  }

  /// State-wide totals for the dashboard header.
  StateSummary summarise(List<DistrictStat> stats) {
    var totalScans = 0;
    var totalCases = 0;
    var activeDistricts = 0;
    final byDisease = <String, int>{};
    final bySpecies = <String, int>{};

    for (final s in stats) {
      totalScans += s.totalScans;
      totalCases += s.diseaseCases;
      if (s.isActive && s.diseaseCases > 0) activeDistricts++;
      s.byDisease.forEach(
        (k, v) => byDisease[k] = (byDisease[k] ?? 0) + v,
      );
      s.bySpecies.forEach(
        (k, v) => bySpecies[k] = (bySpecies[k] ?? 0) + v,
      );
    }

    return StateSummary(
      totalScans: totalScans,
      totalCases: totalCases,
      districtsReporting: stats.where((s) => s.totalScans > 0).length,
      activeOutbreakDistricts: activeDistricts,
      byDisease: byDisease,
      bySpecies: bySpecies,
      topHotspots: stats.take(5).toList(),
    );
  }

  static double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ------------------------------------------------------------ demo seed

  /// Populates the map with plausible demonstration data.
  ///
  /// WHY THIS EXISTS, stated plainly: a real-time outbreak map needs real
  /// users, and a new deployment has none. Rather than let the map render
  /// empty, this writes a believable state-wide picture so the feature can be
  /// shown working end to end.
  ///
  /// Every row it writes carries isDemo: true. The dashboard can filter it
  /// out, and nothing here can ever be mistaken for a real farmer report.
  /// Delete it with [clearDemoData] before any real pilot.
  Future<void> seedDemoData({int seed = 42}) async {
    final rng = Random(seed);
    final batch = FirebaseFirestore.instance.batch();

    // Disease pressure follows the actual crop geography: red rot in the
    // sugarcane belt, rusts in the wheat districts, blights where potato and
    // maize are grown. A random scatter would look obviously fake to anyone
    // who knows Maharashtra.
    for (final district in MaharashtraDistricts.all) {
      if (district.majorCrops.isEmpty) continue;

      final candidates = <DiseaseInfo>[];
      for (final crop in district.majorCrops) {
        candidates.addAll(DiseaseKb.forSpecies(crop));
      }
      if (candidates.isEmpty) continue;

      final totalScans = 8 + rng.nextInt(60);
      final byDisease = <String, int>{};
      final bySpecies = <String, int>{};
      var diseaseCases = 0;

      // A handful of districts get a genuine outbreak so the map has real
      // structure rather than uniform noise.
      final isHotspot = rng.nextDouble() < 0.22;
      final picks = isHotspot ? 2 + rng.nextInt(2) : 1 + rng.nextInt(2);

      for (var i = 0; i < picks; i++) {
        final d = candidates[rng.nextInt(candidates.length)];
        final count = isHotspot ? 6 + rng.nextInt(18) : 1 + rng.nextInt(5);
        byDisease[d.key] = (byDisease[d.key] ?? 0) + count;
        bySpecies[d.species] = (bySpecies[d.species] ?? 0) + count;
        diseaseCases += count;
      }

      if (diseaseCases > totalScans) diseaseCases = totalScans;

      final stat = DistrictStat(
        district: district.name,
        region: district.region.label,
        lat: district.lat,
        lng: district.lng,
        totalScans: totalScans,
        diseaseCases: diseaseCases,
        byDisease: byDisease,
        bySpecies: bySpecies,
        lastReportedAt: DateTime.now().subtract(
          Duration(days: rng.nextInt(12), hours: rng.nextInt(24)),
        ),
        isDemo: true,
      );

      batch.set(
        _fs.districtStats.doc(district.name),
        stat.toMap(),
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    debugPrint('HotspotService: demo data seeded');
  }

  /// Removes every seeded district row. Run before a real pilot so no
  /// demonstration number ever reaches an officer's dashboard.
  Future<void> clearDemoData() async {
    final q = await _fs.districtStats.where('isDemo', isEqualTo: true).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in q.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('HotspotService: demo data cleared (${q.docs.length} rows)');
  }
}

/// State-wide rollup for the dashboard header.
class StateSummary {
  final int totalScans;
  final int totalCases;
  final int districtsReporting;
  final int activeOutbreakDistricts;
  final Map<String, int> byDisease;
  final Map<String, int> bySpecies;
  final List<DistrictStat> topHotspots;

  const StateSummary({
    required this.totalScans,
    required this.totalCases,
    required this.districtsReporting,
    required this.activeOutbreakDistricts,
    required this.byDisease,
    required this.bySpecies,
    required this.topHotspots,
  });

  double get stateInfectionRate =>
      totalScans == 0 ? 0 : totalCases / totalScans;

  /// Disease counts ordered worst first, resolved to knowledge-base entries.
  List<({DiseaseInfo info, int count})> get rankedDiseases {
    final out = <({DiseaseInfo info, int count})>[];
    for (final entry in byDisease.entries) {
      for (final d in DiseaseKb.all) {
        if (d.key == entry.key) {
          out.add((info: d, count: entry.value));
          break;
        }
      }
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }
}
