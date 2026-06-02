import 'dart:io';

import 'package:flutter/material.dart';

import '../model/detection_result.dart';

class DetectionDetailPage extends StatelessWidget {
  final DetectionResult result;

  const DetectionDetailPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F1),

      body: SafeArea(
        child: Column(
          children: [
            /// HEADER
            _buildHeader(context),

            /// CONTENT
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    /// IMAGE CARD
                    _imageCard(),

                    const SizedBox(height: 16),

                    /// DISEASE TITLE
                    _diseaseTitle(),

                    const SizedBox(height: 16),

                    /// RISK CARD
                    _riskCard(),

                    const SizedBox(height: 18),

                    /// TREATMENT CARD
                    _treatmentCard(),

                    const SizedBox(height: 20),

                    /// ACTION BUTTONS
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

  /// HEADER

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
        },
        child: Align(
          alignment: Alignment.topLeft,
          child: Icon(Icons.arrow_back_ios, color: Colors.black54),
        ),
      ),
    );
  }

  /// IMAGE CARD

  Widget _imageCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),

      child: Stack(
        children: [
          Image.file(
            File(result.imagePath),
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),

          Positioned(
            bottom: 12,
            left: 12,

            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),

              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),

              child: const Text(
                "IDENTIFIED",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// DISEASE TITLE

  Widget _diseaseTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          result.disease,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2E7D32),
          ),
        ),

        const SizedBox(height: 4),

        Text(
          result.species,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ],
    );
  }

  /// RISK CARD

  Widget _riskCard() {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              const Text(
                "RISK LIFE PREDICTION",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),

              Text(
                "${result.severity} Risk",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          /// RISK BAR
          ClipRRect(
            borderRadius: BorderRadius.circular(6),

            child: LinearProgressIndicator(
              value: result.confidence / 100,

              minHeight: 8,

              backgroundColor: Colors.grey.shade300,

              color: Colors.orange,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            "Current condition suggests ${result.confidence.toStringAsFixed(0)}% stability. Immediate intervention can restore full vitality within 14 days.",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// TREATMENT CARD

  Widget _treatmentCard() {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: const [
              Icon(Icons.health_and_safety, color: Colors.green),

              SizedBox(width: 8),

              Text(
                "Treatment and Prevention",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            result.recommendation,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// BUTTONS

  Widget _actionButtons(BuildContext context) {
    return Column(
      children: [
        /// RESCAN
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

            onPressed: () {
              Navigator.pop(context);
            },

            child: const Text(
              "RE-SCAN",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        /// SHARE
        SizedBox(
          width: double.infinity,

          child: OutlinedButton.icon(
            icon: const Icon(Icons.share),

            label: const Text("SHARE REPORT"),

            onPressed: () {},

            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
