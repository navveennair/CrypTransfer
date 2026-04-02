import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/key_repository.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

/// Checks auth state on startup, wipes RSA session keys, then routes to
/// HomeScreen or LoginScreen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _securing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Wait for Firebase to restore persisted auth state
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;

    if (user == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    setState(() => _securing = true);
    try {
      await KeyRepository().wipeAllSessionKeys(user.uid);
    } catch (_) {
      // Non-fatal: proceed even if wipe partially fails
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_securing) ...[
              const SizedBox(height: 16),
              Text(
                'Securing session...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
