import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../data/disease_kb.dart';
import '../data/maharashtra_districts.dart';
import '../model/detection_result.dart';
import '../model/diagnosis_history_model.dart';
import '../model/scan_record.dart';
import '../model/user_model.dart';
import 'firestore_service.dart';
import 'history_service.dart';
import 'location_service.dart';

/// What happened to a scan after inference.
class ScanReport {
  /// Firestore document id, null when the scan stayed local (not signed in,
  /// or the cloud write could not even be queued).
  final String? cloudId;

  /// District the scan was filed under, null when no location was available.
  final String? district;

  /// True when the scan was excluded from public aggregates because the fix
  /// landed outside Maharashtra.
  final bool excludedFromMap;

  const ScanReport({
    this.cloudId,
    this.district,
    this.excludedFromMap = false,
  });
}

/// Single place where a completed detection is persisted.
///
/// Both the camera and the gallery path go through here, so local history,
/// the cloud record and the district aggregate can never drift apart - they
/// were previously written by two copies of the same inline code.
class ScanReportingService {
  ScanReportingService._();
  static final ScanReportingService instance = ScanReportingService._();

  /// Persist a detection locally and, when possible, to the cloud.
  ///
  /// Never throws and never blocks on the network. A farmer with no signal
  /// must still get their result screen instantly; the cloud write queues on
  /// disk and flushes when connectivity returns.
  Future<ScanReport> report(DetectionResult result) async {
    await _saveLocal(result);

    try {
      return await _saveCloud(result);
    } catch (e) {
      // Local history already succeeded, so the farmer loses nothing here.
      debugPrint('ScanReportingService: cloud report skipped: $e');
      return const ScanReport();
    }
  }

  Future<void> _saveLocal(DetectionResult r) async {
    try {
      await HistoryService.saveHistory(
        history: DiagnosisHistory(
          epochTime: r.time.millisecondsSinceEpoch,
          plantName: r.species,
          imagePath: r.imagePath,
          // Now the disease's threat level rather than a confidence band.
          result: r.severity,
          diagnosis: r.disease,
          confidence: r.confidence,
        ),
      );
    } catch (e) {
      debugPrint('ScanReportingService: local history failed: $e');
    }
  }

  Future<ScanReport> _saveCloud(DetectionResult r) async {
    final uid = FirestoreService.instance.currentUid;
    if (uid == null) return const ScanReport();

    final loc = await LocationService.instance.resolve();
    if (loc == null) {
      // Without a location the scan cannot be placed on the map. We keep it
      // as a personal record rather than filing it under a guessed district,
      // which would quietly corrupt the state-wide picture.
      debugPrint('ScanReportingService: no location, scan stays local');
      return const ScanReport();
    }

    // A fix outside Maharashtra is real data but does not belong in a
    // Maharashtra outbreak map.
    final inState = MaharashtraDistricts.isWithinState(loc.lat, loc.lng);

    final info = DiseaseKb.resolve(r.species, r.disease);
    final farmerName = _localName();

    final record = ScanRecord(
      id: '',
      uid: uid,
      farmerName: farmerName,
      species: r.species,
      disease: r.disease,
      diseaseKey: info.key,
      confidence: r.confidence,
      threatLevel: info.threat.label,
      modelVersion: r.modelVersion,
      district: loc.district.name,
      region: loc.district.region.label,
      // Coarsened before it ever leaves the device.
      lat: loc.publicLat,
      lng: loc.publicLng,
      localImagePath: r.imagePath,
      contributesToMap: inState,
      createdAt: r.time,
    );

    final id = await FirestoreService.instance.saveScan(record);

    return ScanReport(
      cloudId: id,
      district: loc.district.name,
      excludedFromMap: !inState,
    );
  }

  String _localName() {
    try {
      final box = Hive.box<UserModel>('userBox');
      return box.get('currentUser')?.name ?? '';
    } catch (_) {
      return '';
    }
  }
}
