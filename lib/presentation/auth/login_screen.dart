import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../home/home_screen.dart';
import '../../data/repositories/auth_repository.dart';
import 'register_screen.dart';

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
  String _errorMessage = '';

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _authService.loginWithUsername(
        username: username,
        password: password,
      );
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
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

  /// Maps FirebaseAuthException codes to user-friendly messages.
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

  /// Maps non-Firebase exceptions (our own string codes) to messages.
  String _generalError(String raw) {
    if (raw.contains('username-not-found')) {
      return 'No account found with this username.';
    }
    if (raw.contains('firestore-permission-denied')) {
      return 'Database permission error. Check Firestore security rules.';
    }
    if (raw.contains('account-data-corrupted')) {
      return 'Account data is corrupted. Please re-register.';
    }
    if (raw.contains('firestore-error')) {
      return 'Database error. Check your connection and try again.';
    }
    if (raw.contains('network')) {
      return 'Network error. Check your connection.';
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo & title ──────────────────────────────
                Icon(Icons.lock_rounded, size: 72, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  'CrypTransfer',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
                Text(
                  'Secure file sharing',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 40),

                // ── Fields ────────────────────────────────────
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
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
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Error ─────────────────────────────────────
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: cs.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // ── Login button ──────────────────────────────
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Login'),
                ),

                const SizedBox(height: 16),

                // ── Register link ─────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account?",
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
                      ),
                      child: const Text('Register'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
