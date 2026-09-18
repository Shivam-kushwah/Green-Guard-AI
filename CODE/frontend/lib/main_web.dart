import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/officer_dashboard_screen.dart';
import 'services/firestore_service.dart';
import 'services/session.dart';
import 'utils/colors.dart';

/// Web entry point - the officer dashboard only.
///
/// Why this is a separate entry point rather than `main.dart`:
/// tflite_flutter binds the native TensorFlow Lite runtime through `dart:ffi`,
/// which does not exist on the web platform, so any file that reaches
/// TfService cannot compile to JavaScript. Officers never run inference - they
/// read aggregates - so the dashboard build simply never imports it.
///
/// Build and deploy:
///   flutter build web -t lib/main_web.dart --release \
///     --dart-define=FB_API_KEY=... --dart-define=FB_APP_ID=... \
///     --dart-define=FB_SENDER_ID=... --dart-define=FB_PROJECT_ID=... \
///     --dart-define=FB_AUTH_DOMAIN=... --dart-define=FB_STORAGE_BUCKET=...
///   firebase deploy --only hosting
///
/// The values come from Firebase console -> Project settings -> your web app.
/// A web app has to be registered there first; google-services.json covers
/// Android only. These are passed as dart-defines rather than committed,
/// though note that Firebase web config is not secret by design - access is
/// controlled by the Firestore rules, not by hiding these strings.
class WebFirebaseConfig {
  static const apiKey = String.fromEnvironment('FB_API_KEY');
  static const appId = String.fromEnvironment('FB_APP_ID');
  static const messagingSenderId = String.fromEnvironment('FB_SENDER_ID');
  static const projectId = String.fromEnvironment(
    'FB_PROJECT_ID',
    defaultValue: 'green-guard-efb41',
  );
  static const authDomain = String.fromEnvironment('FB_AUTH_DOMAIN');
  static const storageBucket = String.fromEnvironment('FB_STORAGE_BUCKET');

  static bool get isComplete =>
      apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: authDomain.isEmpty ? '$projectId.firebaseapp.com' : authDomain,
    storageBucket: storageBucket.isEmpty
        ? '$projectId.firebasestorage.app'
        : storageBucket,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!WebFirebaseConfig.isComplete) {
    // Fail loudly and legibly rather than throwing an opaque Firebase error.
    runApp(const _ConfigErrorApp());
    return;
  }

  await Firebase.initializeApp(options: WebFirebaseConfig.options);
  await FirestoreService.configureOffline();
  Session.instance.start();

  runApp(const DashboardApp());
}

class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Green Guard - State Surveillance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Plus Jakarta Sans',
        scaffoldBackgroundColor: AppColors.surface,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          surface: AppColors.surface,
        ),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Signs the officer in, then hands over to the dashboard.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Popup rather than the google_sign_in plugin: on web that plugin has a
      // different flow, and signInWithPopup is the supported path.
      final provider = GoogleAuthProvider();
      final cred = await FirebaseAuth.instance.signInWithPopup(provider);
      final user = cred.user;
      if (user != null) {
        await FirestoreService.instance.ensureUserProfile(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          photoUrl: user.photoURL ?? '',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == null) return _signInScreen();

        // Session drives the role gate inside the dashboard itself.
        return AnimatedBuilder(
          animation: Session.instance,
          builder: (_, __) => const OfficerDashboardScreen(),
        );
      },
    );
  }

  Widget _signInScreen() => Scaffold(
    backgroundColor: AppColors.surface,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.eco_rounded, size: 52, color: AppColors.primary),
              const SizedBox(height: 18),
              const Text(
                'Green Guard',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Maharashtra crop disease surveillance',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login_rounded, size: 19),
                  label: Text(_busy ? 'Signing in...' : 'Sign in with Google'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              const Text(
                'Officer accounts only. Farmers and agronomists use the '
                'mobile app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shown when the build was made without the Firebase web config.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.settings_outlined,
                    size: 38, color: AppColors.error),
                SizedBox(height: 14),
                Text(
                  'Firebase web config missing',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'This build was compiled without the Firebase web keys. '
                  'Register a Web app in the Firebase console (Project '
                  'settings -> Your apps), then rebuild passing the values:',
                  style: TextStyle(fontSize: 13, height: 1.55),
                ),
                SizedBox(height: 14),
                SelectableText(
                  'flutter build web -t lib/main_web.dart --release \\\n'
                  '  --dart-define=FB_API_KEY=... \\\n'
                  '  --dart-define=FB_APP_ID=... \\\n'
                  '  --dart-define=FB_SENDER_ID=... \\\n'
                  '  --dart-define=FB_PROJECT_ID=green-guard-efb41',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
