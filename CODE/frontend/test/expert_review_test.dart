import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/config/app_config.dart';
import 'package:frontend/model/district_stat.dart';
import 'package:frontend/model/scan_record.dart';
import 'package:frontend/services/expert_service.dart';

ScanRecord buildScan({
  ReviewStatus status = ReviewStatus.none,
  DateTime? requestedAt,
  String disease = 'Late Blight',
  String species = 'Potato',
  String? expertDisease,
  double confidence = 88,
}) {
  return ScanRecord(
    id: 's1',
    uid: 'u1',
    farmerName: 'Test',
    species: species,
    disease: disease,
    diseaseKey: '${species}_$disease'.toLowerCase().replaceAll(' ', '_'),
    confidence: confidence,
    threatLevel: 'Critical',
    modelVersion: 'bundled-v1',
    district: 'Pune',
    region: 'Western Maharashtra',
    lat: 18.52,
    lng: 73.86,
    reviewStatus: status,
    reviewRequestedAt: requestedAt,
    expertDisease: expertDisease,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('SLA countdown', () {
    test('reports hours remaining inside the window', () {
      final scan = buildScan(
        status: ReviewStatus.pending,
        requestedAt: DateTime.now().subtract(const Duration(hours: 4)),
      );
      final left = scan.slaHoursRemaining(AppConfig.expertSlaWindow)!;
      expect(left, closeTo(20, 0.1));
    });

    test('goes negative once the window is breached', () {
      final scan = buildScan(
        status: ReviewStatus.pending,
        requestedAt: DateTime.now().subtract(const Duration(hours: 30)),
      );
      expect(scan.slaHoursRemaining(AppConfig.expertSlaWindow), lessThan(0));
    });

    test('is null for a case that was never submitted', () {
      expect(buildScan().slaHoursRemaining(AppConfig.expertSlaWindow), isNull);
    });

    test('is null once a verdict has landed - the clock has stopped', () {
      final scan = buildScan(
        status: ReviewStatus.confirmed,
        requestedAt: DateTime.now().subtract(const Duration(hours: 40)),
      );
      expect(scan.slaHoursRemaining(AppConfig.expertSlaWindow), isNull);
    });
  });

  group('effective diagnosis', () {
    test('falls back to the AI label when no expert has ruled', () {
      expect(buildScan().effectiveDisease, 'Late Blight');
      expect(buildScan().isVerified, isFalse);
    });

    test('a correction overrides the AI label everywhere downstream', () {
      final scan = buildScan(
        status: ReviewStatus.corrected,
        expertDisease: 'Early Blight',
      );
      expect(scan.effectiveDisease, 'Early Blight');
      expect(scan.isCorrection, isTrue);
      expect(scan.isVerified, isTrue);
    });

    test('a confirmation counts as verified but is not a correction', () {
      final scan = buildScan(
        status: ReviewStatus.confirmed,
        expertDisease: 'Late Blight',
      );
      expect(scan.isVerified, isTrue);
      expect(scan.isCorrection, isFalse);
    });

    test('an expired case is neither verified nor a correction', () {
      final scan = buildScan(status: ReviewStatus.expired);
      expect(scan.isVerified, isFalse);
      expect(scan.isCorrection, isFalse);
    });
  });

  group('queue health', () {
    test('answer rate ignores cases still pending', () {
      const h = QueueHealth(
        pending: 50,
        resolved: 8,
        expired: 2,
        verifiedExperts: 3,
      );
      // 8 answered out of 10 closed - the 50 still open are not failures yet.
      expect(h.answerRate, closeTo(0.8, 0.001));
    });

    test('a fresh deployment with no closed cases is not counted as failing', () {
      const h = QueueHealth(
        pending: 4,
        resolved: 0,
        expired: 0,
        verifiedExperts: 2,
      );
      expect(h.answerRate, 1.0);
    });

    test('no verified experts is always under-staffed', () {
      const h = QueueHealth(
        pending: 0,
        resolved: 0,
        expired: 0,
        verifiedExperts: 0,
      );
      expect(
        h.isUnderStaffed,
        isTrue,
        reason: 'an expert layer with nobody in it cannot answer anything',
      );
    });

    test('backlog beyond ten cases per expert flags under-staffing', () {
      const ok = QueueHealth(
        pending: 15,
        resolved: 0,
        expired: 0,
        verifiedExperts: 2,
      );
      const swamped = QueueHealth(
        pending: 25,
        resolved: 0,
        expired: 0,
        verifiedExperts: 2,
      );
      expect(ok.isUnderStaffed, isFalse);
      expect(swamped.isUnderStaffed, isTrue);
    });
  });

  group('district hotspot scoring', () {
    DistrictStat stat({
      int total = 40,
      int cases = 10,
      Map<String, int>? byDisease,
      int daysAgo = 1,
    }) => DistrictStat(
      district: 'Kolhapur',
      region: 'Western Maharashtra',
      lat: 16.7,
      lng: 74.24,
      totalScans: total,
      diseaseCases: cases,
      byDisease: byDisease ?? {'corn_rust': cases},
      bySpecies: const {'CORN': 10},
      lastReportedAt: DateTime.now().subtract(Duration(days: daysAgo)),
    );

    test('a district with no cases scores zero', () {
      expect(stat(cases: 0, byDisease: {}).hotspotScore, 0);
    });

    test('prevalence matters, not just raw case count', () {
      // Same number of cases, very different share of scans.
      final concentrated = stat(total: 12, cases: 10);
      final diluted = stat(total: 300, cases: 10);
      expect(
        concentrated.hotspotScore,
        greaterThan(diluted.hotspotScore),
        reason: 'otherwise the map just shows where the most farmers are',
      );
    });

    test('stale reports decay toward zero', () {
      final fresh = stat(daysAgo: 0);
      final old = stat(daysAgo: 20);
      expect(old.hotspotScore, lessThan(fresh.hotspotScore));
      expect(stat(daysAgo: 30).hotspotScore, 0);
    });

    test('a notifiable disease floors the score even at low volume', () {
      // One case of red rot, which spreads fast enough to warrant attention
      // regardless of how few reports there are.
      final s = stat(total: 60, cases: 1, byDisease: {'sugarcane_redrot': 1});
      expect(s.hasNotifiableDisease, isTrue);
      expect(s.hotspotScore, greaterThanOrEqualTo(45));
    });

    test('a non-notifiable disease at the same volume stays low', () {
      final s = stat(total: 60, cases: 1, byDisease: {'corn_rust': 1});
      expect(s.hasNotifiableDisease, isFalse);
      expect(s.hotspotScore, lessThan(45));
    });

    test('activity window separates quiet from stale', () {
      expect(stat(daysAgo: 3).isActive, isTrue);
      expect(stat(daysAgo: 40).isActive, isFalse);
    });
  });
}
