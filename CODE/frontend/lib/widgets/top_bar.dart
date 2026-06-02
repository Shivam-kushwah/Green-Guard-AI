import 'package:flutter/material.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(Icons.arrow_back, color: Colors.white),
          const Text("Plant Scanner",
              style: TextStyle(color: Colors.white, fontSize: 20)),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/history'),
            child: const Icon(Icons.history, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
