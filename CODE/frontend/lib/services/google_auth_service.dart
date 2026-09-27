import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:frontend/model/app_user.dart';
import 'package:frontend/model/user_model.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive/hive.dart';

import 'firestore_service.dart';

/// What a successful sign-in produced: the Firebase identity, and the cloud
/// profile that decides where to route next (RoleRequestScreen vs AppGate).
typedef SignInResult = ({User user, AppUser profile});

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<SignInResult?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) return null;

      final userBox = Hive.box<UserModel>('userBox');

      final userModel = UserModel(
        uid: user.uid,
        name: user.displayName ?? "",
        email: user.email ?? "",
        photoUrl: user.photoURL ?? "",
      );

      // Local cache of the signed-in identity, so the app opens straight
      // into the scan flow offline without waiting on Firestore.
      await userBox.put("currentUser", userModel);

      // Cloud profile carries the role, district and verification status.
      // Created on first sign-in, refreshed on later ones. Failure here must
      // not block login - a farmer with no signal should still be able to
      // scan, and the profile is reconciled on the next successful start.
      AppUser profile;
      try {
        profile = await FirestoreService.instance.ensureUserProfile(
          uid: user.uid,
          name: userModel.name,
          email: userModel.email,
          photoUrl: userModel.photoUrl,
        );
      } catch (e) {
        debugPrint("Cloud profile sync deferred: $e");
        // A bare-minimum farmer profile so routing can still happen offline;
        // Session's live stream reconciles the real one once signal returns.
        profile = AppUser(
          uid: user.uid,
          name: userModel.name,
          email: userModel.email,
          photoUrl: userModel.photoUrl,
          role: UserRole.farmer,
          onboardingComplete: true,
          createdAt: DateTime.now(),
        );
      }

      return (user: user, profile: profile);
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");

      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();

    await _auth.signOut();
  }
}
