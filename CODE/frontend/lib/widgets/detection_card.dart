import 'dart:io';

import 'package:flutter/material.dart';

import '../model/detection_result.dart';

class DetectionCard extends StatelessWidget {
  final DetectionResult result;
  final VoidCallback? onTap;

  const DetectionCard({super.key, required this.result, this.onTap});

  Color _severityColor(String s) {
    if (s == "Severe") return Colors.red.shade600;
    if (s == "Moderate") return Colors.orange.shade700;
    return Colors.green.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: result.image != null
              ? Image.file(
                  File(result.image!.path),
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                )
              : Container(width: 60, height: 60, color: Colors.grey[200]),
        ),
        title: Text(
          "${result.species} • ${result.disease}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text("${result.time.toLocal().toString().split('.')[0]}"),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${result.confidence.toStringAsFixed(0)}%",
              style: TextStyle(
                color: _severityColor(result.severity),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _severityColor(result.severity).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                result.severity,
                style: TextStyle(
                  color: _severityColor(result.severity),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
