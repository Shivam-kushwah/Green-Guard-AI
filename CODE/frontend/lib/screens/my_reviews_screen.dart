import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/disease_kb.dart';
import '../model/scan_record.dart';
import '../services/expert_service.dart';
import '../services/session.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// The farmer's view of cases they sent for expert review.
class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'My Cases',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: user == null
          ? const _Empty(
              icon: Icons.login_rounded,
              title: 'Sign in to see your cases',
              body: 'Cases you send to an agronomist appear here.',
            )
          : StreamBuilder<List<ScanRecord>>(
              stream: ExpertService.instance.watchMyReviews(user.uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final cases = snap.data ?? const <ScanRecord>[];
                if (cases.isEmpty) {
                  return const _Empty(
                    icon: Icons.support_agent_rounded,
                    title: 'No cases yet',
                    body:
                        'After a scan you can send the photo to a verified '
                        'agronomist for a second opinion.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                  itemCount: cases.length,
                  itemBuilder: (_, i) => _ReviewCard(scan: cases[i]),
                );
              },
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final ScanRecord scan;

  const _ReviewCard({required this.scan});

  @override
  Widget build(BuildContext context) {
    final aiInfo = DiseaseKb.resolve(scan.species, scan.disease);
    final status = scan.reviewStatus;

    final (Color color, IconData icon, String label) = switch (status) {
      ReviewStatus.pending => (
        RiskColors.moderate,
        Icons.hourglass_top_rounded,
        'Waiting for an agronomist',
      ),
      ReviewStatus.confirmed => (
        RiskColors.healthy,
        Icons.verified_rounded,
        'Confirmed by an agronomist',
      ),
      ReviewStatus.corrected => (
        RiskColors.high,
        Icons.edit_note_rounded,
        'Corrected by an agronomist',
      ),
      ReviewStatus.expired => (
        RiskColors.unknown,
        Icons.timer_off_outlined,
        'No expert was available',
      ),
      ReviewStatus.none => (
        RiskColors.unknown,
        Icons.help_outline,
        'Not sent for review',
      ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 14, color: color),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'AI said: ${aiInfo.commonName}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (status == ReviewStatus.corrected) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Actually: ${DiseaseKb.resolve(scan.expertSpecies ?? scan.species, scan.expertDisease ?? "").commonName}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                    if (status == ReviewStatus.pending) ...[
                      const SizedBox(height: 4),
                      _countdown(),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (scan.expertNote != null && scan.expertNote!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: RiskColors.surfaceFor(color),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scan.expertNote!,
                    style: const TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '- ${scan.expertName ?? "Agronomist"}'
                    '${scan.expertQualification == null ? "" : ", ${scan.expertQualification}"}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // An expired case must not just go quiet - the farmer is waiting on
          // an answer that is not coming, and needs to be told what to do.
          if (status == ReviewStatus.expired) ...[
            const SizedBox(height: 10),
            const Text(
              'Nobody picked this up within the target window. Contact your '
              'local Krishi Vigyan Kendra, or re-send with a clearer photo.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countdown() {
    final hours = scan.slaHoursRemaining(AppConfig.expertSlaWindow);
    if (hours == null) return const SizedBox.shrink();

    final overdue = hours < 0;
    return Text(
      overdue
          ? 'Past the target reply time'
          : hours < 1
          ? 'About ${(hours * 60).toStringAsFixed(0)} minutes left'
          : 'About ${hours.toStringAsFixed(0)} hours left',
      style: const TextStyle(
        fontSize: 11,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  Widget _thumb() {
    final b64 = scan.imageBase64;
    if (b64 == null || b64.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.eco_outlined,
            size: 18, color: AppColors.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        base64Decode(b64),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Container(
          width: 56,
          height: 56,
          color: AppColors.surfaceContainer,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Empty({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
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
  );
}
