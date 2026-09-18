import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/screens/splash_screen.dart';
import 'package:frontend/utils/colors.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'model/diagnosis_history_model.dart';
import 'model/user_model.dart';
import 'services/firestore_service.dart';
import 'services/model_update_service.dart';
import 'services/session.dart';
import 'services/tf_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Must run before any Firestore read or write. Disk persistence is what
  // keeps the app usable on a field connection: reads fall back to cache and
  // writes queue locally until signal returns.
  await FirestoreService.configureOffline();

  await Hive.initFlutter();

  Hive.registerAdapter(UserModelAdapter());
  Hive.registerAdapter(DiagnosisHistoryAdapter());

  await Hive.openBox<UserModel>('userBox');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Tracks the signed-in user profile so role-gated screens react the moment
  // an admin verifies an agronomist, without needing an app restart.
  Session.instance.start();

  // Prefer a model downloaded by the learning loop over the one compiled
  // into the APK, so a phone that already updated keeps the newer weights
  // across restarts. Falls back to the bundled asset if nothing is stored or
  // the cached file has been evicted by the OS.
  final usingDownloaded =
      await ModelUpdateService.instance.loadActiveModel();
  if (!usingDownloaded) {
    await TfService.instance.loadModel();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Green Guard',
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
      home: const SplashScreen(),
    );
  }
}
