import 'package:flutter/material.dart';

import '../../core/utils/biometric_helper.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../core/utils/tofu_service.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/shared_widgets.dart';

class RsaKeyManagerScreen extends StatefulWidget {
  const RsaKeyManagerScreen({super.key});

  @override
  State<RsaKeyManagerScreen> createState() => _RsaKeyManagerScreenState();
}

class _RsaKeyManagerScreenState extends State<RsaKeyManagerScreen>
    with SecurityLifecycleMixin<RsaKeyManagerScreen> {
  final _authRepo = AuthRepository();
  bool _gateChecked = false;
  bool _regenerating = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    final ok = await BiometricHelper.authenticate('Unlock RSA Key Vault');
    if (!mounted) return;
    if (!ok) {
      Navigator.pop(context);
      return;
    }
    setState(() => _gateChecked = true);
    _updateLastVaultAccess();
  }

  Future<void> _updateLastVaultAccess() async {
    final uid = _authRepo.currentUid;
    if (uid == null) return;
    try {
      await _authRepo.updateLastVaultAccess(uid);
    } catch (_) {
      // Non-fatal: vault still opens if timestamp update fails
    }
  }

  // Uses TofuService.displayFingerprint() so Key Vault and sender Verify dialog
  // show the same grouped format ("AB12 CD34 EF56 7890") for side-by-side comparison.
  String _fingerprint(String publicKeyJson) =>
      TofuService.displayFingerprint(publicKeyJson);

  Future<void> _onRegenerate() async {
    final uid = _authRepo.currentUid;
    if (uid == null) return;

    final cs = Theme.of(context).colorScheme;
    final confirmed = await _showConfirmDialog(
      icon: Icons.refresh_rounded,
      iconColor: cs.primary,
      title: 'Regenerate RSA Keys?',
      message: 'This will generate a new RSA-2048 keypair.\n\n'
          'Your old private key will be replaced on this device '
          'and your public key in Firestore will be updated.\n\n'
          'Active sessions will be notified automatically.',
      confirmLabel: 'Regenerate',
      confirmColor: cs.primary,
    );
    if (!confirmed || !mounted) return;

    setState(() => _regenerating = true);

    // Track if the progress dialog was shown (for safe cleanup)
    bool dialogShown = false;

    try {
      // Schedule the dialog to show
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showProgressDialog('Generating RSA-2048 keypair…');
          dialogShown = true;
        }
      });

      // Do the actual work
      await _authRepo.regenerateKeyPair(uid);

      if (mounted) {
        // Only dismiss the dialog if it was actually shown
        if (dialogShown && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('RSA keys regenerated successfully.'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );

        // Give the snackbar time to display before closing
        await Future.delayed(const Duration(milliseconds: 300));

        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context); // close RsaKeyManagerScreen to return to ReceiverScreen
        }
      }
    } catch (e) {
      if (mounted) {
        if (dialogShown && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        _showError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _onDelete() async {
    final uid = _authRepo.currentUid;
    if (uid == null) return;

    final gateOk = await BiometricHelper.authenticate('Confirm: Delete RSA Keys');
    if (!gateOk || !mounted) return;

    final cs = Theme.of(context).colorScheme;
    final confirmed = await _showConfirmDialog(
      icon: Icons.delete_forever_rounded,
      iconColor: cs.error,
      title: 'Delete RSA Keys?',
      message: 'This will permanently delete your private key from this device '
          'and clear your public key from Firestore.\n\n'
          'You will not be able to receive encrypted files until you generate new keys.',
      confirmLabel: 'Delete',
      confirmColor: cs.error,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);

    // Track if the progress dialog was shown (for safe cleanup)
    bool dialogShown = false;

    try {
      // Schedule the dialog to show
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showProgressDialog('Deleting RSA keys…');
          dialogShown = true;
        }
      });

      // Do the actual work
      await _authRepo.deleteKeyPair(uid);

      if (mounted) {
        // Only dismiss the dialog if it was actually shown
        if (dialogShown && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('RSA keys deleted.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );

        // Give the snackbar time to display before closing
        await Future.delayed(const Duration(milliseconds: 300));

        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context); // close RsaKeyManagerScreen to return to ReceiverScreen
        }
      }
    } catch (e) {
      if (mounted) {
        if (dialogShown && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        _showError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<bool> _showConfirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        final cs = Theme.of(ctx).colorScheme;
        return GlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Icon(icon, size: 48, color: iconColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CrypButton(
                      label: Text(confirmLabel),
                      onPressed: () => Navigator.pop(ctx, true),
                      color: confirmColor,
                      height: 44,
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 8),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _showProgressDialog(String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.replaceFirst('Exception: ', '')),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _authRepo.currentUid;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'RSA Key Vault',
          style: tt.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: cs.onSurface,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: !_gateChecked
          ? const Center(child: CircularProgressIndicator())
          : uid == null
              ? const Center(child: Text('Not authenticated'))
              : StreamBuilder<UserModel?>(
                  stream: _authRepo.streamUserProfile(uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final user = snapshot.data;
                    final hasKey = user?.publicKey != null &&
                        (user!.publicKey?.isNotEmpty ?? false);
                    return _buildVaultBody(user, hasKey, uid);
                  },
                ),
    );
  }

  Widget _buildVaultBody(UserModel? user, bool hasKey, String uid) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status card — GlassContainer is for info display (not action buttons)
          GlassContainer(
            padding: const EdgeInsets.all(16),
            color: hasKey
                ? cs.secondary.withValues(alpha: 0.08)
                : cs.tertiary.withValues(alpha: 0.08),
            borderColor: hasKey
                ? cs.secondary.withValues(alpha: 0.25)
                : cs.tertiary.withValues(alpha: 0.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasKey
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      color: hasKey ? cs.secondary : cs.tertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasKey ? 'RSA-2048 Key Active' : 'No RSA Keys Found',
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: hasKey ? cs.secondary : cs.tertiary,
                      ),
                    ),
                  ],
                ),
                if (hasKey) ...[
                  const SizedBox(height: 12),
                  _KeyInfoRow(label: 'Algorithm', value: 'RSA-2048'),
                  const SizedBox(height: 6),
                  _KeyInfoRow(
                    label: 'Fingerprint',
                    value: _fingerprint(user!.publicKey!),
                    mono: true,
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Generate an RSA-2048 keypair to enable secure file transfers.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Generate / Regenerate — CrypButton per D-20 (global 3D button standard)
          CrypButton(
            icon: Icon(
              hasKey ? Icons.refresh_rounded : Icons.vpn_key_rounded,
              size: 20,
            ),
            label: Text(hasKey ? 'Regenerate Keys' : 'Generate Keys'),
            onPressed: _regenerating ? null : _onRegenerate,
            color: cs.primary,
          ),
          if (hasKey) ...[
            const SizedBox(height: 12),
            // Delete — CrypButton per D-20 (global 3D button standard)
            CrypButton(
              icon: const Icon(Icons.delete_forever_rounded, size: 20),
              label: const Text('Delete Keys'),
              onPressed: _deleting ? null : _onDelete,
              color: cs.error,
            ),
          ],
          const SizedBox(height: 32),
          Text(
            'Your private key is stored securely on this device. '
            'Your public key is stored in Firestore and shared with senders.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _KeyInfoRow extends StatelessWidget {
  const _KeyInfoRow({
    required this.label,
    required this.value,
    this.mono = false,
  });
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: mono
                ? TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: cs.primary, // GitHub Dark palette — NOT hardcoded hex
                    letterSpacing: 1.2,
                  )
                : tt.bodySmall?.copyWith(color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}
