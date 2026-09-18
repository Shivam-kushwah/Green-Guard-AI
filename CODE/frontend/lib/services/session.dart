import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

  AppUser? _user;
  StreamSubscription<AppUser?>? _sub;
  StreamSubscription<User?>? _authSub;

  AppUser? get user => _user;
  bool get isSignedIn => _user != null;

  UserRole get role => _user?.role ?? UserRole.farmer;
  bool get canReview => _user?.canReview ?? false;
  bool get canViewDashboard => _user?.canViewDashboard ?? false;

  /// Begin tracking the signed-in user. Safe to call more than once.
  void start() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((authUser) {
      _sub?.cancel();
      if (authUser == null) {
        _user = null;
        notifyListeners();
        return;
      }
      _sub = FirestoreService.instance.watchUser(authUser.uid).listen(
        (profile) {
          _user = profile;
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
