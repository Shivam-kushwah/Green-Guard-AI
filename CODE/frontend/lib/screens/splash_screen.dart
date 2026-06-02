import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/model/user_model.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/main_screen.dart';
import 'package:hive/hive.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final userBox = Hive.box<UserModel>('userBox');

  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isInitialized) {
      _isInitialized = true;
      _initializeSplash();
    }
  }

  Future<void> _initializeSplash() async {
    // Precache image
    await precacheImage(
      const AssetImage('assets/images/splash_bg.png'),
      context,
    );

    /// Wait splash duration
    await Future.delayed(const Duration(seconds: 3));

    // Get user
    final user = userBox.get("currentUser");

    if (!mounted) return;

    // Navigate AFTER delay
    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox(
        height: size.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            /// Top spacing (status bar safe)
            SizedBox(height: MediaQuery.of(context).padding.top + 30),

            /// Title
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/logo_full.png'),

                      Text(
                        'Version 1.0.0',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            /// Background Image
            Align(
              alignment: Alignment.bottomLeft,
              child: Image.asset(
                'assets/images/splash_bg.png',
                fit: BoxFit.fill,
                height: size.height * 0.65,
                width: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
