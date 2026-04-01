import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/repositories/auth_repository.dart';
import 'login_screen.dart';

// ─── Field status ─────────────────────────────────────────────────────────────

enum _FS { pristine, checking, valid, invalid }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthRepository();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // ── Per-field validation state ────────────────────────────────────────────
  _FS _usernameStatus = _FS.pristine;
  String? _usernameError;
  Timer? _usernameDebounce;

  _FS _emailStatus = _FS.pristine;
  String? _emailError;

  _FS _phoneStatus = _FS.pristine;
  String? _phoneError;

  _FS _passwordStatus = _FS.pristine;
  String? _passwordError;

  _FS _confirmStatus = _FS.pristine;
  String? _confirmError;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_validateUsername);
    _emailController.addListener(_validateEmail);
    _phoneController.addListener(_validatePhone);
    _passwordController.addListener(_validatePassword);
    _confirmController.addListener(_validateConfirm);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ── Real-time validators ──────────────────────────────────────────────────

  void _validateUsername() {
    final v = _usernameController.text.trim();
    _usernameDebounce?.cancel();

    if (v.isEmpty) {
      setState(() {
        _usernameStatus = _FS.pristine;
        _usernameError = null;
      });
      return;
    }

    if (v.length < 3) {
      setState(() {
        _usernameStatus = _FS.invalid;
        _usernameError = 'At least 3 characters';
      });
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
      setState(() {
        _usernameStatus = _FS.invalid;
        _usernameError = 'Letters, numbers and _ only';
      });
      return;
    }

    // Format is valid — debounce Firestore uniqueness check
    setState(() {
      _usernameStatus = _FS.checking;
      _usernameError = null;
    });

    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final taken = await _authService.isUsernameTaken(v);
      if (!mounted) return;
      if (_usernameController.text.trim() != v) return; // stale result
      setState(() {
        if (taken) {
          _usernameStatus = _FS.invalid;
          _usernameError = 'Username already taken';
        } else {
          _usernameStatus = _FS.valid;
          _usernameError = null;
        }
      });
    });
  }

  void _validateEmail() {
    final v = _emailController.text.trim();
    if (v.isEmpty) {
      setState(() {
        _emailStatus = _FS.pristine;
        _emailError = null;
      });
      return;
    }
    final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v);
    setState(() {
      _emailStatus = ok ? _FS.valid : _FS.invalid;
      _emailError = ok ? null : 'Enter a valid email';
    });
  }

  void _validatePhone() {
    final digits = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      setState(() {
        _phoneStatus = _FS.pristine;
        _phoneError = null;
      });
      return;
    }
    final ok = digits.length >= 10 && digits.length <= 11;
    setState(() {
      _phoneStatus = ok ? _FS.valid : _FS.invalid;
      _phoneError = ok ? null : 'Must be 10–11 digits';
    });
  }

  void _validatePassword() {
    final v = _passwordController.text;
    if (v.isEmpty) {
      setState(() {
        _passwordStatus = _FS.pristine;
        _passwordError = null;
      });
    } else {
      final ok = v.length >= 6;
      setState(() {
        _passwordStatus = ok ? _FS.valid : _FS.invalid;
        _passwordError = ok ? null : 'At least 6 characters';
      });
    }
    // Re-evaluate confirm when password changes
    if (_confirmController.text.isNotEmpty) _validateConfirm();
  }

  void _validateConfirm() {
    final v = _confirmController.text;
    if (v.isEmpty) {
      setState(() {
        _confirmStatus = _FS.pristine;
        _confirmError = null;
      });
      return;
    }
    final ok = v == _passwordController.text;
    setState(() {
      _confirmStatus = ok ? _FS.valid : _FS.invalid;
      _confirmError = ok ? null : 'Passwords do not match';
    });
  }

  // ── Registration ──────────────────────────────────────────────────────────

  bool get _allValid =>
      _usernameStatus == _FS.valid &&
      _emailStatus == _FS.valid &&
      _phoneStatus == _FS.valid &&
      _passwordStatus == _FS.valid &&
      _confirmStatus == _FS.valid;

  Future<void> _register() async {
    // Trigger validation on any untouched field
    _touchAll();
    if (!_allValid) return;

    setState(() => _isLoading = true);

    try {
      await _authService.register(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account created successfully!'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        // Replace the register screen with login (don't stack)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      _handleRegistrationError(msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleRegistrationError(String raw) {
    String snackMsg;

    if (raw.contains('email-already-in-use')) {
      setState(() {
        _emailStatus = _FS.invalid;
        _emailError = 'Email already registered';
      });
      snackMsg = 'That email is already registered.';
    } else if (raw.contains('Username already taken')) {
      setState(() {
        _usernameStatus = _FS.invalid;
        _usernameError = 'Username already taken';
      });
      snackMsg = 'Username already taken.';
    } else if (raw.contains('weak-password')) {
      setState(() {
        _passwordStatus = _FS.invalid;
        _passwordError = 'Password is too weak';
      });
      snackMsg = 'Password is too weak. Use at least 6 characters.';
    } else if (raw.contains('invalid-email')) {
      setState(() {
        _emailStatus = _FS.invalid;
        _emailError = 'Invalid email address';
      });
      snackMsg = 'Please enter a valid email address.';
    } else if (raw.contains('network')) {
      snackMsg = 'Network error. Check your connection.';
    } else {
      snackMsg = 'Registration failed. Please try again.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackMsg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// Force-validates all empty fields so errors show on submit tap.
  void _touchAll() {
    if (_usernameController.text.trim().isEmpty) {
      setState(() {
        _usernameStatus = _FS.invalid;
        _usernameError = 'Required';
      });
    }
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _emailStatus = _FS.invalid;
        _emailError = 'Required';
      });
    }
    if (_phoneController.text.trim().isEmpty) {
      setState(() {
        _phoneStatus = _FS.invalid;
        _phoneError = 'Required';
      });
    }
    if (_passwordController.text.isEmpty) {
      setState(() {
        _passwordStatus = _FS.invalid;
        _passwordError = 'Required';
      });
    }
    if (_confirmController.text.isEmpty) {
      setState(() {
        _confirmStatus = _FS.invalid;
        _confirmError = 'Required';
      });
    }
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Widget? _statusIcon(_FS status) {
    switch (status) {
      case _FS.checking:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _FS.valid:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _FS.invalid:
        return Icon(Icons.cancel,
            color: Theme.of(context).colorScheme.error);
      case _FS.pristine:
        return null;
    }
  }

  /// Suffix for password/confirm fields — status icon + visibility toggle.
  Widget _passwordSuffix(_FS status, bool obscure, VoidCallback toggle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == _FS.valid)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.check_circle, color: Colors.green, size: 20),
          )
        else if (status == _FS.invalid)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.cancel,
                color: Theme.of(context).colorScheme.error, size: 20),
          ),
        IconButton(
          icon: Icon(obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
          onPressed: toggle,
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Create Account', style: GoogleFonts.poppins()),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.person_add_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 8),
              Text(
                'Join CrypTransfer',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 28),

              // ── Username ────────────────────────────────────
              TextField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: const Icon(Icons.alternate_email),
                  suffixIcon: _statusIcon(_usernameStatus),
                  errorText: _usernameError,
                ),
              ),
              const SizedBox(height: 14),

              // ── Email ───────────────────────────────────────
              TextField(
                controller: _emailController,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  suffixIcon: _statusIcon(_emailStatus),
                  errorText: _emailError,
                ),
              ),
              const SizedBox(height: 14),

              // ── Phone ───────────────────────────────────────
              TextField(
                controller: _phoneController,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  suffixIcon: _statusIcon(_phoneStatus),
                  errorText: _phoneError,
                ),
              ),
              const SizedBox(height: 14),

              // ── Password ─────────────────────────────────────
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: _passwordSuffix(
                    _passwordStatus,
                    _obscurePassword,
                    () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  errorText: _passwordError,
                ),
              ),
              const SizedBox(height: 14),

              // ── Confirm password ──────────────────────────────
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _register(),
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: _passwordSuffix(
                    _confirmStatus,
                    _obscureConfirm,
                    () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  errorText: _confirmError,
                ),
              ),
              const SizedBox(height: 22),

              // ── Register button ───────────────────────────────
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton(
                      onPressed: _register,
                      child: const Text('Create Account'),
                    ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account?',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Login'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
