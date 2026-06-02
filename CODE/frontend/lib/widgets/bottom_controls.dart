import 'package:flutter/material.dart';

class BottomControls extends StatelessWidget {
  const BottomControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        children: [
          const Text("Scan a plant",
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const Icon(Icons.image, color: Colors.white),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/result'),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green, width: 4),
                  ),
                ),
              ),
              const Icon(Icons.flash_on, color: Colors.white),
            ],
          )
        ],
      ),
    );
  }
}
