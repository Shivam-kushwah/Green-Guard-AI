import 'package:flutter/material.dart';

class ScanBox extends StatelessWidget {
  const ScanBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.greenAccent, width: 3),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
