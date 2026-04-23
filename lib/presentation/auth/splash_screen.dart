import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import '../../data/repositories/key_repository.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

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
    await Future.delayed(const Duration(milliseconds: 1500));
    final user = await FirebaseAuth.instance.authStateChanges().first;
    if (!mounted) return;

    if (user == null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const LoginScreen(),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
      return;
    }

    setState(() => _securing = true);
    try {
      await KeyRepository().wipeAllSessionKeys(user.uid);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -size.height * 0.1,
            right: -size.width * 0.2,
            child: _BlurCircle(size: 300, color: cs.primary.withValues(alpha: 0.15)),
          ),
          Positioned(
            bottom: -size.height * 0.05,
            left: -size.width * 0.1,
            child: _BlurCircle(size: 250, color: cs.secondary.withValues(alpha: 0.1)),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: 'app_logo',
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary.withValues(alpha: 0.2), width: 2),
                    ),
                    child: Icon(Icons.shield_rounded, size: 80, color: cs.primary),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'CrypTransfer',
                  style: GoogleFonts.poppins(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 140,
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        backgroundColor: cs.primary.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        borderRadius: BorderRadius.circular(10),
                        minHeight: 3,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _securing ? 'Securing session...' : 'Initializing...',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _BlurCircle({required this.size, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}
