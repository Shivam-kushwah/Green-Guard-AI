import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/hotspot_service.dart';
import '../widgets/model_status_card.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:hive/hive.dart';

import '../model/user_model.dart';
import '../services/google_auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _auth = AuthService();

  final userBox = Hive.box<UserModel>('userBox');
  late final user = userBox.get("currentUser");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFDDE4D6), // soft green bg
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 20),

              /// Profile Avatar
              Stack(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F3E46),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 10,
                          color: Colors.black.withOpacity(0.2),
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: user?.photoUrl != null && user!.photoUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.network(
                              user!.photoUrl!,
                              fit: BoxFit.cover,
                            ),
                          )
                        /// Otherwise show default icon
                        : const Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.white,
                          ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              /// Name
              Text(
                '${user?.name}',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 4),

              /// Email
              Text(
                '${user?.email}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),

              const SizedBox(height: 28),

              /// Section Title
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "ACCOUNT PREFERENCES",
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              /// Settings Cards
              /// Learning loop status - which model is running, and whether
              /// a retrained one is available.
              const ModelStatusCard(),

              _buildTile(
                icon: Icons.notifications_none,
                title: "Notifications",
                onTap: () {},
              ),

              _buildTile(
                icon: Icons.language,
                title: "Language",
                subtitle: "English (US)",
                onTap: () {},
              ),

              _buildTile(
                icon: Icons.shield_outlined,
                title: "Privacy Policy",
                onTap: () {},
              ),

              /// Demo tooling. Compiled out of release builds entirely, so
              /// there is no path for seeded data to reach a real deployment
              /// through the UI.
              if (kDebugMode) ...[
                _buildTile(
                  icon: Icons.auto_awesome_outlined,
                  title: "Seed demo outbreak data",
                  subtitle: "Fills the map for a demo - marked as demo data",
                  onTap: _seedDemo,
                ),
                _buildTile(
                  icon: Icons.delete_sweep_outlined,
                  title: "Clear demo data",
                  subtitle: "Removes every seeded district row",
                  onTap: _clearDemo,
                ),
              ],

              const Spacer(),

              /// Logout Button
              Container(
                width: double.infinity,
                height: 55,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9B7B7),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextButton.icon(
                  onPressed: () async {
                    await _auth.signOut();

                    userBox.delete("currentUser");

                    if (!mounted) return;

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => LoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    "Log Out",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              /// Version Text
              Center(
                child: Text(
                  "Version 1.0.0 -  Green Guard",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _seedDemo() async {
    _toast('Seeding demo data...');
    try {
      await HotspotService.instance.seedDemoData();
      _toast('Demo outbreak data added to the map');
    } catch (e) {
      _toast('Seeding failed: $e');
    }
  }

  Future<void> _clearDemo() async {
    _toast('Clearing demo data...');
    try {
      await HotspotService.instance.clearDemoData();
      _toast('Demo data removed');
    } catch (e) {
      _toast('Clear failed: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Settings Tile Widget
  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F0E7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.green),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
