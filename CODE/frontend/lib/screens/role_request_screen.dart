import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/maharashtra_districts.dart';
import '../l10n/gen/app_localizations.dart';
import '../model/app_user.dart';
import '../services/firestore_service.dart';
import '../utils/colors.dart';
import 'app_gate.dart';

/// Shown once, right after a farmer's very first sign-in.
///
/// Roles cannot be self-assigned - firestore.rules blocks a user from writing
/// their own `role`/`verified` (notEscalatingPrivilege), for the same reason
/// an unverified stranger can't claim to be a KVK agronomist and start ruling
/// on cases. So this screen never grants a role: it only files a request
/// (requestedRole + supporting details), which sits in the Manage Users
/// screen until an admin approves it. Picking Farmer needs no approval and
/// goes straight into the app; Agronomist/Officer land on
/// PendingApprovalScreen (via AppGate) until that happens.
class RoleRequestScreen extends StatefulWidget {
  final AppUser user;

  const RoleRequestScreen({super.key, required this.user});

  @override
  State<RoleRequestScreen> createState() => _RoleRequestScreenState();
}

class _RoleRequestScreenState extends State<RoleRequestScreen> {
  UserRole _choice = UserRole.farmer;
  String? _district;
  final _qualificationController = TextEditingController();
  final _institutionController = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qualificationController.dispose();
    _institutionController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final fields = <String, dynamic>{'onboardingComplete': true};

    if (_choice != UserRole.farmer) {
      fields['requestedRole'] = _choice.wire;
      fields['requestedAt'] = Timestamp.now();
      if (_choice == UserRole.agronomist) {
        fields['requestedQualification'] = _qualificationController.text.trim();
        fields['requestedInstitution'] = _institutionController.text.trim();
      }
      if (_choice == UserRole.officer && _district != null) {
        fields['requestedDistrict'] = _district;
      }
    }

    try {
      await FirestoreService.instance.updateUserFields(widget.user.uid, fields);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppGate()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppLocalizations.of(context)!.roleSaveError(e.toString());
      });
    }
  }

  bool get _canContinue {
    if (_choice == UserRole.agronomist) {
      return _qualificationController.text.trim().isNotEmpty &&
          _institutionController.text.trim().isNotEmpty;
    }
    if (_choice == UserRole.officer) return _district != null;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F0E2), AppColors.surface],
            stops: [0.0, 0.35],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.eco_rounded,
                      size: 28, color: AppColors.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.roleRequestTitle,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.5,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.roleRequestSubtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),

                _roleCard(
                  role: UserRole.farmer,
                  icon: Icons.agriculture_rounded,
                  title: l10n.roleFarmerTitle,
                  subtitle: l10n.roleFarmerSubtitle,
                ),
                const SizedBox(height: 12),
                _roleCard(
                  role: UserRole.agronomist,
                  icon: Icons.fact_check_outlined,
                  title: l10n.roleAgronomistTitle,
                  subtitle: l10n.roleAgronomistSubtitle,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _choice == UserRole.agronomist
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            children: [
                              _textField(_qualificationController,
                                  l10n.roleFieldQualification,
                                  l10n.roleFieldQualificationHint),
                              const SizedBox(height: 10),
                              _textField(_institutionController,
                                  l10n.roleFieldInstitution,
                                  l10n.roleFieldInstitutionHint),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 12),
                _roleCard(
                  role: UserRole.officer,
                  icon: Icons.insights_rounded,
                  title: l10n.roleOfficerTitle,
                  subtitle: l10n.roleOfficerSubtitle,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _choice == UserRole.officer
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _districtSelector(l10n),
                        )
                      : const SizedBox(width: double.infinity),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ],

                const SizedBox(height: 28),
                _submitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Only this button needs to react to keystrokes (the qualification /
  /// institution fields gate _canContinue) - merging the two controllers'
  /// own Listenable and scoping the rebuild to just this widget means typing
  /// no longer rebuilds the whole screen (role cards, gradients, animations
  /// and all) on every character, which is what made this screen feel
  /// laggy on a real device despite doing very little actual work.
  Widget _submitButton() => AnimatedBuilder(
    animation: Listenable.merge([_qualificationController, _institutionController]),
    builder: (context, _) {
      final enabled = !_saving && _canContinue;
      return SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryContainer],
                  )
                : null,
            color: enabled ? null : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(28),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: Color(0x401B6D24),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: enabled ? _continue : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _choice == UserRole.farmer
                              ? AppLocalizations.of(context)!.roleContinueFarmer
                              : AppLocalizations.of(context)!.roleSubmitRequest,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: enabled
                                ? Colors.white
                                : AppColors.onSurfaceVariant,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _roleCard({
    required UserRole role,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _choice == role;
    return GestureDetector(
      onTap: () => setState(() => _choice = role),
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.99,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : const Color(0x0F171D14),
                blurRadius: selected ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: selected ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.outlineVariant,
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _districtSelector(AppLocalizations l10n) => DropdownButtonFormField<String>(
    initialValue: _district,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: l10n.roleFieldDistrict,
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    items: [
      for (final d in MaharashtraDistricts.all)
        DropdownMenuItem(value: d.name, child: Text(d.name)),
    ],
    onChanged: (v) => setState(() => _district = v),
  );

  Widget _textField(
    TextEditingController controller,
    String label,
    String hint,
  ) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
