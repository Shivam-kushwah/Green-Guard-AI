import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tf_service.dart';

/// A model release published by the retraining pipeline.
class ModelRelease {
  final String version;

  /// Direct download URL for the .tflite file.
  final String url;

  /// Bytes, so the UI can warn before pulling a large file over mobile data.
  final int sizeBytes;

  /// Accuracy on the held-out validation split at release time.
  final double validationAccuracy;

  /// Agreement with expert verdicts on real field photos, if measured. This is
  /// the number that actually matters and it is usually lower than the one
  /// above - a model can ace a curated test split and still struggle on a
  /// phone photo taken at dusk.
  final double? fieldAgreement;

  /// How many expert-labelled samples fed this release.
  final int expertSamplesUsed;

  final int numClasses;
  final DateTime releasedAt;
  final String? notes;

  const ModelRelease({
    required this.version,
    required this.url,
    required this.sizeBytes,
    required this.validationAccuracy,
    required this.expertSamplesUsed,
    required this.numClasses,
    required this.releasedAt,
    this.fieldAgreement,
    this.notes,
  });

  double get sizeMb => sizeBytes / (1024 * 1024);

  factory ModelRelease.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ModelRelease(
      version: (d['version'] as String?) ?? doc.id,
      url: (d['url'] as String?) ?? '',
      sizeBytes: (d['sizeBytes'] as num?)?.toInt() ?? 0,
      validationAccuracy:
          (d['validationAccuracy'] as num?)?.toDouble() ?? 0,
      fieldAgreement: (d['fieldAgreement'] as num?)?.toDouble(),
      expertSamplesUsed: (d['expertSamplesUsed'] as num?)?.toInt() ?? 0,
      numClasses: (d['numClasses'] as num?)?.toInt() ?? 0,
      releasedAt:
          (d['releasedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: d['notes'] as String?,
    );
  }
}

/// Ships improved models to phones without an app-store release.
///
/// This is the delivery half of the learning loop. The learning half happens
/// offline in the Python pipeline (see CODE/Model-Training/retrain.py); this
/// class only fetches the result and swaps it in.
///
/// Worth being clear about what this does and does not mean: the model does
/// not learn on the device and does not improve by itself. Expert verdicts
/// accumulate, a human runs a retrain, the gate in that script decides whether
/// the candidate is actually better, and only then does a release appear here.
class ModelUpdateService {
  ModelUpdateService._();
  static final ModelUpdateService instance = ModelUpdateService._();

  static const _kActiveVersion = 'gg_active_model_version';
  static const _kActivePath = 'gg_active_model_path';
  static const _kLastCheck = 'gg_model_last_check';

  /// Version compiled into the APK, used when nothing has been downloaded.
  static const String bundledVersion = 'bundled-v1';

  CollectionReference<Map<String, dynamic>> get _releases =>
      FirebaseFirestore.instance.collection('model_releases');

  /// Latest published release, or null when none exists.
  Future<ModelRelease?> latestRelease() async {
    try {
      final q = await _releases
          .orderBy('releasedAt', descending: true)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return null;
      return ModelRelease.fromDoc(q.docs.first);
    } catch (e) {
      debugPrint('ModelUpdateService: release lookup failed: $e');
      return null;
    }
  }

  Future<String> activeVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveVersion) ?? bundledVersion;
  }

  /// Load a previously downloaded model, if one is present and still valid.
  ///
  /// Called at startup before the bundled asset, so a phone that already
  /// updated keeps using the newer weights across restarts.
  Future<bool> loadActiveModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_kActivePath);
      final version = prefs.getString(_kActiveVersion);
      if (path == null || version == null) return false;

      final file = File(path);
      if (!await file.exists()) {
        // Cache was cleared by the OS - fall back to the bundled model rather
        // than leaving the app with no interpreter at all.
        await prefs.remove(_kActivePath);
        await prefs.remove(_kActiveVersion);
        return false;
      }

      await TfService.instance.loadModelFromFile(file, version);
      return true;
    } catch (e) {
      debugPrint('ModelUpdateService: could not load active model: $e');
      return false;
    }
  }

  /// Is there something newer than what is running?
  Future<ModelRelease?> checkForUpdate() async {
    final release = await latestRelease();
    if (release == null || release.url.isEmpty) return null;

    final current = await activeVersion();
    if (release.version == current) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);

    return release;
  }

  /// Download and activate a release.
  ///
  /// The new file is written under a version-stamped name and only becomes
  /// active after it loads successfully, so a truncated download cannot leave
  /// the app unable to run inference.
  Future<bool> downloadAndActivate(
    ModelRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final target = File('${dir.path}/model_${release.version}.tflite');

      final request = http.Request('GET', Uri.parse(release.url));
      final response = await request.send();

      if (response.statusCode != 200) {
        debugPrint(
          'ModelUpdateService: download failed ${response.statusCode}',
        );
        return false;
      }

      final total = response.contentLength ?? release.sizeBytes;
      final sink = target.openWrite();
      var received = 0;

      await response.stream.forEach((chunk) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call(received / total);
      });
      await sink.close();

      // Verify by actually loading it. A model that downloads but will not
      // load must not be promoted.
      try {
        await TfService.instance.loadModelFromFile(target, release.version);
      } catch (e) {
        debugPrint('ModelUpdateService: new model failed to load: $e');
        await target.delete();
        // Restore whatever was working before.
        await loadActiveModel();
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final previousPath = prefs.getString(_kActivePath);

      await prefs.setString(_kActivePath, target.path);
      await prefs.setString(_kActiveVersion, release.version);

      // Clean up the superseded file once the new one is committed.
      if (previousPath != null && previousPath != target.path) {
        final old = File(previousPath);
        if (await old.exists()) {
          await old.delete().catchError((_) => old);
        }
      }

      debugPrint('ModelUpdateService: activated ${release.version}');
      return true;
    } catch (e) {
      debugPrint('ModelUpdateService: update failed: $e');
      return false;
    }
  }

  /// Drop back to the model compiled into the app.
  Future<void> revertToBundled() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kActivePath);
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await prefs.remove(_kActivePath);
    await prefs.remove(_kActiveVersion);
    TfService.instance.dispose();
    await TfService.instance.loadModel();
  }

  /// Training samples that have not yet been pulled into a retrain.
  ///
  /// Read by the export script; surfaced in the app so the team can see the
  /// loop filling up rather than guessing.
  Future<int> pendingSampleCount() async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('model_feedback')
          .where('exportedAt', isNull: true)
          .count()
          .get();
      return q.count ?? 0;
    } catch (e) {
      debugPrint('ModelUpdateService: sample count failed: $e');
      return 0;
    }
  }

  /// Publish a release record. Called by the pipeline operator, not the app.
  Future<void> publishRelease({
    required String version,
    required String url,
    required int sizeBytes,
    required double validationAccuracy,
    required int expertSamplesUsed,
    required int numClasses,
    double? fieldAgreement,
    String? notes,
  }) async {
    await _releases.doc(version).set({
      'version': version,
      'url': url,
      'sizeBytes': sizeBytes,
      'validationAccuracy': validationAccuracy,
      'fieldAgreement': fieldAgreement,
      'expertSamplesUsed': expertSamplesUsed,
      'numClasses': numClasses,
      'releasedAt': Timestamp.now(),
      'notes': notes,
    });
  }

  /// Convenience for the export script's counterpart in Dart, and for tests:
  /// encode a sample the way the pipeline expects to read it.
  static Map<String, dynamic> decodeSampleImage(String base64Image) => {
    'bytes': base64Decode(base64Image).length,
  };
}
