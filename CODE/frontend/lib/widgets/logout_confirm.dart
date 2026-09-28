import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Asks the user to confirm before signing out. Resolves true only if they
/// tapped the destructive action.
Future<bool> confirmLogout(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.logoutConfirmTitle),
      content: Text(l10n.logoutConfirmMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            l10n.logout,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}
