import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../model/app_user.dart';
import '../model/scan_record.dart';

/// The cloud data layer.
///
/// Everything the app writes to Firestore goes through here so that collection
/// names, aggregate maintenance and the offline behaviour live in one place.
///
/// Offline notes: Firestore's local persistence is enabled at startup, so
/// reads resolve from cache and writes queue on disk when there is no signal.
/// That matters more than usual here - rural connectivity is the normal case,
/// not the edge case. Any code awaiting a write must therefore NOT block the
/// UI on the server round trip; see [saveScan] for how that is handled.
class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collection names in one place - typo-proofing the rest of the app.
  static const String cUsers = 'users';
  static const String cScans = 'scans';
  static const String cDistrictStats = 'district_stats';
  static const String cFeedback = 'model_feedback';

  CollectionReference<Map<String, dynamic>> get users => _db.collection(cUsers);
  CollectionReference<Map<String, dynamic>> get scans => _db.collection(cScans);
  CollectionReference<Map<String, dynamic>> get districtStats =>
      _db.collection(cDistrictStats);
  CollectionReference<Map<String, dynamic>> get feedback =>
      _db.collection(cFeedback);

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Turn on disk persistence. Called once, before any other Firestore use.
  static Future<void> configureOffline() async {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // ---------------------------------------------------------------- users

  /// Creates the cloud profile on first sign-in, or refreshes the mutable
  /// fields on later ones. Never downgrades a role that an admin has set -
  /// that is why role is only written when the document does not yet exist.
  Future<AppUser> ensureUserProfile({
    required String uid,
    required String name,
    required String email,
    required String photoUrl,
  }) async {
    final ref = users.doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      final fresh = AppUser(
        uid: uid,
        name: name,
        email: email,
        photoUrl: photoUrl,
        role: UserRole.farmer,
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      );
      await ref.set(fresh.toMap());
      return fresh;
    }

    await ref.update({
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'lastActiveAt': Timestamp.now(),
    });
    return AppUser.fromDoc(await ref.get());
  }

  Future<AppUser?> getUser(String uid) async {
    final snap = await users.doc(uid).get();
    return snap.exists ? AppUser.fromDoc(snap) : null;
  }

  /// Live profile stream - the role can change under the user (an admin
  /// verifying an agronomist) and the UI should follow without a restart.
  Stream<AppUser?> watchUser(String uid) => users
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromDoc(s) : null);

  Future<void> updateUserFields(String uid, Map<String, dynamic> fields) =>
      users.doc(uid).update(fields);

  // ---------------------------------------------------------------- scans

  /// Persists a scan and bumps the district aggregate.
  ///
  /// Returns as soon as the write is queued locally rather than waiting for
  /// the server, so a farmer on a weak signal still gets an instant result
  /// screen. Firestore flushes the queue when connectivity returns.
  Future<String> saveScan(ScanRecord scan) async {
    final ref = scans.doc();
    // Intentionally not awaited: on a dead connection this future does not
    // complete until the device is back online, and the caller must not hang.
    // Local persistence guarantees the write survives an app kill.
    unawaited(ref.set(scan.toMap()));
    unawaited(_bumpDistrictStat(scan));
    unawaited(
      users.doc(scan.uid).update({'scanCount': FieldValue.increment(1)}),
    );
    return ref.id;
  }

  Future<void> attachImage(String scanId, String imageBase64) =>
      scans.doc(scanId).update({'imageBase64': imageBase64});

  Stream<List<ScanRecord>> watchMyScans(String uid, {int limit = 50}) => scans
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(ScanRecord.fromDoc).toList());

  Future<ScanRecord?> getScan(String id) async {
    final snap = await scans.doc(id).get();
    return snap.exists ? ScanRecord.fromDoc(snap) : null;
  }

  Stream<ScanRecord?> watchScan(String id) => scans
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? ScanRecord.fromDoc(s) : null);

  // ------------------------------------------------------- district stats

  /// Client-maintained aggregate.
  ///
  /// On the Blaze plan this would be a Cloud Function triggered by the scan
  /// write, which is race-free and cannot be forged by a client. On Spark we
  /// do it here with atomic increments: correct under concurrency, but it does
  /// mean the rules must allow an authenticated user to increment counters.
  /// That is an accepted trade for a free-tier demo, and is called out in
  /// firestore.rules.
  Future<void> _bumpDistrictStat(ScanRecord scan) async {
    if (!scan.contributesToMap) return;

    final ref = districtStats.doc(scan.district);
    final isDisease = !scan.isHealthy;

    // Counters are nested one level deep rather than written with dotted
    // field paths. Dot notation means "nested field" only to update(); inside
    // set() it creates a field literally NAMED "byDisease.corn_rust", so the
    // byDisease map would stay empty and both the map and the dashboard would
    // read zero. A nested map with merge:true deep-merges correctly, and
    // increments work inside it.
    await ref.set({
      'district': scan.district,
      'region': scan.region,
      'lat': scan.lat,
      'lng': scan.lng,
      'totalScans': FieldValue.increment(1),
      if (isDisease) ...{
        'diseaseCases': FieldValue.increment(1),
        'byDisease': {scan.diseaseKey: FieldValue.increment(1)},
        'bySpecies': {scan.species: FieldValue.increment(1)},
      },
      'lastReportedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }
}

/// Local stand-in for `package:async`'s unawaited, to avoid pulling in the
/// dependency for one helper. Documents that the omission is deliberate.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    // Swallowed on purpose: a queued Firestore write that ultimately fails
    // must not surface as an unhandled async error on the farmer's screen.
    // ignore: avoid_print
    print('FirestoreService: deferred write failed: $e');
  });
}
