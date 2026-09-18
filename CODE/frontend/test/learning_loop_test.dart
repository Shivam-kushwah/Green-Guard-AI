import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/disease_kb.dart';
import 'package:frontend/model/district_stat.dart';
import 'package:frontend/model/intervention.dart';
import 'package:frontend/services/dashboard_service.dart';

void main() {
  _districtStatShapeTests();

  group('model agreement', () {
    test('is null with no reviewed cases rather than a misleading 100%', () {
      const a = ModelAgreement(
        confirmed: 0,
        corrected: 0,
        missesByDisease: {},
      );
      expect(a.agreementRate, isNull);
      expect(a.total, 0);
    });

    test('computes the share of expert verdicts that backed the model', () {
      const a = ModelAgreement(
        confirmed: 42,
        corrected: 8,
        missesByDisease: {'potato_late_blight': 8},
      );
      expect(a.agreementRate, closeTo(0.84, 0.001));
      expect(a.total, 50);
    });

    test('flags a sample too small to mean anything', () {
      const small = ModelAgreement(
        confirmed: 4,
        corrected: 1,
        missesByDisease: {},
      );
      const big = ModelAgreement(
        confirmed: 90,
        corrected: 20,
        missesByDisease: {},
      );
      expect(small.isStatisticallyMeaningful, isFalse);
      expect(big.isStatisticallyMeaningful, isTrue);
    });

    test('ranks the classes the model gets wrong most often', () {
      const a = ModelAgreement(
        confirmed: 10,
        corrected: 12,
        missesByDisease: {
          'potato_early_blight': 7,
          'corn_rust': 2,
          'wheat_brown_rust': 3,
        },
      );
      final worst = a.worstClasses;
      expect(worst.first.info.disease, 'Early Blight');
      expect(worst.first.misses, 7);
      for (var i = 1; i < worst.length; i++) {
        expect(worst[i - 1].misses, greaterThanOrEqualTo(worst[i].misses));
      }
    });

    test('ignores labels that no longer exist in the knowledge base', () {
      // A retrain could retire a class; the dashboard must not crash on it.
      const a = ModelAgreement(
        confirmed: 5,
        corrected: 3,
        missesByDisease: {'corn_rust': 2, 'some_retired_class': 1},
      );
      expect(a.worstClasses.length, 1);
      expect(a.worstClasses.first.info.disease, 'Rust');
    });
  });

  group('disease keys are stable across the loop', () {
    test('every KB entry produces the key the pipeline expects', () {
      // export_feedback.py builds the same slug in Python. If these ever
      // diverge, exported folders stop matching the app's labels and the
      // retrain silently learns the wrong mapping.
      final lateBlight = DiseaseKb.lookup('Potato', 'Late Blight')!;
      expect(lateBlight.key, 'potato_late_blight');

      final greySpot = DiseaseKb.lookup('CORN', 'Gray Spot')!;
      expect(greySpot.key, 'corn_gray_spot');

      final redRot = DiseaseKb.lookup('SugarCane', 'RedRot')!;
      expect(redRot.key, 'sugarcane_redrot');
    });

    test('keys are unique across the whole knowledge base', () {
      final keys = DiseaseKb.all.map((d) => d.key).toList();
      expect(
        keys.toSet().length,
        keys.length,
        reason: 'a duplicate key would merge two diseases in training data',
      );
    });

    test('keys contain no characters that break a folder name', () {
      final safe = RegExp(r'^[a-z0-9_]+$');
      for (final d in DiseaseKb.all) {
        expect(
          safe.hasMatch(d.key),
          isTrue,
          reason: '${d.key} is not safe as a directory name',
        );
      }
    });
  });

  group('intervention tracking', () {
    Intervention make({
      InterventionStatus status = InterventionStatus.acknowledged,
      int daysAgo = 0,
      int caseCountAtUpdate = 5,
    }) => Intervention(
      id: 'x',
      district: 'Kolhapur',
      diseaseKey: 'sugarcane_redrot',
      status: status,
      caseCountAtUpdate: caseCountAtUpdate,
      createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
      updatedAt: DateTime.now().subtract(Duration(days: daysAgo)),
    );

    test('composite id keeps one record per district and disease', () {
      expect(
        Intervention.idFor('Kolhapur', 'sugarcane_redrot'),
        'kolhapur__sugarcane_redrot',
      );
      // District names with spaces must still produce a valid document id.
      expect(
        Intervention.idFor('Chhatrapati Sambhajinagar', 'corn_rust'),
        'chhatrapati_sambhajinagar__corn_rust',
      );
    });

    test('open statuses are the ones still demanding attention', () {
      expect(InterventionStatus.unreviewed.isOpen, isTrue);
      expect(InterventionStatus.acknowledged.isOpen, isTrue);
      expect(InterventionStatus.dispatched.isOpen, isTrue);
      expect(InterventionStatus.resolved.isOpen, isFalse);
      expect(InterventionStatus.dismissed.isOpen, isFalse);
    });

    test('an acknowledged cluster left a week goes stalled', () {
      expect(make(daysAgo: 2).isStalled, isFalse);
      expect(make(daysAgo: 9).isStalled, isTrue);
    });

    test('a dispatched cluster is not stalled - someone is on it', () {
      expect(
        make(status: InterventionStatus.dispatched, daysAgo: 30).isStalled,
        isFalse,
      );
    });
  });

  group('outbreak cluster prioritisation', () {
    OutbreakCluster cluster({
      required String diseaseKey,
      required int cases,
      Intervention? intervention,
    }) {
      final info = DiseaseKb.all.firstWhere((d) => d.key == diseaseKey);
      return OutbreakCluster(
        district: 'Pune',
        disease: info,
        cases: cases,
        intervention: intervention,
      );
    }

    test('a notifiable disease outranks a larger non-notifiable cluster', () {
      final redRot = cluster(diseaseKey: 'sugarcane_redrot', cases: 5);
      final rust = cluster(diseaseKey: 'corn_rust', cases: 40);
      expect(
        redRot.priority,
        greaterThan(rust.priority),
        reason: 'red rot spreads fast enough that 5 cases beat 40 of rust',
      );
    });

    test('resolved clusters sink below everything open', () {
      final resolved = cluster(
        diseaseKey: 'sugarcane_redrot',
        cases: 50,
        intervention: Intervention(
          id: 'x',
          district: 'Pune',
          diseaseKey: 'sugarcane_redrot',
          status: InterventionStatus.resolved,
          caseCountAtUpdate: 50,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final open = cluster(diseaseKey: 'corn_rust', cases: 1);
      expect(resolved.priority, lessThan(open.priority));
      expect(resolved.isOpen, isFalse);
    });

    test('tracks cases arriving after an officer acknowledged it', () {
      final c = cluster(
        diseaseKey: 'corn_rust',
        cases: 18,
        intervention: Intervention(
          id: 'x',
          district: 'Pune',
          diseaseKey: 'corn_rust',
          status: InterventionStatus.acknowledged,
          caseCountAtUpdate: 6,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      expect(c.casesSinceUpdate, 12);
    });

    test('never reports negative growth if counts are re-baselined', () {
      final c = cluster(
        diseaseKey: 'corn_rust',
        cases: 3,
        intervention: Intervention(
          id: 'x',
          district: 'Pune',
          diseaseKey: 'corn_rust',
          status: InterventionStatus.acknowledged,
          caseCountAtUpdate: 10,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      expect(c.casesSinceUpdate, 0);
    });
  });
}

/// Guards the shape of the district aggregate document.
///
/// Firestore treats a dotted key as a nested path in update() but as a literal
/// field name in set(). Writing 'byDisease.corn_rust' through set() therefore
/// produces a field called exactly that, leaving byDisease empty and silently
/// zeroing the map and the dashboard. These assert the nested-map contract
/// that FirestoreService._bumpDistrictStat and DistrictStat.fromDoc share.
void _districtStatShapeTests() {
  group('district aggregate shape', () {
    test('byDisease and bySpecies serialise as nested maps', () {
      final stat = DistrictStat(
        district: 'Kolhapur',
        region: 'Western Maharashtra',
        lat: 16.7,
        lng: 74.24,
        totalScans: 10,
        diseaseCases: 4,
        byDisease: const {'sugarcane_redrot': 4},
        bySpecies: const {'SugarCane': 4},
        lastReportedAt: DateTime.now(),
      );

      final map = stat.toMap();
      expect(map['byDisease'], isA<Map<String, int>>());
      expect(map['bySpecies'], isA<Map<String, int>>());

      // No key may contain a dot, or it would be read back as a nested path.
      for (final key in (map['byDisease'] as Map).keys) {
        expect(key.toString().contains('.'), isFalse);
      }
    });

    test('a district with no disease keys still reports a zero score', () {
      final stat = DistrictStat(
        district: 'Pune',
        region: 'Western Maharashtra',
        lat: 18.5,
        lng: 73.8,
        totalScans: 12,
        diseaseCases: 0,
        byDisease: const {},
        bySpecies: const {},
        lastReportedAt: DateTime.now(),
      );
      expect(stat.hotspotScore, 0);
      expect(stat.dominantDisease, isNull);
      expect(stat.infectionRate, 0);
    });
  });
}
