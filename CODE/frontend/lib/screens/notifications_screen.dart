import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/hotspot_service.dart';
import '../utils/colors.dart';

/// Profile -> Notifications.
///
/// There are no real notification preferences yet (no Cloud Functions on the
/// free tier means no FCM push - see ARCHITECTURE.md), so the demo-data
/// seed/clear tools live here instead, unconditionally - by request, not
/// gated to debug builds or to admin accounts. Anyone who can open the app
/// can seed or clear the map's demo rows from this screen.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l10n.profileNotifications,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.notificationsDebugTools,
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              _buildTile(
                icon: Icons.auto_awesome_outlined,
                title: l10n.profileSeedDemo,
                subtitle: l10n.profileSeedDemoSubtitle,
                onTap: _seedDemo,
              ),
              _buildTile(
                icon: Icons.delete_sweep_outlined,
                title: l10n.profileClearDemo,
                subtitle: l10n.profileClearDemoSubtitle,
                onTap: _clearDemo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _seedDemo() async {
    final l10n = AppLocalizations.of(context)!;
    _toast(l10n.profileSeeding);
    try {
      await HotspotService.instance.seedDemoData();
      _toast(l10n.profileSeeded);
    } catch (e) {
      _toast(l10n.profileSeedFailed(e.toString()));
    }
  }

  Future<void> _clearDemo() async {
    final l10n = AppLocalizations.of(context)!;
    _toast(l10n.profileClearing);
    try {
      await HotspotService.instance.clearDemoData();
      _toast(l10n.profileCleared);
    } catch (e) {
      _toast(l10n.profileClearFailed(e.toString()));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

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
