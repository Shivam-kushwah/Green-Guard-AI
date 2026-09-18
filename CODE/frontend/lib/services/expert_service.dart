import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../data/disease_kb.dart';
import '../model/app_user.dart';
import '../model/scan_record.dart';
import 'firestore_service.dart';

/// Why a review action could not be completed.
enum ReviewFailure {
  notSignedIn,
  notVerified,
  alreadyClaimed,
  alreadyResolved,
  noImage,
  notFound,
}

class ReviewException implements Exception {
  final ReviewFailure kind;
  final String message;
  const ReviewException(this.kind, this.message);

  @override
  String toString() => message;
}

/// The expert validation workflow.
///
/// A farmer sends a case; a verified agronomist claims it, rules on it, and
/// the verdict flows back to the farmer and into the training set.
///
/// On what the 24-hour window actually is: it is a tracked target, not a
/// guarantee. Software can queue a case, show a countdown, surface breaches
/// and mark a case expired - it cannot make a human answer. The feature is
/// only as real as the agronomists actually recruited to staff it, and
/// [queueHealth] exists so that is visible rather than assumed.
class ExpertService {
  ExpertService._();
  static final ExpertService instance = ExpertService._();

  final FirestoreService _fs = FirestoreService.instance;

  // ------------------------------------------------------------- farmer

  /// Send a scan to the expert queue.
  ///
  /// The image is required: an agronomist cannot rule on a case they cannot
  /// see. It is uploaded as compressed base64 inside the scan document, which
  /// is what keeps this on the free Firestore tier with no Cloud Storage.
  Future<void> submitForReview({
    required String scanId,
    required String imageBase64,
    String? farmerNote,
  }) async {
    final uid = _fs.currentUid;
    if (uid == null) {
      throw const ReviewException(
        ReviewFailure.notSignedIn,
        'Sign in to send a case to an agronomist.',
      );
    }
    if (imageBase64.isEmpty) {
      throw const ReviewException(
        ReviewFailure.noImage,
        'The photo could not be prepared for upload.',
      );
    }

    await _fs.scans.doc(scanId).update({
      'imageBase64': imageBase64,
      'reviewStatus': ReviewStatus.pending.wire,
      'reviewRequestedAt': Timestamp.now(),
      if (farmerNote != null && farmerNote.isNotEmpty) 'farmerNote': farmerNote,
    });
  }

  /// The farmer's own cases, newest first. Drives the in-app notification
  /// badge - with no Cloud Functions there is no FCM push, so a live Firestore
  /// listener is how a farmer learns their verdict arrived.
  Stream<List<ScanRecord>> watchMyReviews(String uid) => _fs.scans
      .where('uid', isEqualTo: uid)
      .where('reviewStatus', whereIn: [
        ReviewStatus.pending.wire,
        ReviewStatus.confirmed.wire,
        ReviewStatus.corrected.wire,
        ReviewStatus.expired.wire,
      ])
      .orderBy('reviewRequestedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((q) => q.docs.map(ScanRecord.fromDoc).toList());

  /// Verdicts the farmer has not opened yet.
  Stream<int> watchUnreadVerdicts(String uid) => watchMyReviews(uid).map(
    (list) => list.where((s) => s.reviewStatus.isResolved).length,
  );

  // --------------------------------------------------------- agronomist

  /// Cases waiting for a verdict, oldest first so nothing starves.
  ///
  /// Oldest-first is deliberate: newest-first would let a steady trickle of
  /// new cases permanently bury the ones closest to breaching the window.
  Stream<List<ScanRecord>> watchQueue({int limit = 50}) => _fs.scans
      .where('reviewStatus', isEqualTo: ReviewStatus.pending.wire)
      .orderBy('reviewRequestedAt')
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(ScanRecord.fromDoc).toList());

  /// Cases this agronomist has already ruled on.
  Stream<List<ScanRecord>> watchMyVerdicts(String expertUid, {int limit = 50}) =>
      _fs.scans
          .where('expertUid', isEqualTo: expertUid)
          .orderBy('reviewedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((q) => q.docs.map(ScanRecord.fromDoc).toList());

  /// Record a verdict.
  ///
  /// Runs in a transaction so two agronomists opening the same case cannot
  /// both file a ruling - the second one is told it is already answered
  /// rather than silently overwriting the first.
  Future<void> submitVerdict({
    required AppUser expert,
    required String scanId,
    required bool agreesWithAi,
    String? correctedSpecies,
    String? correctedDisease,
    required String note,
  }) async {
    if (!expert.canReview) {
      throw const ReviewException(
        ReviewFailure.notVerified,
        'Only a verified agronomist can rule on cases.',
      );
    }

    final ref = _fs.scans.doc(scanId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const ReviewException(
          ReviewFailure.notFound,
          'This case no longer exists.',
        );
      }

      final scan = ScanRecord.fromDoc(snap);
      if (scan.reviewStatus.isResolved) {
        throw const ReviewException(
          ReviewFailure.alreadyResolved,
          'Another agronomist has already answered this case.',
        );
      }

      final species = agreesWithAi
          ? scan.species
          : (correctedSpecies ?? scan.species);
      final disease = agreesWithAi
          ? scan.disease
          : (correctedDisease ?? scan.disease);

      tx.update(ref, {
        'reviewStatus': agreesWithAi
            ? ReviewStatus.confirmed.wire
            : ReviewStatus.corrected.wire,
        'expertUid': expert.uid,
        'expertName': expert.name,
        'expertQualification': expert.qualification,
        'expertSpecies': species,
        'expertDisease': disease,
        'expertNote': note,
        'reviewedAt': Timestamp.now(),
      });
    });

    // Fire-and-forget bookkeeping. A failure here must not roll back a
    // verdict the farmer is already waiting on.
    unawaited(
      _fs.users.doc(expert.uid).update({
        'reviewsCompleted': FieldValue.increment(1),
      }),
    );

    unawaited(
      _recordTrainingSample(
        scanId: scanId,
        expert: expert,
        agreesWithAi: agreesWithAi,
        correctedSpecies: correctedSpecies,
        correctedDisease: correctedDisease,
      ),
    );
  }

  /// Captures the expert's ruling as a labelled training sample.
  ///
  /// This is the hand-off point into the learning loop: every verdict, whether
  /// it confirms or corrects the model, is ground truth about a real Indian
  /// field photo. Corrections are the valuable ones, but confirmations matter
  /// too - without them there is no way to measure precision, only recall of
  /// mistakes.
  Future<void> _recordTrainingSample({
    required String scanId,
    required AppUser expert,
    required bool agreesWithAi,
    String? correctedSpecies,
    String? correctedDisease,
  }) async {
    final snap = await _fs.scans.doc(scanId).get();
    if (!snap.exists) return;
    final scan = ScanRecord.fromDoc(snap);

    await _fs.feedback.doc(scanId).set({
      'scanId': scanId,
      'farmerUid': scan.uid,
      'imageBase64': scan.imageBase64,

      // What the model predicted, and which model predicted it.
      'aiSpecies': scan.species,
      'aiDisease': scan.disease,
      'aiLabel': scan.diseaseKey,
      'aiConfidence': scan.confidence,
      'modelVersion': scan.modelVersion,

      // Ground truth from the expert.
      'trueSpecies': agreesWithAi ? scan.species : correctedSpecies,
      'trueDisease': agreesWithAi ? scan.disease : correctedDisease,
      'trueLabel': agreesWithAi
          ? scan.diseaseKey
          : DiseaseKb.resolve(
              correctedSpecies ?? scan.species,
              correctedDisease ?? scan.disease,
            ).key,
      'isCorrection': !agreesWithAi,

      // Provenance, so a future retrain can weight or filter samples.
      'expertUid': expert.uid,
      'expertName': expert.name,
      'expertInstitution': expert.institution,
      'district': scan.district,
      'region': scan.region,
      'createdAt': Timestamp.now(),

      // Set once a sample has been pulled into a training run, so the same
      // image is not silently counted twice across retrains.
      'exportedAt': null,
      'usedInVersion': null,
    });
  }

  // -------------------------------------------------------------- SLA

  /// Mark cases that blew through the window.
  ///
  /// With no Cloud Scheduler on the free tier there is no cron to do this
  /// server-side, so it runs opportunistically when an agronomist or officer
  /// opens the queue. The consequence worth knowing: a case only flips to
  /// expired once someone looks, so treat the timestamp rather than the status
  /// as authoritative when auditing.
  Future<int> expireOverdueCases() async {
    final cutoff = DateTime.now().subtract(AppConfig.expertSlaWindow);

    final overdue = await _fs.scans
        .where('reviewStatus', isEqualTo: ReviewStatus.pending.wire)
        .where('reviewRequestedAt', isLessThan: Timestamp.fromDate(cutoff))
        .limit(100)
        .get();

    if (overdue.docs.isEmpty) return 0;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in overdue.docs) {
      batch.update(doc.reference, {
        'reviewStatus': ReviewStatus.expired.wire,
      });
    }
    await batch.commit();
    debugPrint('ExpertService: expired ${overdue.docs.length} case(s)');
    return overdue.docs.length;
  }

  /// Whether the expert network is actually keeping up.
  ///
  /// Exists so the 24-hour promise is measured rather than assumed. If this
  /// shows a growing backlog and a falling answer rate, the answer is to
  /// recruit more agronomists - no amount of code will fix it.
  Future<QueueHealth> queueHealth() async {
    final pending = await _fs.scans
        .where('reviewStatus', isEqualTo: ReviewStatus.pending.wire)
        .count()
        .get();

    final resolved = await _fs.scans
        .where('reviewStatus', whereIn: [
          ReviewStatus.confirmed.wire,
          ReviewStatus.corrected.wire,
        ])
        .count()
        .get();

    final expired = await _fs.scans
        .where('reviewStatus', isEqualTo: ReviewStatus.expired.wire)
        .count()
        .get();

    final verifiedExperts = await _fs.users
        .where('role', isEqualTo: UserRole.agronomist.wire)
        .where('verified', isEqualTo: true)
        .count()
        .get();

    return QueueHealth(
      pending: pending.count ?? 0,
      resolved: resolved.count ?? 0,
      expired: expired.count ?? 0,
      verifiedExperts: verifiedExperts.count ?? 0,
    );
  }
}

/// Operational health of the expert layer.
class QueueHealth {
  final int pending;
  final int resolved;
  final int expired;
  final int verifiedExperts;

  const QueueHealth({
    required this.pending,
    required this.resolved,
    required this.expired,
    required this.verifiedExperts,
  });

  int get totalRequests => pending + resolved + expired;

  /// Share of closed cases that were answered rather than timing out.
  double get answerRate {
    final closed = resolved + expired;
    return closed == 0 ? 1.0 : resolved / closed;
  }

  /// The blunt version, for the dashboard.
  bool get isUnderStaffed =>
      verifiedExperts == 0 || (pending > verifiedExperts * 10);
}
