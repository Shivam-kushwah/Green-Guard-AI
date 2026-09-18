import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frontend/screens/scan_camera_screen.dart';

import '../utils/colors.dart';
import '../services/session.dart';
import 'expert_queue_screen.dart';
import 'home_screen.dart';
import 'hotspot_map_screen.dart';
import 'my_reviews_screen.dart';
import 'officer_dashboard_screen.dart';
import 'profile_screen.dart';

class DiagnosisItem {
  final String name;
  final String plant;
  final String time;
  final String imageUrl;
  final List<Color> severityDots;

  const DiagnosisItem({
    required this.name,
    required this.plant,
    required this.time,
    required this.imageUrl,
    required this.severityDots,
  });
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// Index into [_tabs]. Scan is not a tab - it pushes a full-screen route -
  /// so it is excluded here rather than being mapped around, which is what
  /// made the previous index handling hard to follow.
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    // The role can change under the user when an admin verifies them, so the
    // nav has to rebuild rather than being fixed at first build.
    Session.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    Session.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      // Drop back to Home if the current tab no longer exists for this role.
      if (_selectedTab >= _tabs.length) _selectedTab = 0;
    });
  }

  /// Verified agronomists get the review queue where a farmer gets My Cases.
  /// Same binary, same slot - only the destination differs.
  bool get _isReviewer => Session.instance.canReview;

  /// Officers get the surveillance dashboard in the slot a farmer uses for
  /// their own cases - the roles never need both at once.
  bool get _isOfficer => Session.instance.canViewDashboard;

  List<Widget> get _tabs => [
    const HomeScreen(),
    const HotspotMapScreen(),
    if (_isOfficer)
      const OfficerDashboardScreen()
    else if (_isReviewer)
      const ExpertQueueScreen()
    else
      const MyReviewsScreen(),
    const ProfileScreen(),
  ];

  void _onNavTap(_NavDestination dest) {
    if (dest == _NavDestination.scan) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanCameraScreen()),
      );
      return;
    }
    setState(() => _selectedTab = dest.tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,

      // IndexedStack keeps each tab alive, so returning to the map does not
      // refetch Firestore and re-centre the camera every time.
      body: IndexedStack(index: _selectedTab, children: _tabs),

      bottomNavigationBar: _BottomNavBar(
        selectedTab: _selectedTab,
        isReviewer: _isReviewer,
        isOfficer: _isOfficer,
        onTap: _onNavTap,
      ),
    );
  }
}

/// What the bar can do. Naming these avoids the magic-number remapping the
/// old switch relied on.
enum _NavDestination {
  home(0, Icons.home_rounded, 'Home'),
  map(1, Icons.public_rounded, 'Map'),
  scan(-1, Icons.camera_alt_outlined, 'Scan'),
  cases(2, Icons.support_agent_rounded, 'Cases'),
  profile(3, Icons.person_outline_rounded, 'Profile');

  const _NavDestination(this.tabIndex, this.icon, this.label);

  /// -1 for destinations that push a route instead of switching tab.
  final int tabIndex;
  final IconData icon;
  final String label;

  bool get isTab => tabIndex >= 0;

  /// The third slot changes meaning with the role: farmers see their own
  /// cases, agronomists a review queue, officers the state dashboard.
  String labelFor({required bool isReviewer, required bool isOfficer}) {
    if (this != _NavDestination.cases) return label;
    if (isOfficer) return 'Dashboard';
    if (isReviewer) return 'Review';
    return label;
  }

  IconData iconFor({required bool isReviewer, required bool isOfficer}) {
    if (this != _NavDestination.cases) return icon;
    if (isOfficer) return Icons.insights_rounded;
    if (isReviewer) return Icons.fact_check_outlined;
    return icon;
  }
}

class _BottomNavBar extends StatelessWidget {
  final int selectedTab;
  final bool isReviewer;
  final bool isOfficer;
  final ValueChanged<_NavDestination> onTap;

  const _BottomNavBar({
    required this.selectedTab,
    required this.isReviewer,
    required this.isOfficer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.navBarBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),

          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),

          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final dest in _NavDestination.values)
                  _NavItem(
                    icon: dest.iconFor(
                      isReviewer: isReviewer,
                      isOfficer: isOfficer,
                    ),
                    label: dest.labelFor(
                      isReviewer: isReviewer,
                      isOfficer: isOfficer,
                    ),
                    // Scan opens a route rather than a tab, so it never
                    // shows as the current destination.
                    isActive: dest.isTab && dest.tabIndex == selectedTab,
                    onTap: () => onTap(dest),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.surfaceContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive
                  ? AppColors.primary
                  : AppColors.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: isActive
                    ? AppColors.primary
                    : AppColors.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
