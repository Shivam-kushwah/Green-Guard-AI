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
import 'package:frontend/screens/main_screen.dart';
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
                      _buildLogo(),

                      const SizedBox(height: 30),

                      // 📝 Welcome Text
                      _buildTitle(),

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
  Widget _buildLogo() {
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

        const Text(
          "BOTANICAL INTELLIGENCE",
          style: TextStyle(
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
  Widget _buildTitle() {
    return Column(
      children: const [
        Text(
          "Welcome to Green Guard",
          textAlign: TextAlign.center,

          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2A1F),
          ),
        ),

        SizedBox(height: 12),

        Text(
          "Your partner in plant health and\nbotanical intelligence.",
          textAlign: TextAlign.center,

          style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
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

              final user = await _auth.signInWithGoogle();

              if (user != null) {
                print(user.email);

                setState(() {
                  isLogging = false;
                });

                if (!context.mounted) {
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                );
              } else {
                print("Login Failed");

                setState(() {
                  isLogging = false;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Error While logging. Try again later !"),
                    duration: Duration(seconds: 2),
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

                  const Text(
                    "Continue with Google",

                    style: TextStyle(
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              Icon(Icons.circle, size: 6, color: Colors.green),

              SizedBox(width: 8),

              Text(
                "ENCRYPTED SECURE ACCESS",

                style: TextStyle(
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
