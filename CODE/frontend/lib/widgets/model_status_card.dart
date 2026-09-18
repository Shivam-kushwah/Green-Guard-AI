import 'package:flutter/material.dart';

import '../services/model_update_service.dart';
import '../services/tf_service.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// Shows which model is running and offers an update when one is published.
///
/// The learning loop is otherwise invisible to the person using the app, and
/// an AI that silently changes its mind about a diagnosis is unsettling. This
/// makes the version explicit and puts the update in the user's hands.
class ModelStatusCard extends StatefulWidget {
  const ModelStatusCard({super.key});

  @override
  State<ModelStatusCard> createState() => _ModelStatusCardState();
}

class _ModelStatusCardState extends State<ModelStatusCard> {
  String _activeVersion = '...';
  int _classes = 0;
  ModelRelease? _available;

  bool _checking = true;
  bool _downloading = false;
  double _progress = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);

    final version = await ModelUpdateService.instance.activeVersion();
    final update = await ModelUpdateService.instance.checkForUpdate();

    if (!mounted) return;
    setState(() {
      _activeVersion = version;
      _classes = TfService.instance.numClasses;
      _available = update;
      _checking = false;
    });
  }

  Future<void> _update() async {
    final release = _available;
    if (release == null) return;

    setState(() {
      _downloading = true;
      _progress = 0;
      _message = null;
    });

    final ok = await ModelUpdateService.instance.downloadAndActivate(
      release,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _downloading = false;
      _message = ok
          ? 'Updated to ${release.version}'
          : 'Update failed. The previous model is still in use.';
    });
    if (ok) _check();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F0E7),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.memory_rounded,
                    color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detection model',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _checking
                          ? 'Checking...'
                          : '$_activeVersion  -  $_classes classes',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_checking && _available == null)
                IconButton(
                  tooltip: 'Check for updates',
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  onPressed: _check,
                ),
            ],
          ),

          if (_available != null) ...[
            const SizedBox(height: 12),
            _updateBlock(_available!),
          ],

          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _updateBlock(ModelRelease r) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version ${r.version} available',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),

          // State plainly what improved and on what evidence, rather than
          // asking the farmer to trust an unexplained "improved model".
          Text(
            r.expertSamplesUsed > 0
                ? 'Retrained with ${r.expertSamplesUsed} cases checked by '
                      'agronomists in the field.'
                : 'Retrained model.',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            r.fieldAgreement != null
                ? 'Agrees with experts ${(r.fieldAgreement! * 100).round()}% '
                      'of the time  -  ${r.sizeMb.toStringAsFixed(1)} MB'
                : 'Validation accuracy '
                      '${(r.validationAccuracy * 100).round()}%  -  '
                      '${r.sizeMb.toStringAsFixed(1)} MB',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 11),
          if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 6,
                backgroundColor: Colors.white,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloading ${(_progress * 100).round()}%',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _update,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: Text(
                  'UPDATE (${r.sizeMb.toStringAsFixed(1)} MB)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 7),
          Row(
            children: [
              Icon(Icons.wifi_rounded,
                  size: 12, color: RiskColors.inkOn(RiskColors.moderate)),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'Downloads once. Detection stays fully offline afterwards.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
