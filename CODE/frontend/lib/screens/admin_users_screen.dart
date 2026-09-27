import 'package:flutter/material.dart';

import '../data/maharashtra_districts.dart';
import '../model/app_user.dart';
import '../services/firestore_service.dart';
import '../services/session.dart';
import '../utils/colors.dart';

/// Lets an admin change a user's role, verification and role-specific
/// details from inside the app.
///
/// Why this exists: promoting a farmer to a verified agronomist or an
/// officer is otherwise a manual Firestore-console edit (see
/// DOCUMENTATION/SETUP.md). Roles still cannot be self-assigned - that stays
/// enforced in firestore.rules (`notEscalatingPrivilege`) - but an admin
/// account can now do the promotion here instead of in the console.
///
/// The very first admin account still has to be set by hand in the console
/// once, because an app with zero admins has nobody able to open this
/// screen. Every promotion after that can happen here.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  // Cached rather than called inline in build()'s StreamBuilder.stream: the
  // search box calls setState on every keystroke, which was recreating this
  // and resubscribing the whole users collection listener per character.
  // watchAllUsers() never depends on _query - filtering happens client-side
  // below - so it only ever needs to be created once.
  late final Stream<List<AppUser>> _usersStream =
      FirestoreService.instance.watchAllUsers();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Manage Users',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AppUser>>(
              stream: _usersStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _message(
                    'Could not load users',
                    snap.error.toString(),
                  );
                }

                var users = snap.data ?? const <AppUser>[];
                final pending = _query.isEmpty
                    ? users.where((u) => u.hasPendingRoleRequest).toList()
                    : const <AppUser>[];

                if (_query.isNotEmpty) {
                  users = users
                      .where((u) =>
                          u.name.toLowerCase().contains(_query) ||
                          u.email.toLowerCase().contains(_query))
                      .toList();
                }
                users.sort((a, b) => a.name.toLowerCase().compareTo(
                      b.name.toLowerCase(),
                    ));

                if (users.isEmpty && pending.isEmpty) {
                  return _message('No users found', '');
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  children: [
                    if (pending.isNotEmpty) ...[
                      _sectionLabel('PENDING REQUESTS (${pending.length})'),
                      const SizedBox(height: 10),
                      for (final u in pending) ...[
                        _PendingRequestRow(user: u),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 18),
                      _sectionLabel('ALL USERS'),
                      const SizedBox(height: 10),
                    ],
                    for (final u in users) ...[
                      _UserRow(user: u),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1,
      color: Colors.grey.shade700,
    ),
  );

  Widget _message(String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 34, color: AppColors.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _UserRow extends StatelessWidget {
  final AppUser user;

  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context) {
    final isSelf = user.uid == Session.instance.user?.uid;

    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openEditSheet(context, user),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surfaceContainer,
                backgroundImage:
                    user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
                child: user.photoUrl.isEmpty
                    ? Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name.isEmpty ? '(no name)' : user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '(you)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _roleChip(user),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleChip(AppUser user) {
    final needsVerification =
        user.role == UserRole.agronomist && !user.verified;
    final color = needsVerification ? AppColors.tertiary : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        needsVerification ? '${user.role.label} - unverified' : user.role.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  void _openEditSheet(BuildContext context, AppUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditUserSheet(user: user),
    );
  }
}

class _EditUserSheet extends StatefulWidget {
  final AppUser user;

  const _EditUserSheet({required this.user});

  @override
  State<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends State<_EditUserSheet> {
  late UserRole _role = widget.user.role;
  late bool _verified = widget.user.verified;
  late final _qualificationController =
      TextEditingController(text: widget.user.qualification ?? '');
  late final _institutionController =
      TextEditingController(text: widget.user.institution ?? '');
  String? _district;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _district = widget.user.district;
  }

  @override
  void dispose() {
    _qualificationController.dispose();
    _institutionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final fields = <String, dynamic>{
      'role': _role.wire,
      // Only an agronomist's verification actually gates anything, but
      // clearing it for every other role keeps the field meaningful rather
      // than carrying a stale true from a previous role.
      'verified': _role == UserRole.agronomist ? _verified : false,
    };

    if (_role == UserRole.agronomist) {
      fields['qualification'] = _qualificationController.text.trim();
      fields['institution'] = _institutionController.text.trim();
    }
    if (_role == UserRole.officer && _district != null) {
      fields['district'] = _district;
    }

    try {
      await FirestoreService.instance.updateUserFields(widget.user.uid, fields);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.user.name.isEmpty ? '(no name)' : widget.user.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                widget.user.email,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),

              const Text(
                'ROLE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _roleSelector(),

              if (_role == UserRole.agronomist) ...[
                const SizedBox(height: 18),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _verified,
                  onChanged: (v) => setState(() => _verified = v),
                  activeThumbColor: AppColors.primary,
                  title: const Text(
                    'Verified',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'Required before this account can rule on cases',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: 6),
                _textField(_qualificationController, 'Qualification',
                    'e.g. M.Sc. Plant Pathology'),
                const SizedBox(height: 10),
                _textField(_institutionController, 'Institution',
                    'e.g. KVK Kolhapur'),
              ],

              if (_role == UserRole.officer) ...[
                const SizedBox(height: 18),
                const Text(
                  'DISTRICT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _districtSelector(),
              ],

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.error),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'SAVE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
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

  Widget _roleSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final role in UserRole.values)
          ChoiceChip(
            label: Text(role.label),
            selected: _role == role,
            onSelected: (_) => setState(() => _role = role),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _role == role ? Colors.white : AppColors.onSurface,
            ),
            backgroundColor: AppColors.surfaceContainerLowest,
            side: const BorderSide(color: AppColors.outlineVariant),
          ),
      ],
    );
  }

  Widget _districtSelector() {
    return DropdownButtonFormField<String>(
      initialValue: _district,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      hint: const Text('Select a district'),
      items: [
        for (final d in MaharashtraDistricts.all)
          DropdownMenuItem(value: d.name, child: Text(d.name)),
      ],
      onChanged: (v) => setState(() => _district = v),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      style: const TextStyle(fontSize: 13.5),
    );
  }
}

/// One self-filed role request, waiting on an admin's decision.
///
/// Approving pulls the details the requester supplied (qualification /
/// institution, or district) straight into the real fields - the same
/// information already went through a human at request time, so there is
/// nothing extra to re-type. The role only actually changes here, via
/// updateUserFields, which is isAdmin()-gated in firestore.rules; the request
/// fields themselves carry no privilege on their own.
class _PendingRequestRow extends StatefulWidget {
  final AppUser user;

  const _PendingRequestRow({required this.user});

  @override
  State<_PendingRequestRow> createState() => _PendingRequestRowState();
}

class _PendingRequestRowState extends State<_PendingRequestRow> {
  bool _busy = false;
  String? _error;

  Future<void> _approve() async {
    final u = widget.user;
    final role = u.requestedRole;
    if (role == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final fields = <String, dynamic>{
      'role': role.wire,
      'verified': role == UserRole.agronomist,
      'requestedRole': null,
      'requestedAt': null,
    };
    if (role == UserRole.agronomist) {
      fields['qualification'] = u.requestedQualification;
      fields['institution'] = u.requestedInstitution;
      fields['requestedQualification'] = null;
      fields['requestedInstitution'] = null;
    }
    if (role == UserRole.officer) {
      fields['district'] = u.requestedDistrict;
      fields['requestedDistrict'] = null;
    }

    try {
      await FirestoreService.instance.updateUserFields(u.uid, fields);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not approve: $e';
      });
    }
  }

  Future<void> _reject() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirestoreService.instance.updateUserFields(widget.user.uid, {
        'requestedRole': null,
        'requestedAt': null,
        'requestedQualification': null,
        'requestedInstitution': null,
        'requestedDistrict': null,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reject: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final role = u.requestedRole!;
    final detail = role == UserRole.agronomist
        ? '${u.requestedQualification ?? "-"} - ${u.requestedInstitution ?? "-"}'
        : (u.requestedDistrict ?? '-');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.name.isEmpty ? '(no name)' : u.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'wants to become ${role.label} - $detail',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(fontSize: 11, color: AppColors.error),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: const BorderSide(color: AppColors.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _approve,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Approve',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
