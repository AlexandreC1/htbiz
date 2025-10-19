import 'package:flutter/material.dart';
import '../../main.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person, size: 100),
            const SizedBox(height: 20),
            Text(
              user?.email ?? 'Guest',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),
            const Text('Profile editing coming soon!'),
          ],
        ),
      ),
    );
  }
}
