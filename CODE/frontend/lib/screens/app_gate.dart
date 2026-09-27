import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/session.dart';
import '../utils/colors.dart';
import 'main_screen.dart';
import 'pending_approval_screen.dart';

/// Single reactive decision point between MainScreen and
/// PendingApprovalScreen, re-evaluated live off Session.
///
/// Both LoginScreen (returning user) and RoleRequestScreen (just submitted a
/// request) land here rather than pushing MainScreen directly, so an
/// approval or rejection that happens while someone is sitting on the
/// pending screen swaps them into the real app immediately - Session's
/// Firestore stream notifies, this rebuilds, no polling or manual refresh.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;

    // Firebase auth already resolved (that's how anything reached this
    // widget), but the Firestore profile stream can take a moment to
    // deliver its first snapshot. Rather than a guaranteed flash of
    // MainScreen for someone who turns out to be pending, use the
    // last-persisted guess (SharedPreferences, via preloadCache in main())
    // to pick the more likely loading state while the live one catches up.
    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (session.cachedHasPendingRequest) ...[
                const Icon(Icons.hourglass_top_rounded,
                    size: 34, color: AppColors.tertiary),
                const SizedBox(height: 14),
              ],
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    if (user.hasPendingRoleRequest) {
      return PendingApprovalScreen(user: user);
    }

    return const MainScreen();
  }
}
