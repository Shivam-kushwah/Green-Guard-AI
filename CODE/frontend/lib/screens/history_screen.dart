import 'package:flutter/material.dart';

import '../widgets/detection_card.dart';
import 'home_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Center(
            child: const Text("History", style: TextStyle(color: Colors.grey)),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: recentDetections.isEmpty
              ? const Center(child: Text("No history yet."))
              : ListView.builder(
                  itemCount: recentDetections.length,
                  itemBuilder: (context, index) {
                    final r = recentDetections[index];
                    return DetectionCard(
                      result: r,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetectionDetailPage(result: r),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
