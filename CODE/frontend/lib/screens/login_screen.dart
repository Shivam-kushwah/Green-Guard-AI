// import 'package:flutter/material.dart';
// import 'package:frontend/services/google_auth_service.dart';
//
// class LoginScreen extends StatelessWidget {
//   LoginScreen({super.key});
//
//   final AuthService _auth = AuthService();
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Center(
//         child: ElevatedButton.icon(
//           icon: const Icon(Icons.login),
//
//           label: const Text("Sign in with Google"),
//
//           onPressed: () async {
//             final user = await _auth.signInWithGoogle();
//
//             if (user != null) {
//               print(user.email);
//
//               Navigator.pushReplacementNamed(context, "/home");
//             } else {
//               print("Login Failed");
//             }
//           },
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:frontend/l10n/gen/app_localizations.dart';
import 'package:frontend/model/app_user.dart';
import 'package:frontend/screens/app_gate.dart';
import 'package:frontend/screens/role_request_screen.dart';
import 'package:frontend/services/google_auth_service.dart';

class LoginScreen extends StatefulWidget {
  LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogging = false;
  final AuthService _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE6EDE0), Color(0xFFD6DEC9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),

        child: SafeArea(
          child: isLogging
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,

                    children: [
                      const Spacer(),

                      // 🌿 Logo Section
                      _buildLogo(context),

                      const SizedBox(height: 30),

                      // 📝 Welcome Text
                      _buildTitle(context),

                      const SizedBox(height: 40),

                      // 🔘 Google Button Card
                      _buildGoogleCard(context),

                      const Spacer(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // 🌿 LOGO SECTION
  Widget _buildLogo(BuildContext context) {
    return Column(
      children: [
        // Rounded Logo Box
        Container(
          height: 70,
          width: 70,

          // decoration: BoxDecoration(
          //   color: const Color(0xFF3A7D44),
          //   borderRadius: BorderRadius.circular(16),
          // ),
          child: Image.asset('assets/images/logo.png'),
        ),

        const SizedBox(height: 14),

        const Text(
          "GREEN GUARD",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),

        Text(
          AppLocalizations.of(context)!.loginTagline,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 2,
            color: Colors.green,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // 📝 TITLE SECTION
  Widget _buildTitle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          l10n.loginWelcome,
          textAlign: TextAlign.center,

          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2A1F),
          ),
        ),

        const SizedBox(height: 12),

        Text(
          l10n.loginSubtitle,
          textAlign: TextAlign.center,

          style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
        ),
      ],
    );
  }

  // 🔘 GOOGLE LOGIN CARD
  Widget _buildGoogleCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        children: [
          // Google Button
          GestureDetector(
            onTap: () async {
              setState(() {
                isLogging = true;
              });

              final result = await _auth.signInWithGoogle();

              if (result != null) {
                setState(() {
                  isLogging = false;
                });

                if (!context.mounted) {
                  return;
                }
                // Whether this is a brand-new sign-up or a returning user is
                // decided by onboardingComplete on the profile signInWithGoogle
                // already fetched/created - no extra Firestore round trip
                // needed here just to make this routing decision. An account
                // that already has a real, non-farmer role (set up by hand in
                // the console before this screen existed, or already
                // approved) or an already-pending request must never be sent
                // back through the picker just because that one flag was
                // never set on it.
                final p = result.profile;
                final skipPicker = p.onboardingComplete ||
                    p.role != UserRole.farmer ||
                    p.hasPendingRoleRequest;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        skipPicker ? const AppGate() : RoleRequestScreen(user: p),
                  ),
                );
              } else {
                debugPrint("Login Failed");

                setState(() {
                  isLogging = false;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!.loginErrorRetry),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },

            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),

              decoration: BoxDecoration(
                color: const Color(0xFFE3E8DD),

                borderRadius: BorderRadius.circular(30),
              ),

              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  // Google Logo
                  Image.asset(
                    'assets/images/google_logo.png',
                    height: 22,
                    width: 22,
                  ),

                  const SizedBox(width: 12),

                  Text(
                    AppLocalizations.of(context)!.loginContinueGoogle,

                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // 🔒 Footer Text
          Row(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              const Icon(Icons.circle, size: 6, color: Colors.green),

              const SizedBox(width: 8),

              Text(
                AppLocalizations.of(context)!.loginSecureAccess,

                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),

              SizedBox(width: 8),

              Icon(Icons.circle, size: 6, color: Colors.green),
            ],
          ),
        ],
      ),
    );
  }
}
