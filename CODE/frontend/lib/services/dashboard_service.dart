import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/disease_kb.dart';
import '../model/app_user.dart';
import '../model/district_stat.dart';
import '../model/intervention.dart';
import '../model/scan_record.dart';
import 'firestore_service.dart';

/// One disease cluster that an officer may need to act on.
///
/// Joins the aggregate case count with the department's response, which live
/// in separate collections - the counts are written by farmers, the response
/// by officers.
class OutbreakCluster {
  final String district;
  final DiseaseInfo disease;
  final int cases;
  final Intervention? intervention;
  final DateTime? lastReportedAt;

  const OutbreakCluster({
    required this.district,
    required this.disease,
    required this.cases,
    this.intervention,
    this.lastReportedAt,
  });

  InterventionStatus get status =>
      intervention?.status ?? InterventionStatus.unreviewed;

  bool get isOpen => status.isOpen;

  /// Cases added since an officer last touched this cluster. A growing number
  /// here on an acknowledged outbreak is the signal that response is not
  /// keeping pace.
  int get casesSinceUpdate {
    final i = intervention;
    if (i == null) return cases;
    final delta = cases - i.caseCountAtUpdate;
    return delta < 0 ? 0 : delta;
  }

  /// Ordering key for the officer's worklist. Notifiable diseases first, then
  /// by how many cases have accumulated without a response.
  int get priority {
    var p = cases;
    if (disease.notifiable) p += 100;
    if (status == InterventionStatus.unreviewed) p += 50;
    if (intervention?.isStalled == true) p += 30;
    if (status == InterventionStatus.resolved ||
        status == InterventionStatus.dismissed) {
      p -= 200;
    }
    return p;
  }
}

/// Backs the agriculture officer dashboard.
class DashboardService {
  DashboardService._();
  static final DashboardService instance = DashboardService._();

  final FirestoreService _fs = FirestoreService.instance;

  CollectionReference<Map<String, dynamic>> get _interventions =>
      FirebaseFirestore.instance.collection('interventions');

  Stream<List<Intervention>> watchInterventions() => _interventions
      .snapshots()
      .map((q) => q.docs.map(Intervention.fromDoc).toList());

  /// Every district/disease pair with at least one case, joined to its
  /// response record and sorted into an officer worklist.
  List<OutbreakCluster> buildClusters(
    List<DistrictStat> stats,
    List<Intervention> interventions,
  ) {
    final byId = {for (final i in interventions) i.id: i};
    final clusters = <OutbreakCluster>[];

    for (final stat in stats) {
      stat.byDisease.forEach((key, caseCount) {
        if (caseCount <= 0) return;

        DiseaseInfo? info;
        for (final d in DiseaseKb.all) {
          if (d.key == key) {
            info = d;
            break;
          }
        }
        if (info == null) return;

        clusters.add(
          OutbreakCluster(
            district: stat.district,
            disease: info,
            cases: caseCount,
            intervention: byId[Intervention.idFor(stat.district, key)],
            lastReportedAt: stat.lastReportedAt,
          ),
        );
      });
    }

    clusters.sort((a, b) => b.priority.compareTo(a.priority));
    return clusters;
  }

  /// Record or update the department's response to a cluster.
  Future<void> setInterventionStatus({
    required AppUser officer,
    required String district,
    required String diseaseKey,
    required InterventionStatus status,
    required int currentCaseCount,
    String? note,
  }) async {
    if (!officer.canViewDashboard) {
      throw StateError('Only an agriculture officer can set this.');
    }

    final id = Intervention.idFor(district, diseaseKey);
    final now = Timestamp.now();

    await _interventions.doc(id).set({
      'district': district,
      'diseaseKey': diseaseKey,
      'status': status.wire,
      'caseCountAtUpdate': currentCaseCount,
      'officerUid': officer.uid,
      'officerName': officer.name,
      'note': note,
      // Preserved on first write, left alone afterwards.
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  /// Disease counts over time, for the trend chart.
  ///
  /// Reads individual scans rather than the district rollups, because the
  /// rollups carry only a running total with no history. The window is capped:
  /// an unbounded scan query is the fastest way to burn the free read quota.
  Future<List<DailyCount>> diseaseTrend({
    int days = 30,
    String? species,
    String? district,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days));

    Query<Map<String, dynamic>> q = _fs.scans
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('createdAt');

    if (district != null) {
      q = q.where('district', isEqualTo: district);
    }

    final snap = await q.limit(1000).get();
    final scans = snap.docs.map(ScanRecord.fromDoc).toList();

    final filtered = species == null
        ? scans
        : scans.where((s) => s.species == species).toList();

    // Bucket by calendar day.
    final buckets = <DateTime, DailyCount>{};
    for (final s in filtered) {
      final day = DateTime(
        s.createdAt.year,
        s.createdAt.month,
        s.createdAt.day,
      );
      final existing = buckets[day];
      final isDisease = !s.isHealthy;
      buckets[day] = DailyCount(
        day: day,
        total: (existing?.total ?? 0) + 1,
        diseased: (existing?.diseased ?? 0) + (isDisease ? 1 : 0),
      );
    }

    final out = buckets.values.toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return out;
  }

  /// Crop-wise case totals for the dashboard breakdown.
  Map<String, int> cropBreakdown(List<DistrictStat> stats) {
    final out = <String, int>{};
    for (final s in stats) {
      s.bySpecies.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  /// Agreement between the model and expert ground truth.
  ///
  /// This is the dashboard's honest accuracy number: not the accuracy the
  /// model scored on its own held-out test split, but how often it matched a
  /// human on real field photos. Those two figures usually differ a lot, and
  /// the second one is the one an officer should be shown.
  Future<ModelAgreement> modelAgreement({int limit = 500}) async {
    final snap = await _fs.feedback.limit(limit).get();

    var confirmed = 0;
    var corrected = 0;
    final missesByDisease = <String, int>{};

    for (final doc in snap.docs) {
      final d = doc.data();
      final isCorrection = (d['isCorrection'] as bool?) ?? false;
      if (isCorrection) {
        corrected++;
        final aiLabel = (d['aiLabel'] as String?) ?? 'unknown';
        missesByDisease[aiLabel] = (missesByDisease[aiLabel] ?? 0) + 1;
      } else {
        confirmed++;
      }
    }

    return ModelAgreement(
      confirmed: confirmed,
      corrected: corrected,
      missesByDisease: missesByDisease,
    );
  }
}

/// One day in the trend chart.
class DailyCount {
  final DateTime day;
  final int total;
  final int diseased;

  const DailyCount({
    required this.day,
    required this.total,
    required this.diseased,
  });

  double get rate => total == 0 ? 0 : diseased / total;
}

/// How often expert verdicts backed the model.
class ModelAgreement {
  final int confirmed;
  final int corrected;

  /// AI label -> how many times an expert overturned it. The model's problem
  /// areas, which is what a retrain should target first.
  final Map<String, int> missesByDisease;

  const ModelAgreement({
    required this.confirmed,
    required this.corrected,
    required this.missesByDisease,
  });

  int get total => confirmed + corrected;

  /// Null rather than a misleading 100% when nothing has been reviewed yet.
  double? get agreementRate => total == 0 ? null : confirmed / total;

  /// Below this many samples the rate is noise, not a measurement.
  static const int minimumMeaningfulSample = 30;

  bool get isStatisticallyMeaningful => total >= minimumMeaningfulSample;

  /// Diseases the model gets wrong most often, worst first.
  List<({DiseaseInfo info, int misses})> get worstClasses {
    final out = <({DiseaseInfo info, int misses})>[];
    missesByDisease.forEach((key, misses) {
      for (final d in DiseaseKb.all) {
        if (d.key == key) {
          out.add((info: d, misses: misses));
          break;
        }
      }
    });
    out.sort((a, b) => b.misses.compareTo(a.misses));
    return out;
  }
}
