import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/app_user.dart';
import 'firestore_service.dart';

/// Holds the signed-in user's cloud profile, including their role.
///
/// A single listenable source means role-dependent UI (the agronomist queue,
/// the officer dashboard) reacts the moment an admin verifies someone, rather
/// than waiting for an app restart.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _kCachedUid = 'session_cached_uid';
  static const _kCachedRole = 'session_cached_role';
  static const _kCachedPending = 'session_cached_pending';

  AppUser? _user;
  StreamSubscription<AppUser?>? _sub;
  StreamSubscription<User?>? _authSub;

  AppUser? get user => _user;
  bool get isSignedIn => _user != null;

  UserRole get role => _user?.role ?? UserRole.farmer;
  bool get canReview => _user?.canReview ?? false;
  bool get canViewDashboard => _user?.canViewDashboard ?? false;

  /// Best-known role/pending status from before the live Firestore stream
  /// resolves, so AppGate can make an instant first guess on cold start
  /// instead of always showing a loader - filled in by [preloadCache].
  String? cachedUid;
  bool cachedHasPendingRequest = false;

  /// Reads the last-persisted session snapshot. Call once, before the first
  /// frame (see main()), so AppGate's very first build already has a
  /// reasonable guess rather than a guaranteed loading flash on every cold
  /// start.
  Future<void> preloadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      cachedUid = prefs.getString(_kCachedUid);
      cachedHasPendingRequest = prefs.getBool(_kCachedPending) ?? false;
    } catch (e) {
      debugPrint('Session: cache preload failed: $e');
    }
  }

  Future<void> _persistCache(AppUser u) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedUid, u.uid);
      await prefs.setString(_kCachedRole, u.role.wire);
      await prefs.setBool(_kCachedPending, u.hasPendingRoleRequest);
    } catch (e) {
      debugPrint('Session: cache write failed: $e');
    }
  }

  Future<void> _clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCachedUid);
      await prefs.remove(_kCachedRole);
      await prefs.remove(_kCachedPending);
    } catch (e) {
      debugPrint('Session: cache clear failed: $e');
    }
  }

  /// Begin tracking the signed-in user. Safe to call more than once.
  void start() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((authUser) {
      _sub?.cancel();
      if (authUser == null) {
        _user = null;
        unawaited(_clearCache());
        notifyListeners();
        return;
      }
      _sub = FirestoreService.instance.watchUser(authUser.uid).listen(
        (profile) {
          _user = profile;
          if (profile != null) unawaited(_persistCache(profile));
          notifyListeners();
        },
        onError: (Object e) {
          // Offline or rules rejection - keep whatever profile we had rather
          // than logging the farmer out of role-gated screens mid-session.
          debugPrint('Session: profile stream error: $e');
        },
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
