import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/repositories/auth_repository.dart';
import '../auth/login_screen.dart';

class SidebarDrawer extends StatelessWidget {
  const SidebarDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    final username = user?.displayName ?? 'User';
    final email = user?.email ?? '';

    return Drawer(
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: cs.onPrimary.withValues(alpha: 0.2),
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: GoogleFonts.poppins(
                          color: cs.onPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        email,
                        style: TextStyle(
                          color: cs.onPrimary.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Navigation items ──────────────────────────────────
          ListTile(
            leading: Icon(Icons.people_outline, color: cs.primary),
            title: const Text('Find Friends'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Find Friends — coming soon')),
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.vpn_key_outlined, color: cs.primary),
            title: const Text('Generate RSA Keys'),
            subtitle: const Text('Create your encryption key pair'),
            onTap: () {
              Navigator.pop(context);
              _showKeyGenDialog(context);
            },
          ),

          const Spacer(),
          const Divider(height: 1),

          ListTile(
            leading: Icon(Icons.logout, color: cs.error),
            title: Text('Logout', style: TextStyle(color: cs.error)),
            onTap: () async {
              // Capture the navigator before closing the drawer so its
              // context remains valid after the drawer route is popped.
              final nav = Navigator.of(context);
              nav.pop(); // close drawer

              final confirmed = await showDialog<bool>(
                context: nav.context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content:
                      const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(ctx).colorScheme.error,
                        foregroundColor:
                            Theme.of(ctx).colorScheme.onError,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await AuthRepository().logout();
                if (nav.context.mounted) {
                  nav.pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showKeyGenDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _KeyGenDialog(),
    );
  }
}

class _KeyGenDialog extends StatefulWidget {
  @override
  State<_KeyGenDialog> createState() => _KeyGenDialogState();
}

class _KeyGenDialogState extends State<_KeyGenDialog> {
  _Status _status = _Status.idle;
  String _message = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('RSA Key Generation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_status == _Status.idle)
            Text(
              'Generate a 2048-bit RSA key pair.\n\n'
              'Your private key is stored securely on this device only. '
              'Your public key is shared to Firestore so friends can encrypt files for you.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          if (_status == _Status.loading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Generating keys… this may take a moment.'),
          ],
          if (_status == _Status.success) ...[
            Icon(Icons.check_circle_outline, color: cs.primary, size: 48),
            const SizedBox(height: 12),
            const Text('Key pair generated and stored successfully!'),
          ],
          if (_status == _Status.error) ...[
            Icon(Icons.error_outline, color: cs.error, size: 48),
            const SizedBox(height: 12),
            Text(_message, style: TextStyle(color: cs.error)),
          ],
        ],
      ),
      actions: [
        if (_status != _Status.loading) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_status == _Status.success ? 'Done' : 'Cancel'),
          ),
          if (_status != _Status.success)
            FilledButton(
              onPressed: _generate,
              child: const Text('Generate'),
            ),
        ],
      ],
    );
  }

  Future<void> _generate() async {
    setState(() => _status = _Status.loading);
    try {
      await AuthRepository().generateAndStoreKeyPair();
      if (mounted) setState(() => _status = _Status.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _message = e.toString();
        });
      }
    }
  }
}

enum _Status { idle, loading, success, error }
