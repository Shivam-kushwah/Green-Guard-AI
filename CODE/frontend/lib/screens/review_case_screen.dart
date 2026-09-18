import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/disease_kb.dart';
import '../model/scan_record.dart';
import '../services/expert_service.dart';
import '../services/session.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// Where an agronomist rules on one case.
///
/// The verdict is binary by design - confirm or correct - because an ambiguous
/// third option would be worthless as training data. Free-text advice is
/// captured separately and goes to the farmer, not into the label.
class ReviewCaseScreen extends StatefulWidget {
  final ScanRecord scan;

  const ReviewCaseScreen({super.key, required this.scan});

  @override
  State<ReviewCaseScreen> createState() => _ReviewCaseScreenState();
}

class _ReviewCaseScreenState extends State<ReviewCaseScreen> {
  final _noteController = TextEditingController();

  /// null until the agronomist picks. Deliberately not defaulted to "confirm":
  /// a pre-selected agree button is exactly how rubber-stamping happens, and
  /// rubber-stamped labels would poison the training set.
  bool? _agrees;

  String? _correctedSpecies;
  String? _correctedDisease;

  bool _submitting = false;
  String? _error;

  ScanRecord get scan => widget.scan;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_agrees == null) return false;
    if (_agrees == false &&
        (_correctedSpecies == null || _correctedDisease == null)) {
      return false;
    }
    return _noteController.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    final expert = Session.instance.user;
    if (expert == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ExpertService.instance.submitVerdict(
        expert: expert,
        scanId: scan.id,
        agreesWithAi: _agrees!,
        correctedSpecies: _correctedSpecies,
        correctedDisease: _correctedDisease,
        note: _noteController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verdict sent to the farmer')),
      );
    } on ReviewException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not send the verdict: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = DiseaseKb.resolve(scan.species, scan.disease);
    final resolved = scan.reviewStatus.isResolved;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Review Case',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _photo(),
          const SizedBox(height: 16),
          _aiClaimCard(info),
          const SizedBox(height: 16),
          _contextCard(),

          if (resolved) ...[
            const SizedBox(height: 16),
            _existingVerdict(),
          ] else ...[
            const SizedBox(height: 20),
            _verdictPicker(),
            if (_agrees == false) ...[
              const SizedBox(height: 16),
              _correctionPicker(),
            ],
            const SizedBox(height: 16),
            _noteField(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBox(_error!),
            ],
            const SizedBox(height: 20),
            _submitButton(),
          ],
        ],
      ),
    );
  }

  Widget _photo() {
    final b64 = scan.imageBase64;
    if (b64 == null || b64.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(
          child: Text(
            'No photo attached to this case',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.memory(
        base64Decode(b64),
        height: 260,
        width: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }

  Widget _aiClaimCard(DiseaseInfo info) {
    final lowCertainty = scan.confidence < AppConfig.lowCertaintyThreshold;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WHAT THE AI SAID',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            info.commonName,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          Text(
            '${scan.species} - ${info.pathogenName}',
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: scan.confidence / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation(
                      lowCertainty ? RiskColors.moderate : RiskColors.healthy,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                '${scan.confidence.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: lowCertainty
                      ? RiskColors.moderate
                      : RiskColors.healthy,
                ),
              ),
            ],
          ),
          if (lowCertainty) ...[
            const SizedBox(height: 8),
            const Text(
              'The model was unsure here. Your ruling on low-certainty cases '
              'is worth the most for improving it.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text(
            'Typical signs: ${info.symptoms}',
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contextRow(Icons.place_outlined, 'District',
            '${scan.district}, ${scan.region}'),
        const SizedBox(height: 8),
        _contextRow(
          Icons.schedule_rounded,
          'Submitted',
          scan.reviewRequestedAt == null
              ? 'Unknown'
              : _relativeTime(scan.reviewRequestedAt!),
        ),
        const SizedBox(height: 8),
        _contextRow(Icons.memory_rounded, 'Model', scan.modelVersion),
      ],
    ),
  );

  Widget _contextRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 15, color: AppColors.onSurfaceVariant),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      const Spacer(),
      Flexible(
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
      ),
    ],
  );

  Widget _verdictPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'YOUR VERDICT',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _verdictButton(
              selected: _agrees == true,
              color: RiskColors.healthy,
              icon: Icons.check_circle_outline,
              label: 'AI is correct',
              onTap: () => setState(() {
                _agrees = true;
                _correctedSpecies = null;
                _correctedDisease = null;
              }),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _verdictButton(
              selected: _agrees == false,
              color: RiskColors.high,
              icon: Icons.cancel_outlined,
              label: 'AI is wrong',
              onTap: () => setState(() => _agrees = false),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _verdictButton({
    required bool selected,
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: selected
            ? RiskColors.surfaceFor(color)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? color : AppColors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon,
              color: selected ? color : AppColors.onSurfaceVariant, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? color : AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _correctionPicker() {
    final species = DiseaseKb.allSpecies..sort();
    final diseases = _correctedSpecies == null
        ? <DiseaseInfo>[]
        : DiseaseKb.all
              .where((d) => d.species == _correctedSpecies)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WHAT IS IT ACTUALLY?',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'This becomes ground truth for retraining, so pick carefully.',
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: species
              .map(
                (s) => ChoiceChip(
                  label: Text(s, style: const TextStyle(fontSize: 12.5)),
                  selected: _correctedSpecies == s,
                  onSelected: (_) => setState(() {
                    _correctedSpecies = s;
                    _correctedDisease = null;
                  }),
                ),
              )
              .toList(),
        ),
        if (diseases.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: diseases
                .map(
                  (d) => ChoiceChip(
                    label: Text(
                      d.commonName,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    selected: _correctedDisease == d.disease,
                    onSelected: (_) =>
                        setState(() => _correctedDisease = d.disease),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _noteField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'ADVICE FOR THE FARMER',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _noteController,
        maxLines: 4,
        maxLength: 600,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'What should they do, and by when? Be specific about '
              'dose and timing.',
          hintStyle: const TextStyle(fontSize: 12.5),
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
        ),
      ),
    ],
  );

  Widget _submitButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.outlineVariant,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      onPressed: (_canSubmit && !_submitting) ? _submit : null,
      child: _submitting
          ? const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              'SEND VERDICT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
    ),
  );

  Widget _existingVerdict() {
    final corrected = scan.reviewStatus == ReviewStatus.corrected;
    final color = corrected ? RiskColors.high : RiskColors.healthy;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: RiskColors.surfaceFor(color),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                corrected ? Icons.edit_note_rounded : Icons.verified_outlined,
                size: 19,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                corrected ? 'Corrected' : 'Confirmed',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          if (corrected) ...[
            const SizedBox(height: 8),
            Text(
              'Actual: ${DiseaseKb.resolve(scan.expertSpecies ?? scan.species, scan.expertDisease ?? "").commonName}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (scan.expertNote != null) ...[
            const SizedBox(height: 8),
            Text(
              scan.expertNote!,
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'By ${scan.expertName ?? "an agronomist"}'
            '${scan.expertQualification == null ? "" : ", ${scan.expertQualification}"}',
            style: const TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: RiskColors.surfaceFor(AppColors.error),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 17, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: child,
  );

  static String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
