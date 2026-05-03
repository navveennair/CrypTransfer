import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/utils/theme_service.dart';
import '../../core/constants/firebase_constants.dart';
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [
                  _ThemePickerPage(cs: cs),
                  const _TutorialPage(
                    title: 'Secure Handshake',
                    description: 'CrypTransfer uses RSA-2048 end-to-end encryption. Before any transfer, a secure handshake establishes an encrypted tunnel known only to you and the recipient.',
                    icon: Icons.handshake_rounded,
                  ),
                  const _TutorialPage(
                    title: 'Zero Remanence',
                    description: 'Your privacy is our priority. Once a transfer is complete or a session ends, all temporary keys and buffers are cryptographically wiped from both devices and servers.',
                    icon: Icons.security_rounded,
                  ),
                ],
              ),
            ),
            _buildBottomBar(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Dots
          Row(
            children: List.generate(3, (index) => _buildDot(index, cs)),
          ),
          
          // Next / Finish button
          GlassButton(
            label: Text(_currentPage == 2 ? 'Finish' : 'Next'),
            color: cs.primary,
            onPressed: () {
              if (_currentPage < 2) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                );
              } else {
                _completeOnboarding();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index ? cs.primary : cs.outlineVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection(FirebaseConstants.users)
          .doc(uid)
          .update({'isFirstTime': false});
    }
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }
}

class _ThemePickerPage extends StatelessWidget {
  final ColorScheme cs;
  const _ThemePickerPage({required this.cs});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Choose your vibe',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a theme that suits you best. You can always change this later in settings.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 48),
          _ThemeCard(
            label: 'Light Mode',
            icon: Icons.light_mode_rounded,
            isSelected: themeService.themeMode == ThemeMode.light,
            onTap: () => themeService.setThemeMode(ThemeMode.light),
            cs: cs,
          ),
          const SizedBox(height: 16),
          _ThemeCard(
            label: 'Dark Mode',
            icon: Icons.dark_mode_rounded,
            isSelected: themeService.themeMode == ThemeMode.dark,
            onTap: () => themeService.setThemeMode(ThemeMode.dark),
            cs: cs,
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _ThemeCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary.withValues(alpha: 0.1) : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? cs.primary : cs.onSurfaceVariant, size: 28),
            const SizedBox(width: 16),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isSelected ? cs.primary : cs.onSurface,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

class _TutorialPage extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const _TutorialPage({
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 80, color: cs.primary),
          ),
          const SizedBox(height: 48),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: cs.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
