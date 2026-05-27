import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import '../home/home_screen.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/shared_widgets.dart';
import 'register_screen.dart';
import 'onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthRepository();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _usernameError;
  String? _passwordError;
  String _errorMessage = '';

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _usernameError = username.isEmpty ? 'Required' : null;
      _passwordError = password.isEmpty ? 'Required' : null;
      _errorMessage = '';
    });

    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final cred = await _authService.loginWithUsername(
        username: username,
        password: password,
      );
      if (mounted) {
        final userDoc = await _authService.getUserProfile(cred.user!.uid);
        if (!mounted) return;
        final isFirstTime = userDoc?.isFirstTime ?? false;
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => isFirstTime ? const OnboardingScreen() : const HomeScreen(),
          ),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _authError(e.code));
    } catch (e) {
      if (mounted) setState(() => _errorMessage = _generalError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final cred = await _authService.signInWithGoogle();
      if (mounted) {
        final userDoc = await _authService.getUserProfile(cred.user!.uid);
        if (!mounted) return;
        final isFirstTime = userDoc?.isFirstTime ?? false;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => isFirstTime ? const OnboardingScreen() : const HomeScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Google sign-in failed.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this username.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid username or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return 'Login failed ($code). Please try again.';
    }
  }

  String _generalError(String raw) {
    if (raw.contains('username-not-found')) {
      return 'No account found with this username.';
    }
    return 'Login failed. Please try again.';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Decorative Background ───────────────────────────
          Positioned(
            top: -size.height * 0.1,
            right: -size.width * 0.2,
            child: _BlurCircle(
              size: 300,
              color: AppTheme.primaryGold.withValues(alpha: 0.15),
            ),
          ),
          Positioned(
            bottom: -size.height * 0.05,
            left: -size.width * 0.1,
            child: _BlurCircle(
              size: 250,
              color: AppTheme.accentPurple.withValues(alpha: 0.1),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // ── Logo & title ────────────────────────────
                    Hero(
                      tag: 'app_logo',
                      child: GlassContainer(
                        padding: const EdgeInsets.all(20),
                        borderRadius: 100,
                        color: cs.primary.withValues(alpha: 0.1),
                        child: Icon(Icons.shield_rounded, size: 64, color: cs.primary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'CrypTransfer',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Secure, Encrypted, Professional',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // ── Login Form ──────────────────────────────
                    GlassContainer(
                      padding: const EdgeInsets.all(24),
                      borderRadius: 28,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sign In',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 28),
                          TextField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                              errorText: _usernameError,
                              filled: true,
                              fillColor: cs.onSurface.withValues(alpha: 0.03),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                              errorText: _passwordError,
                              filled: true,
                              fillColor: cs.onSurface.withValues(alpha: 0.03),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined, size: 20),
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          if (_errorMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                _errorMessage,
                                style: TextStyle(color: cs.error, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),

                          _isLoading
                            ? const Center(child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(),
                              ))
                            : CrypButton(
                                label: const Text('Login'),
                                color: cs.primary,
                                onPressed: _login,
                              ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text('OR', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5))),
                            ],
                          ),
                          const SizedBox(height: 24),
                          CrypButton(
                            onPressed: _isLoading ? null : _loginWithGoogle,
                            icon: const _GoogleGIcon(),
                            label: const Text('Sign in with Google'),
                            color: Theme.of(context).colorScheme.secondary,
                            height: 48,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Register link ───────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("New here?",
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RegisterScreen()),
                          ),
                          child: Text(
                            'Create Account',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            color: Color(0xFF4285F4),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}
