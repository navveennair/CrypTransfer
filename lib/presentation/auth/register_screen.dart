import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/shared_widgets.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import '../home/home_screen.dart';

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

    setState(() {
      _usernameStatus = _FS.checking;
      _usernameError = null;
    });

    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final taken = await _authService.isUsernameTaken(v);
      if (!mounted) return;
      if (_usernameController.text.trim() != v) return;
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

  bool get _allValid =>
      _usernameStatus == _FS.valid &&
      _emailStatus == _FS.valid &&
      _phoneStatus == _FS.valid &&
      _passwordStatus == _FS.valid &&
      _confirmStatus == _FS.valid;

  Future<void> _register() async {
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
          backgroundColor: Theme.of(context).colorScheme.secondary,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _handleRegistrationError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleRegistrationError(String raw) {
    String snackMsg = 'Registration failed. Please try again.';

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
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackMsg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _registerWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final cred = await _authService.signInWithGoogle();
      if (!mounted) return;
      
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

  Widget? _statusIcon(_FS status) {
    switch (status) {
      case _FS.checking:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _FS.valid:
        return Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.secondary, size: 20);
      case _FS.invalid:
        return Icon(Icons.cancel_rounded,
            color: Theme.of(context).colorScheme.error, size: 20);
      case _FS.pristine:
        return null;
    }
  }

  Widget _passwordSuffix(_FS status, bool obscure, VoidCallback toggle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == _FS.valid)
          Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.secondary, size: 20)
        else if (status == _FS.invalid)
          Icon(Icons.cancel_rounded,
                color: Theme.of(context).colorScheme.error, size: 20),
        IconButton(
          icon: Icon(obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined, size: 20),
          onPressed: toggle,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Positioned(
            top: -size.height * 0.1,
            left: -size.width * 0.2,
            child: _BlurCircle(
              size: 300,
              color: AppTheme.accentPurple.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            bottom: -size.height * 0.1,
            right: -size.width * 0.1,
            child: _BlurCircle(
              size: 250,
              color: AppTheme.primaryGold.withValues(alpha: 0.1),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Hero(
                    tag: 'app_logo',
                    child: GlassContainer(
                      padding: const EdgeInsets.all(20),
                      borderRadius: 100,
                      color: cs.primary.withValues(alpha: 0.1),
                      child: Icon(Icons.person_add_rounded, size: 64, color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: 24),

                  GlassContainer(
                    padding: const EdgeInsets.all(24),
                    borderRadius: 28,
                    child: Column(
                      children: [
                        TextField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                            suffixIcon: _statusIcon(_usernameStatus),
                            errorText: _usernameError,
                            filled: true,
                            fillColor: cs.onSurface.withValues(alpha: 0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _emailController,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined, size: 20),
                            suffixIcon: _statusIcon(_emailStatus),
                            errorText: _emailError,
                            filled: true,
                            fillColor: cs.onSurface.withValues(alpha: 0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                            suffixIcon: _statusIcon(_phoneStatus),
                            errorText: _phoneError,
                            filled: true,
                            fillColor: cs.onSurface.withValues(alpha: 0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: _passwordSuffix(
                              _passwordStatus,
                              _obscurePassword,
                              () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            errorText: _passwordError,
                            filled: true,
                            fillColor: cs.onSurface.withValues(alpha: 0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirmController,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _register(),
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: _passwordSuffix(
                              _confirmStatus,
                              _obscureConfirm,
                              () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                            errorText: _confirmError,
                            filled: true,
                            fillColor: cs.onSurface.withValues(alpha: 0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: cs.primary, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        _isLoading
                            ? const CircularProgressIndicator()
                            : CrypButton(
                                label: const Text('Create Account'),
                                color: cs.primary,
                                onPressed: _register,
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
                          onPressed: _isLoading ? null : _registerWithGoogle,
                          icon: const _GoogleGIcon(),
                          label: const Text('Sign up with Google'),
                          color: Theme.of(context).colorScheme.secondary,
                          height: 48,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account?',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Login',
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
