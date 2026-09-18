import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../model/detection_result.dart';
import '../services/expert_service.dart';
import '../services/tf_service.dart';
import '../utils/colors.dart';
import '../utils/risk_colors.dart';

/// Bottom sheet for sending a case to an agronomist.
///
/// Shows the sheet and returns true when the case was submitted.
Future<bool> showAskExpertSheet(
  BuildContext context, {
  required String scanId,
  required DetectionResult result,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AskExpertSheet(scanId: scanId, result: result),
  );
  return sent ?? false;
}

class _AskExpertSheet extends StatefulWidget {
  final String scanId;
  final DetectionResult result;

  const _AskExpertSheet({required this.scanId, required this.result});

  @override
  State<_AskExpertSheet> createState() => _AskExpertSheetState();
}

class _AskExpertSheetState extends State<_AskExpertSheet> {
  final _noteController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      // Compressed on a background isolate - a 12 MP photo would blow past
      // Firestore's 1 MB document limit and drop frames while encoding.
      final b64 = await TfService.compressForUpload(
        File(widget.result.imagePath),
      );

      if (b64 == null) {
        throw const ReviewException(
          ReviewFailure.noImage,
          'Could not prepare the photo. Try scanning again.',
        );
      }

      await ExpertService.instance.submitForReview(
        scanId: widget.scanId,
        imageBase64: b64,
        farmerNote: _noteController.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on ReviewException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not send the case: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            const Text(
              'Ask an agronomist',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'A verified agronomist will look at your photo and confirm or '
              'correct the diagnosis.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Honest about what the window is and is not. Promising a
            // guaranteed reply would be a promise the software cannot keep.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RiskColors.surfaceFor(AppColors.tertiary),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 16, color: AppColors.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target reply time is '
                      '${AppConfig.expertSlaWindow.inHours} hours. You will '
                      'see the answer in the app - we will tell you if nobody '
                      'picks it up in time.',
                      style: const TextStyle(fontSize: 11.5, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _noteController,
              maxLines: 3,
              maxLength: 400,
              decoration: InputDecoration(
                hintText: 'Anything the agronomist should know? Crop stage, '
                    'what you have already sprayed, how much of the field is '
                    'affected.',
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

            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: RiskColors.surfaceFor(AppColors.error),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppColors.error),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'SEND FOR REVIEW',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Your photo and district are shared with the agronomist',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
