import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../l10n/gen/app_localizations.dart';
import '../model/app_user.dart';
import '../model/user_model.dart';
import '../services/google_auth_service.dart';
import '../utils/colors.dart';
import '../widgets/logout_confirm.dart';
import 'login_screen.dart';

/// Shown instead of the app for a farmer whose agronomist/officer request is
/// still waiting on an admin.
///
/// Deliberately blocking: an unapproved account must not be able to use the
/// review queue or dashboard tabs even briefly, so it never even reaches
/// MainScreen while requestedRole is set. AppGate is what re-evaluates this
/// live - the moment an admin approves or rejects (Session's Firestore
/// stream delivers the change), AppGate swaps this screen out on its own,
/// no polling or manual refresh needed here.
class PendingApprovalScreen extends StatelessWidget {
  final AppUser user;

  const PendingApprovalScreen({super.key, required this.user});

  Future<void> _logout(BuildContext context) async {
    if (!await confirmLogout(context)) return;
    if (!context.mounted) return;
    await AuthService().signOut();
    await Hive.box<UserModel>('userBox').delete('currentUser');
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final role = user.requestedRole;
    final detail = role == UserRole.agronomist
        ? [user.requestedQualification, user.requestedInstitution]
              .where((s) => s != null && s.isNotEmpty)
              .join(' - ')
        : user.requestedDistrict;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 38,
                  color: AppColors.tertiary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.pendingTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                role == null
                    ? l10n.pendingSubtitleGeneric
                    : l10n.pendingSubtitleForRole(role.label),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F171D14),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role?.label.toUpperCase() ?? '',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: AppColors.tertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                l10n.pendingAutoLetIn,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _logout(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded,
                      size: 18, color: AppColors.error),
                  label: Text(
                    l10n.logout,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
