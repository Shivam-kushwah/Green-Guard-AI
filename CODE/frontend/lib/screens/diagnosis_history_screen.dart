import 'dart:io';

import 'package:flutter/material.dart';

import '../model/diagnosis_history_model.dart';
import '../services/history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<DiagnosisHistory> history = [];

  String selectedFilter = "All";

  final String username = "shivam";

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    history = await HistoryService.getHistory();

    setState(() {});
  }

  /// FILTER LOGIC

  List<DiagnosisHistory> get filteredHistory {
    if (selectedFilter == "Healthy") {
      return history.where((e) => e.result.toLowerCase() == "healthy").toList();
    }

    if (selectedFilter == "Diseased") {
      return history.where((e) => e.result.toLowerCase() != "healthy").toList();
    }

    return history;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF3EA),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              /// TITLE
              Center(
                child: const Text(
                  "History",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                "Tracking your botanical journey through scientific analysis.",
                style: TextStyle(color: Colors.black54),
              ),

              const SizedBox(height: 16),

              /// FILTER CHIPS
              Row(
                children: [
                  _filterChip("All"),
                  const SizedBox(width: 8),

                  _filterChip("Diseased"),
                  const SizedBox(width: 8),

                  _filterChip("Healthy"),
                ],
              ),

              const SizedBox(height: 16),

              /// LIST
              Expanded(
                child: filteredHistory.isEmpty
                    ? const Center(child: Text("No History Yet"))
                    : ListView.builder(
                        itemCount: filteredHistory.length,

                        itemBuilder: (context, index) {
                          final item = filteredHistory[index];

                          return _historyCard(item);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// FILTER CHIP

  Widget _filterChip(String title) {
    final isSelected = selectedFilter == title;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = title;
        });
      },

      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),

        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white,

          borderRadius: BorderRadius.circular(20),
        ),

        child: Text(
          title,

          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// HISTORY CARD

  Widget _historyCard(DiagnosisHistory item) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.epochTime);

    final severityColor = _severityColor(item.result);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),

      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),

      child: Row(
        children: [
          /// IMAGE
          ClipRRect(
            borderRadius: BorderRadius.circular(12),

            child: Image.file(
              File(item.imagePath),

              width: 70,
              height: 70,

              fit: BoxFit.cover,
            ),
          ),

          const SizedBox(width: 12),

          /// TEXT
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                /// STATUS
                Text(
                  item.result.toUpperCase(),

                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: severityColor,
                  ),
                ),

                const SizedBox(height: 4),

                /// DISEASE
                Text(
                  item.diagnosis,

                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 2),

                /// PLANT
                Text(
                  item.plantName,

                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          /// DATE
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,

            children: [
              Text(
                "${date.day}/${date.month}/${date.year}",

                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.15),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Text(
                  item.result,

                  style: TextStyle(
                    color: severityColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// SEVERITY COLOR

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case "healthy":
        return Colors.green;

      case "moderate":
        return Colors.orange;

      case "severe":
        return Colors.red;

      default:
        return Colors.grey;
    }
  }
}
