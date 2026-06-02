import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frontend/screens/scan_camera_screen.dart';

import '../utils/colors.dart';
import 'home_screen.dart';
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
  int _selectedIndex = 0;

  /// Only Home + Profile here
  final List<Widget> _screens = [const HomeScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,

      body: _screens[_selectedIndex],

      bottomNavigationBar: _BottomNavBar(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          /// Scan pressed
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScanCameraScreen()),
            );

            return;
          }

          /// Home
          if (index == 0) {
            setState(() {
              _selectedIndex = 0;
            });
          }

          /// Profile
          if (index == 2) {
            setState(() {
              _selectedIndex = 1;
            });
          }
        },
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNavBar({required this.selectedIndex, required this.onTap});

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
                /// HOME
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isActive: selectedIndex == 0,
                  onTap: () => onTap(0),
                ),

                /// SCAN
                _NavItem(
                  icon: Icons.camera_alt_outlined,
                  label: 'Scan',

                  /// Scan is never "active"
                  isActive: false,

                  onTap: () => onTap(1),
                ),

                /// PROFILE
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  isActive: selectedIndex == 1,
                  onTap: () => onTap(2),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
