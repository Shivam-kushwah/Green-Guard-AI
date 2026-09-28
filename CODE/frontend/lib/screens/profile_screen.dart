import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../model/app_user.dart';
import '../services/locale_controller.dart';
import '../services/session.dart';
import '../services/app_info.dart';
import '../widgets/logout_confirm.dart';
import '../widgets/model_status_card.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:hive/hive.dart';

import '../model/user_model.dart';
import '../services/google_auth_service.dart';
import 'admin_users_screen.dart';
import 'notifications_screen.dart';
import 'privacy_policy_screen.dart';

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
    // This screen is the one tab every role keeps unconditionally (the 3rd
    // tab swaps *type* per role and remounts correctly on its own; Profile
    // does not), so Flutter's widget diffing otherwise never re-runs this
    // build() when the role changes underneath it - watching Session here is
    // what makes the admin-only section actually reflect who is signed in
    // now, not whoever was signed in when this tab first mounted.
    final role = context.watch<Session>().role;
    final locale = context.watch<LocaleController>().locale;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFDDE4D6), // soft green bg
      body: SafeArea(
        child: SingleChildScrollView(
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
                              cacheWidth: 220,
                              cacheHeight: 220,
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
                  l10n.profileAccountPreferences,
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
                title: l10n.profileNotifications,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),

              _buildTile(
                icon: Icons.language,
                title: l10n.profileLanguage,
                subtitle: switch (locale?.languageCode) {
                  'hi' => l10n.languageHindi,
                  'mr' => l10n.languageMarathi,
                  _ => l10n.languageEnglish,
                },
                onTap: () => _showLanguagePicker(context, l10n, locale),
              ),

              _buildTile(
                icon: Icons.shield_outlined,
                title: l10n.profilePrivacyPolicy,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                ),
              ),


              // Only an admin can promote/verify other users, and only an
              // admin sees this - everyone else has no use for it.
              if (role == UserRole.admin) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.profileAdministration,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildTile(
                  icon: Icons.manage_accounts_outlined,
                  title: l10n.profileManageUsers,
                  subtitle: l10n.profileManageUsersSubtitle,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminUsersScreen(),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),

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
                    if (!await confirmLogout(context)) return;
                    await _auth.signOut();

                    userBox.delete("currentUser");

                    if (!mounted) return;

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => LoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: Text(
                    l10n.logout,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              /// Version Text
              Center(
                child: FutureBuilder<String>(
                  future: AppInfo.version(),
                  builder: (context, snap) => Text(
                    l10n.profileVersion(snap.data ?? ''),
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(
    BuildContext context,
    AppLocalizations l10n,
    Locale? current,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.profileChooseLanguage,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              RadioGroup<String>(
                groupValue: current?.languageCode ?? 'en',
                onChanged: (code) {
                  if (code == null) return;
                  LocaleController.instance.setLocale(Locale(code));
                  Navigator.pop(sheetContext);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'en',
                      title: Text(l10n.languageEnglish),
                    ),
                    RadioListTile<String>(
                      value: 'hi',
                      title: Text(l10n.languageHindi),
                    ),
                    RadioListTile<String>(
                      value: 'mr',
                      title: Text(l10n.languageMarathi),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
