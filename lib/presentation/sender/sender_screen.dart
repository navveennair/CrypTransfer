import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/utils/biometric_helper.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';
import 'sender_controller.dart';
import 'sender_transfer_screen.dart';

// ─── Widget ──────────────────────────────────────────────────────────────────

class SenderScreen extends StatefulWidget {
  final String? preFilledPartnerUid;
  final String? preFilledPartnerUsername;
  final String? handshakeDocId;

  const SenderScreen({
    super.key,
    this.preFilledPartnerUid,
    this.preFilledPartnerUsername,
    this.handshakeDocId,
  });

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen>
    with SecurityLifecycleMixin<SenderScreen> {
  late final SenderController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SenderController(
      connService: KeyRepository(),
      transferRepo: TransferRepository(),
      preFilledPartnerUid: widget.preFilledPartnerUid,
      preFilledPartnerUsername: widget.preFilledPartnerUsername,
      initialHandshakeDocId: widget.handshakeDocId,
    );

    // Wire controller callbacks → widget UI actions
    _controller.onError = (msg, {Duration? duration, bool clear = false}) =>
        _showError(msg, duration: duration, clear: clear);
    _controller.onSuccess = _showSuccess;
    _controller.onInfo = _showInfo;
    _controller.onEject = _ejectToHomeScreen;
    _controller.onAbortNavigate = _navigateHomeAfterAbort;
    _controller.onBuffersWipe = wipeAll;
    _controller.onRegisterBuffer = registerBuffer;
    _controller.onUnregisterBuffer = unregisterBuffer;

    // Rebuild widget whenever controller state changes
    _controller.stateNotifier.addListener(() {
      if (mounted) setState(() {});
    });

    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ─── SnackBar helpers ─────────────────────────────────────────────────────

  void _showError(String msg, {Duration? duration, bool clear = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (clear) messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: duration ?? const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg,
      {Duration duration = const Duration(seconds: 4)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      duration: duration,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.tertiary,
    ));
  }

  // ─── Navigation helpers ───────────────────────────────────────────────────

  void _ejectToHomeScreen() {
    _showError('Session Terminated — receiver closed the session.',
        duration: const Duration(seconds: 5));
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _navigateHomeAfterAbort(String msg) {
    _showError(msg, duration: const Duration(seconds: 5), clear: true);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _send() {
    final args = _controller.buildSendArgs();
    if (args == null) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => SenderTransferScreen(
          transferId: args.transferId,
          encryptedBytes: args.encryptedBytesCopy,
          fileName: args.fileName,
          fileSize: args.fileSize,
          receiverUsername: args.receiverUsername,
          receiverId: args.receiverId,
          senderId: args.senderId,
          encryptedAESKeyB64: args.encryptedAESKeyB64,
          ivB64: args.ivB64,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = _controller.state;
    return PopScope(
      canPop: !s.encrypting && !s.encryptingKey,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _controller.wipeSensitiveData();
          // Clear transfer roles if assigned (returns user to role picker)
          if (_controller.handshakeDocId != null) {
            _controller.connService
                .clearTransferRoles(handshakeDocId: _controller.handshakeDocId!);
          }
        } else if (_controller.handshakeDocId != null &&
            !s.encrypting &&
            !s.encryptingKey) {
          // Show confirmation dialog for role clearing
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.all(24),
              content: GlassContainer(
                padding: const EdgeInsets.all(24),
                borderRadius: 28,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded,
                        size: 48,
                        color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Go Back?',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Going back will clear your role assignment. The connection will remain.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: CrypButton(
                            label: const Text('Cancel'),
                            onPressed: () => Navigator.pop(ctx),
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            height: 44,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CrypButton(
                            label: const Text('Clear & Go Back'),
                            color: Theme.of(ctx).colorScheme.primary,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final nav = Navigator.of(context);
                              await _controller.connService.clearTransferRoles(
                                  handshakeDocId: _controller.handshakeDocId!);
                              if (mounted) nav.pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Send File'),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _WelcomeBanner(),
              const SizedBox(height: 32),
              _Step0ConnectionStatus(
                receiverSelected: s.receiverSelected,
                receiverReady: s.receiverReady,
                receiverUsername: s.receiverUsername,
                secondsRemaining: s.secondsRemaining,
                timerRunning: s.timerRunning,
              ),
              const SizedBox(height: 16),
              _StepsBlock(
                receiverReady: s.receiverReady,
                receiverSelected: s.receiverSelected,
                fileSelected: s.fileSelected,
                fileEncrypted: s.fileEncrypted,
                file: s.file,
                onPickFile: s.receiverSelected ? _controller.pickFile : null,
                encrypting: s.encrypting,
                encryptionProgress: s.encryptionProgress,
                aesKey: s.aesKey,
                iv: s.iv,
                encryptedBytes: s.encryptedBytes,
                onEncryptFile: s.fileSelected ? _controller.encryptFile : null,
                encryptingKey: s.encryptingKey,
                readyToSend: s.readyToSend,
                receiverUsername: s.receiverUsername,
                onEncryptKey: s.fileEncrypted && !s.encryptingKey
                    ? () => _controller.encryptAesKey(BiometricHelper.authenticate)
                    : null,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Encryption progress ─────────────────────────────────────────────────────

class _EncryptionProgressWidget extends StatelessWidget {
  final double progress;
  const _EncryptionProgressWidget({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (progress * 100).toInt();
    final isReading = progress < 0.7;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.all(16),
      color: cs.tertiary.withValues(alpha: 0.08),
      borderColor: cs.tertiary.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.tertiary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isReading ? 'Reading file… $pct%' : 'Encrypting AES-256-GCM… $pct%',
                style: TextStyle(fontSize: 13, color: cs.tertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: cs.tertiary.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(cs.tertiary),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class _WaitingForConnectionWidget extends StatefulWidget {
  const _WaitingForConnectionWidget();

  @override
  State<_WaitingForConnectionWidget> createState() =>
      _WaitingForConnectionWidgetState();
}

class _WaitingForConnectionWidgetState
    extends State<_WaitingForConnectionWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 10),
          ScaleTransition(
            scale: _scale,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.1),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2), width: 2),
                ),
                child:
                    Icon(Icons.wifi_tethering_rounded, color: cs.primary, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Waiting for Secure Connection…',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'A receiver must authorize you to begin.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  final String username;

  const _ConnectedBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: cs.secondary.withValues(alpha: 0.1),
      borderColor: cs.secondary.withValues(alpha: 0.2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_user_rounded,
                color: cs.secondary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection Verified',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.secondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secure channel open with @$username',
                  style: TextStyle(fontSize: 12, color: cs.secondary),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_rounded, color: cs.secondary, size: 18),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final PlatformFile file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = (file.extension ?? '').toLowerCase();

    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.all(14),
      color: cs.surface.withValues(alpha: 0.05),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _extColor(ext, cs).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_extIcon(ext), color: _extColor(ext, cs), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtSize(file.size),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _extIcon(String ext) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['mp4', 'mov', 'avi'].contains(ext)) return Icons.video_file_rounded;
    if (['mp3', 'wav', 'flac'].contains(ext)) return Icons.audio_file_rounded;
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _extColor(String ext, ColorScheme cs) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return cs.primary;
    if (['mp4', 'mov', 'avi'].contains(ext)) return cs.tertiary;
    if (['mp3', 'wav', 'flac'].contains(ext)) return cs.tertiary;
    if (ext == 'pdf') return cs.error;
    return cs.outline;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _EncryptedBadge extends StatelessWidget {
  final int keyBits;
  final int ivBytes;
  final int ciphertextBytes;

  const _EncryptedBadge({
    required this.keyBits,
    required this.ivBytes,
    required this.ciphertextBytes,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.all(16),
      color: cs.tertiary.withValues(alpha: 0.08),
      borderColor: cs.tertiary.withValues(alpha: 0.2),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.enhanced_encryption_rounded,
                  color: cs.tertiary, size: 20),
              const SizedBox(width: 10),
              Text('AES-256-GCM Locked',
                  style: tt.bodyMedium?.copyWith(color: cs.tertiary)),
            ],
          ),
          const SizedBox(height: 12),
          _Row('Algorithm', 'AES-256-GCM'),
          _Row('Key Size', '$keyBits bits'),
          _Row('IV Size', '$ivBytes bytes'),
          _Row('Payload', _fmtSize(ciphertextBytes)),
        ],
      ),
    );
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _ReceiverBadge extends StatelessWidget {
  final String username;

  const _ReceiverBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: cs.primary.withValues(alpha: 0.1),
      borderColor: cs.primary.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(Icons.person_pin_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                      text: 'Encrypted for ',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.7))),
                  TextSpan(
                      text: '@$username',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface)),
                ],
              ),
            ),
          ),
          Icon(Icons.check_circle_rounded, color: cs.secondary, size: 20),
        ],
      ),
    );
  }
}

class _WaitingForReceiverWidget extends StatefulWidget {
  final int secondsRemaining;
  final bool timerRunning;
  const _WaitingForReceiverWidget(
      {required this.secondsRemaining, required this.timerRunning});

  @override
  State<_WaitingForReceiverWidget> createState() =>
      _WaitingForReceiverWidgetState();
}

class _WaitingForReceiverWidgetState extends State<_WaitingForReceiverWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mins = widget.secondsRemaining ~/ 60;
    final secs = widget.secondsRemaining % 60;
    final display =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          ScaleTransition(
            scale: _scale,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.1),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.hourglass_top_rounded,
                  color: cs.primary,
                  size: 32,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Waiting for Receiver to prepare secure vault…',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.timerRunning
                ? 'Receiver must confirm readiness to continue.'
                : 'Waiting for receiver to connect…',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (widget.timerRunning) ...[
            const SizedBox(height: 16),
            GlassContainer(
              blur: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: cs.primary.withValues(alpha: 0.07),
              borderColor: cs.primary.withValues(alpha: 0.15),
              borderRadius: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    display,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: cs.primary,
                        ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Welcome banner ───────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      borderRadius: 28,
      color: cs.primary.withValues(alpha: 0.1),
      borderColor: cs.primary.withValues(alpha: 0.2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.send_rounded, color: cs.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Inbox',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                ),
                Text(
                  'Securely encrypt and transmit your data.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
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

// ─── Step 0: connection status ────────────────────────────────────────────────

class _Step0ConnectionStatus extends StatelessWidget {
  final bool receiverSelected;
  final bool receiverReady;
  final String? receiverUsername;
  final int secondsRemaining;
  final bool timerRunning;

  const _Step0ConnectionStatus({
    required this.receiverSelected,
    required this.receiverReady,
    required this.receiverUsername,
    required this.secondsRemaining,
    required this.timerRunning,
  });

  @override
  Widget build(BuildContext context) {
    return StepCard(
      step: 0,
      title: 'Secure Connection',
      done: receiverSelected && receiverReady,
      currentStep: !(receiverSelected && receiverReady),
      child: receiverSelected
          ? (receiverReady
              ? _ConnectedBadge(username: receiverUsername!)
              : _WaitingForReceiverWidget(
                  secondsRemaining: secondsRemaining,
                  timerRunning: timerRunning,
                ))
          : const _WaitingForConnectionWidget(),
    );
  }
}

// ─── Steps 1-4 block ─────────────────────────────────────────────────────────

class _StepsBlock extends StatelessWidget {
  // Receiver state
  final bool receiverReady;
  // Step 1
  final bool receiverSelected;
  final bool fileSelected;
  final bool fileEncrypted;
  final PlatformFile? file;
  final VoidCallback? onPickFile;
  // Step 2
  final bool encrypting;
  final double encryptionProgress;
  final Uint8List? aesKey;
  final Uint8List? iv;
  final Uint8List? encryptedBytes;
  final VoidCallback? onEncryptFile;
  // Step 3
  final bool encryptingKey;
  final bool readyToSend;
  final String? receiverUsername;
  final VoidCallback? onEncryptKey;
  // Step 4
  final VoidCallback? onSend;

  const _StepsBlock({
    required this.receiverReady,
    required this.receiverSelected,
    required this.fileSelected,
    required this.fileEncrypted,
    required this.file,
    required this.onPickFile,
    required this.encrypting,
    required this.encryptionProgress,
    required this.aesKey,
    required this.iv,
    required this.encryptedBytes,
    required this.onEncryptFile,
    required this.encryptingKey,
    required this.readyToSend,
    required this.receiverUsername,
    required this.onEncryptKey,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      opacity: receiverReady ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !receiverReady,
        child: Column(
          children: [
            // ── Step 1: Select File ───────────────────────────────
            AnimatedOpacity(
              opacity: (receiverSelected && !fileEncrypted) ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: fileEncrypted,
                child: StepCard(
                  step: 1,
                  title: 'Select File',
                  done: fileSelected,
                  currentStep: receiverReady && !fileSelected,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CrypButton(
                        icon: const Icon(Icons.folder_open_rounded, size: 20),
                        label:
                            Text(file == null ? 'Browse Files' : 'Change File'),
                        onPressed: onPickFile,
                        color: cs.primary,
                      ),
                      if (file != null) ...[
                        const SizedBox(height: 16),
                        _FileCard(file: file!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 2: Encrypt ───────────────────────────────────
            AnimatedOpacity(
              opacity: fileSelected ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: StepCard(
                step: 2,
                title: 'AES-256-GCM Encryption',
                done: fileEncrypted,
                currentStep: fileSelected && !fileEncrypted,
                child: fileEncrypted
                    ? _EncryptedBadge(
                        keyBits: aesKey!.length * 8,
                        ivBytes: iv!.length,
                        ciphertextBytes: encryptedBytes!.length,
                      )
                    : encrypting
                        ? _EncryptionProgressWidget(
                            progress: encryptionProgress)
                        : CrypButton(
                            icon: const Icon(Icons.lock_rounded, size: 20),
                            label: const Text('Encrypt with AES Key'),
                            onPressed: onEncryptFile,
                            color: cs.tertiary,
                          ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 3: RSA Handshake ─────────────────────────────
            AnimatedOpacity(
              opacity: fileEncrypted ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: StepCard(
                step: 3,
                title: 'RSA Key Handshake',
                done: readyToSend,
                currentStep: fileEncrypted && !readyToSend,
                child: readyToSend
                    ? _ReceiverBadge(username: receiverUsername!)
                    : CrypButton(
                        icon: encryptingKey
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.security_rounded, size: 20),
                        label: Text(encryptingKey
                            ? 'Encrypting key…'
                            : 'Encrypt Key for @${receiverUsername ?? "receiver"}'),
                        onPressed: onEncryptKey,
                        color: cs.secondary,
                      ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Step 4: Send ──────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: readyToSend
                  ? CrypButton(
                      key: const ValueKey('send-btn'),
                      icon: const Icon(Icons.send_rounded, size: 20),
                      label: const Text('Send Encrypted File'),
                      onPressed: onSend,
                      color: cs.secondary,
                    )
                  : const SizedBox.shrink(key: ValueKey('send-empty')),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
