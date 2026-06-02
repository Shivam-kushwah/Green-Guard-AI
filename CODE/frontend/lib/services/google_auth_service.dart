import 'package:firebase_auth/firebase_auth.dart';
import 'package:frontend/model/user_model.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive/hive.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<User?> signInWithGoogle() async {
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

      if (user != null) {
        final userBox = Hive.box<UserModel>('userBox');

        final userModel = UserModel(
          uid: user.uid,
          name: user.displayName ?? "",
          email: user.email ?? "",
          photoUrl: user.photoURL ?? "",
        );

        // Save user
        await userBox.put("currentUser", userModel);
      }

      return user;
    } catch (e) {
      print("Google Sign-In Error: $e");

      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();

    await _auth.signOut();
  }
}
