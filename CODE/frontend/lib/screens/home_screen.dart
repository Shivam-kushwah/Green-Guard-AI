import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:frontend/model/diagnosis_history_model.dart';
import 'package:frontend/screens/diagnosis_history_screen.dart';
import 'package:frontend/screens/scan_camera_screen.dart';
import 'package:frontend/services/history_provider.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../utils/colors.dart';
import '../widgets/weather_risk_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // IndexedStack keeps this screen alive across tab switches, so this only
    // ever runs once per app session - HistoryProvider.reload() afterwards
    // (called by ScanReportingService right after a scan is saved) is what
    // actually keeps this screen current from then on.
    if (!HistoryProvider.instance.hasLoaded) {
      HistoryProvider.instance.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      extendBody: true,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 80),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _HeroBanner(),
                      const SizedBox(height: 16),

                      /// Weather-driven outbreak risk for this farm.
                      /// Renders nothing when there is no location fix or no
                      /// elevated risk, so it never pushes the scan button
                      /// down for no reason.
                      const WeatherRiskBanner(),
                      const SizedBox(height: 20),

                      _ScanSection(),
                      const SizedBox(height: 28),
                      Consumer<HistoryProvider>(
                        builder: (context, historyProvider, _) =>
                            _RecentDiagnosesSection(
                              history: historyProvider.items,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Positioned(top: 0, left: 0, right: 0, child: _TopAppBar()),
        ],
      ),
    );
  }
}

class _TopAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: const Text(
          'Green Guard',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            height: 1,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }
}

// ─── Hero Banner ─────────────────────────────────────────────────────────────
/// One slide: an image plus the localized caption it goes with.
///
/// Titles are resolved from AppLocalizations at build time (not stored here)
/// so the carousel keeps translating correctly if the language changes while
/// the app is open.
typedef _HeroSlide = ({String asset, String Function(AppLocalizations) title});

const _heroSlides = <_HeroSlide>[
  (asset: 'assets/images/farmer.jpeg', title: _heroTitle0),
  (asset: 'assets/images/hero_expert.jpg', title: _heroTitle1),
  (asset: 'assets/images/hero_spray.jpg', title: _heroTitle2),
];

String _heroTitle0(AppLocalizations l10n) => l10n.homeHeroTitle;
String _heroTitle1(AppLocalizations l10n) => l10n.homeHeroExpertTitle;
String _heroTitle2(AppLocalizations l10n) => l10n.homeHeroSprayTitle;

/// Auto-advancing carousel: the app's own on-device scan, the expert
/// validation layer, and weather-timed treatment - the three cloud/AI
/// features worth putting in front of a farmer before they even tap Scan.
class _HeroBanner extends StatefulWidget {
  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  static const _autoScrollInterval = Duration(seconds: 6);

  final _pageController = PageController();
  int _page = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _autoScrollTimer = Timer.periodic(_autoScrollInterval, (_) {
      if (!_pageController.hasClients) return;
      final next = (_page + 1) % _heroSlides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
        topRight: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _heroSlides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Image.asset(
                _heroSlides[i].asset,
                fit: BoxFit.cover,
                // Displayed at up to full screen width - well above thumbnail
                // size, but the source photos are still far larger than any
                // phone screen, so this caps the decode target sensibly.
                cacheWidth: 900,
              ),
            ),
            // Gradient overlay
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC171D14)],
                    stops: [0.4, 1.0],
                  ),
                ),
              ),
            ),
            // Text + dots
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _heroSlides[_page].title(l10n),
                        key: ValueKey(_page),
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(_heroSlides.length, (i) {
                        final active = i == _page;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: active ? 24 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Scan Section ─────────────────────────────────────────────────────────────
class _ScanSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon box
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F171D14),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.filter_center_focus_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.homeScanCardTitle,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.onSurface,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!.homeScanCardSubtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Scan Now button
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ),
                borderRadius: BorderRadius.circular(99),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x401B6D24),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScanCameraScreen(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.homeScanNow,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Diagnoses Section ─────────────────────────────────────────────────
class _RecentDiagnosesSection extends StatelessWidget {
  List<DiagnosisHistory> history;
  _RecentDiagnosesSection({required this.history});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AppLocalizations.of(context)!.homeRecentDiagnoses,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              child: Text(
                AppLocalizations.of(context)!.homeViewAll,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // List
        ...history
            .take(3)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),

                child: _DiagnosisCard(history: item),
              ),
            ),
      ],
    );
  }
}

class _DiagnosisCard extends StatelessWidget {
  final DiagnosisHistory history;

  const _DiagnosisCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(history.epochTime);

    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        borderRadius: BorderRadius.circular(16),

        onTap: () {
          /// Later open result screen again
        },

        child: Padding(
          padding: const EdgeInsets.all(14),

          child: Row(
            children: [
              /// IMAGE
              ClipRRect(
                borderRadius: BorderRadius.circular(12),

                child: Image.file(
                  File(history.imagePath),

                  width: 64,
                  height: 64,

                  fit: BoxFit.cover,
                  cacheWidth: 128,
                  cacheHeight: 128,
                ),
              ),

              const SizedBox(width: 14),

              /// TEXT
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      history.diagnosis,

                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        const Icon(
                          Icons.eco_outlined,
                          size: 13,
                          color: AppColors.onSurfaceVariant,
                        ),

                        const SizedBox(width: 3),

                        Text(
                          history.plantName,

                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              /// DATE
              Text(
                "${date.day}/${date.month}",

                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,

                  color: AppColors.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
