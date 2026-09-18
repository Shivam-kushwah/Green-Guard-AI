import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/disease_kb.dart';
import '../model/app_user.dart';
import '../model/scan_record.dart';
import '../services/expert_service.dart';
import '../services/session.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';
import 'review_case_screen.dart';

/// The agronomist's inbox.
///
/// Same app binary as the farmer sees - the role on the user profile decides
/// which screen they land on. That was a deliberate call over building a
/// second app: one codebase, one release, and the data layer is written once.
class ExpertQueueScreen extends StatefulWidget {
  const ExpertQueueScreen({super.key});

  @override
  State<ExpertQueueScreen> createState() => _ExpertQueueScreenState();
}

class _ExpertQueueScreenState extends State<ExpertQueueScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    // No Cloud Scheduler on the free tier, so overdue cases are swept when a
    // reviewer opens the queue.
    ExpertService.instance.expireOverdueCases();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;

    if (user == null) {
      return const _Gate(
        icon: Icons.login_rounded,
        title: 'Sign in required',
        body: 'Sign in with your agronomist account to see the review queue.',
      );
    }

    if (!user.role.canReview) {
      return const _Gate(
        icon: Icons.badge_outlined,
        title: 'Agronomist access only',
        body:
            'This queue is for verified agronomists. If you are a KVK officer '
            'or agri-university staff member, ask an administrator to upgrade '
            'your account.',
      );
    }

    if (!user.verified) {
      return const _Gate(
        icon: Icons.hourglass_empty_rounded,
        title: 'Verification pending',
        body:
            'Your agronomist account is not verified yet. An administrator '
            'must confirm your credentials before you can rule on cases - a '
            'farmer acts on what you say, so the check matters.',
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Review Queue',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'WAITING'),
            Tab(text: 'MY VERDICTS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _QueueList(
            stream: ExpertService.instance.watchQueue(),
            emptyIcon: Icons.inbox_outlined,
            emptyTitle: 'Nothing waiting',
            emptyBody: 'New cases from farmers will appear here.',
            showCountdown: true,
          ),
          _QueueList(
            stream: ExpertService.instance.watchMyVerdicts(user.uid),
            emptyIcon: Icons.fact_check_outlined,
            emptyTitle: 'No verdicts yet',
            emptyBody: 'Cases you rule on will be listed here.',
            showCountdown: false,
          ),
        ],
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  final Stream<List<ScanRecord>> stream;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final bool showCountdown;

  const _QueueList({
    required this.stream,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.showCountdown,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScanRecord>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Gate(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load cases',
            body: snap.error.toString(),
          );
        }

        final cases = snap.data ?? const <ScanRecord>[];
        if (cases.isEmpty) {
          return _Gate(icon: emptyIcon, title: emptyTitle, body: emptyBody);
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          itemCount: cases.length,
          itemBuilder: (_, i) => _CaseCard(
            scan: cases[i],
            showCountdown: showCountdown,
          ),
        );
      },
    );
  }
}

class _CaseCard extends StatelessWidget {
  final ScanRecord scan;
  final bool showCountdown;

  const _CaseCard({required this.scan, required this.showCountdown});

  @override
  Widget build(BuildContext context) {
    final info = DiseaseKb.resolve(scan.species, scan.disease);
    final hoursLeft = scan.slaHoursRemaining(AppConfig.expertSlaWindow);
    final overdue = hoursLeft != null && hoursLeft < 0;
    final urgent = hoursLeft != null && hoursLeft >= 0 && hoursLeft < 6;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: overdue
              ? RiskColors.severe.withValues(alpha: 0.5)
              : AppColors.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReviewCaseScreen(scan: scan)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumbnail(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.commonName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${scan.species} - AI ${scan.confidence.toStringAsFixed(0)}% certain',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scan.confidence <
                                  AppConfig.lowCertaintyThreshold
                              ? RiskColors.moderate
                              : AppColors.onSurfaceVariant,
                          fontWeight: scan.confidence <
                                  AppConfig.lowCertaintyThreshold
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 12, color: AppColors.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              scan.district,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      if (showCountdown)
                        _slaChip(hoursLeft, overdue, urgent)
                      else
                        _verdictChip(),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnail() {
    final b64 = scan.imageBase64;
    if (b64 == null || b64.isEmpty) {
      return Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(Icons.image_not_supported_outlined,
            size: 20, color: AppColors.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Image.memory(
        base64Decode(b64),
        width: 62,
        height: 62,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Container(
          width: 62,
          height: 62,
          color: AppColors.surfaceContainer,
        ),
      ),
    );
  }

  Widget _slaChip(double? hoursLeft, bool overdue, bool urgent) {
    if (hoursLeft == null) return const SizedBox.shrink();

    final color = overdue
        ? RiskColors.severe
        : urgent
        ? RiskColors.high
        : RiskColors.healthy;

    final text = overdue
        ? 'Overdue by ${(-hoursLeft).toStringAsFixed(0)} h'
        : hoursLeft < 1
        ? '${(hoursLeft * 60).toStringAsFixed(0)} min left'
        : '${hoursLeft.toStringAsFixed(0)} h left';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: RiskColors.surfaceFor(color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            overdue ? Icons.error_outline : Icons.schedule_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verdictChip() {
    final corrected = scan.reviewStatus == ReviewStatus.corrected;
    final color = corrected ? RiskColors.high : RiskColors.healthy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: RiskColors.surfaceFor(color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        corrected
            ? 'Corrected to ${scan.expertDisease}'
            : 'Confirmed AI diagnosis',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Gate({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
