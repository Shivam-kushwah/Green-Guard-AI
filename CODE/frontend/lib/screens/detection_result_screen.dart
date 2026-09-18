import 'dart:io';

import 'package:flutter/material.dart';

import '../data/disease_kb.dart';
import '../model/detection_result.dart';
import '../services/scan_reporting_service.dart';
import '../widgets/ask_expert_sheet.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

class DetectionDetailPage extends StatelessWidget {
  final DetectionResult result;

  /// Where the scan ended up - cloud id, district, map eligibility. Null when
  /// the screen is opened from history rather than straight after a scan.
  final ScanReport? report;

  const DetectionDetailPage({
    super.key,
    required this.result,
    this.report,
  });

  DiseaseInfo get info => result.info;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F1),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _imageCard(),
                    const SizedBox(height: 16),
                    _diseaseTitle(),
                    const SizedBox(height: 16),

                    // Shown first when the model is unsure: the farmer should
                    // read the caveat before the diagnosis, not after.
                    if (result.isLowCertainty) ...[
                      _uncertaintyCard(),
                      const SizedBox(height: 14),
                    ],

                    _assessmentCard(),
                    const SizedBox(height: 16),
                    _symptomsCard(),
                    const SizedBox(height: 16),
                    _treatmentCard(),

                    if (info.regionalNote != null) ...[
                      const SizedBox(height: 16),
                      _regionalCard(),
                    ],

                    // Expert review needs a cloud record to attach to, so it
                    // only appears once the scan actually reached Firestore.
                    if (report?.cloudId != null && !result.isHealthy) ...[
                      const SizedBox(height: 16),
                      _ExpertCta(
                        scanId: report!.cloudId!,
                        result: result,
                        recommended: result.shouldSeekExpert,
                      ),
                    ],

                    if (report != null) ...[
                      const SizedBox(height: 16),
                      _reportingStatus(),
                    ],

                    const SizedBox(height: 20),
                    _actionButtons(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Align(
          alignment: Alignment.topLeft,
          child: Icon(Icons.arrow_back_ios, color: Colors.black54),
        ),
      ),
    );
  }

  Widget _imageCard() {
    final threatColor = RiskColors.forThreat(info.threat);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Image.file(
            File(result.imagePath),
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 200,
              color: AppColors.surfaceContainer,
              child: const Center(
                child: Icon(Icons.image_not_supported_outlined, size: 32),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: result.isHealthy ? RiskColors.healthy : threatColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                result.isHealthy ? 'HEALTHY' : '${info.threat.label.toUpperCase()} THREAT',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diseaseTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          info.commonName,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          info.pathogenName == '-'
              ? result.species
              : '${result.species}  -  ${info.pathogenName}',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  /// The two numbers that used to be conflated, now stated separately.
  ///
  /// Model certainty says how sure the classifier is. Threat level says how
  /// dangerous the disease is if it really is present. The old screen drove
  /// both from confidence, which meant a blurry photo of a dying plant read
  /// as "mild" and a sharp photo of a slightly spotted leaf read as "severe".
  Widget _assessmentCard() {
    final threatColor = RiskColors.forThreat(info.threat);
    final certaintyColor = result.isLowCertainty
        ? RiskColors.moderate
        : RiskColors.healthy;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ASSESSMENT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 14),

          _meterRow(
            label: 'Model certainty',
            value: result.confidence / 100,
            valueText: '${result.confidence.toStringAsFixed(0)}%',
            color: certaintyColor,
            hint: 'How sure the AI is about this identification',
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Threat level',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.isHealthy
                          ? 'No disease detected'
                          : 'How damaging this disease is if present',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: RiskColors.surfaceFor(threatColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.threat.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: threatColor,
                  ),
                ),
              ),
            ],
          ),

          if (info.notifiable) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: RiskColors.surfaceFor(RiskColors.severe),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  Icon(Icons.campaign_outlined,
                      size: 17, color: RiskColors.severe),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notifiable disease - your district agriculture office '
                      'should be told about this.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: RiskColors.severe,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _meterRow({
    required String label,
    required double value,
    required String valueText,
    required Color color,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: const TextStyle(fontSize: 11, color: Colors.black45),
        ),
      ],
    );
  }

  /// Shown when the classifier is not confident enough to be acted on.
  ///
  /// Spraying the wrong chemical costs a smallholder real money, so an unsure
  /// result has to say so plainly rather than presenting a guess as a finding.
  Widget _uncertaintyCard() {
    final runnerUp = result.runnerUp;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: RiskColors.surfaceFor(RiskColors.moderate),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: RiskColors.moderate.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  size: 19, color: RiskColors.moderate),
              const SizedBox(width: 8),
              Text(
                'The AI is not confident here',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: RiskColors.moderate.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'At ${result.confidence.toStringAsFixed(0)}% certainty this is a '
            'best guess, not a diagnosis. Retake the photo in daylight with a '
            'single leaf filling the frame, or send it to an agronomist '
            'before you spend money on treatment.',
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
          if (runnerUp != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alt_route_rounded,
                      size: 15, color: Colors.black54),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Could also be '
                      '${DiseaseKb.resolve(runnerUp.species, runnerUp.disease).commonName} '
                      '(${runnerUp.confidence.toStringAsFixed(0)}%)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _symptomsCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.visibility_outlined, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Check these signs',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          info.symptoms,
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      ],
    ),
  );

  Widget _treatmentCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.health_and_safety, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Treatment and prevention',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          info.treatment,
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text(
          'PREVENT IT NEXT SEASON',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          info.prevention,
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
      ],
    ),
  );

  Widget _regionalCard() => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(AppColors.tertiary),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.public, size: 17, color: AppColors.tertiary),
            SizedBox(width: 7),
            Text(
              'WHY THIS MATTERS HERE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.tertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          info.regionalNote!,
          style: const TextStyle(fontSize: 12.5, height: 1.5),
        ),
      ],
    ),
  );

  /// Tells the farmer what happened to their data. Silent data collection is
  /// not acceptable when the thing being collected is where their farm is.
  Widget _reportingStatus() {
    final r = report!;
    final String text;
    final IconData icon;

    if (r.cloudId == null) {
      text = 'Saved on this phone only. Sign in and allow location to add '
          'your scan to the district outbreak map.';
      icon = Icons.phone_android_rounded;
    } else if (r.excludedFromMap) {
      text = 'Saved to your history. Your location is outside Maharashtra, so '
          'it is not added to the state outbreak map.';
      icon = Icons.location_off_outlined;
    } else {
      text = 'Added to the ${r.district} outbreak map. Only your district is '
          'shared - never your exact field location.';
      icon = Icons.cloud_done_outlined;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.black45),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
    ),
    child: child,
  );

  Widget _actionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'RE-SCAN',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}


/// Call to action for the expert validation layer.
///
/// Promoted to a filled button when the result genuinely warrants a second
/// opinion - low model certainty, a critical threat, or a notifiable disease -
/// and left as a quiet outlined button otherwise. Pushing every farmer to the
/// queue for every scan would swamp the agronomists and make the 24-hour
/// target meaningless.
class _ExpertCta extends StatefulWidget {
  final String scanId;
  final DetectionResult result;
  final bool recommended;

  const _ExpertCta({
    required this.scanId,
    required this.result,
    required this.recommended,
  });

  @override
  State<_ExpertCta> createState() => _ExpertCtaState();
}

class _ExpertCtaState extends State<_ExpertCta> {
  bool _sent = false;

  Future<void> _ask() async {
    final sent = await showAskExpertSheet(
      context,
      scanId: widget.scanId,
      result: widget.result,
    );
    if (sent && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RiskColors.surfaceFor(RiskColors.healthy),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: RiskColors.healthy, size: 19),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Sent to an agronomist. You will see their answer here and in '
                'My Cases.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ),
          ],
        ),
      );
    }

    if (!widget.recommended) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _ask,
          icon: const Icon(Icons.support_agent_rounded, size: 19),
          label: const Text('Ask an agronomist'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: RiskColors.surfaceFor(RiskColors.moderate),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: RiskColors.moderate.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Get this confirmed before you spray',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            widget.result.isLowCertainty
                ? 'The AI is not confident enough for you to spend money on '
                      'this diagnosis.'
                : 'This disease moves fast and treatment is expensive - worth '
                      'a human check first.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _ask,
              icon: const Icon(Icons.support_agent_rounded, size: 19),
              label: const Text('ASK AN AGRONOMIST'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
