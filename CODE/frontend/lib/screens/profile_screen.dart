import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text(" ")),
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 42,
                backgroundImage: AssetImage(
                  'assets/images/man-user-color-icon.png',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Shivam Kushwah",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                "rudrashiva2731@gmail.com",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: true,
                onChanged: (v) {},
                title: const Text("Disease Alerts"),
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text("Settings"),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text("Credits"),
                onTap: () {
                  ShowCredit(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  "Logout",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  void ShowCredit(context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: const [
              Icon(Icons.code, color: Colors.green),
              SizedBox(width: 8),
              Text(
                "Developers",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: Text("Shivam Kushwah"),
              ),

              Divider(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Close",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
