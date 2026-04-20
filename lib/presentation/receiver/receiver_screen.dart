import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/biometric_helper.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../core/utils/session_manager.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/services/encryption_service.dart';
import '../widgets/shared_widgets.dart';
import 'receiver_transfer_screen.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen>
    with SecurityLifecycleMixin<ReceiverScreen>, WidgetsBindingObserver {
  final _authService = AuthRepository();
  final _connService = KeyRepository();
  final _sessionManager = SessionManager();

  // ── Step 1: Key Gen ──────────────────────────────────────────────────────
  bool _hasPrivateKey = false;
  bool _hasPublicKey = false;
  bool _checkingStatus = true;
  
  // ── Step 2: Ready State ──────────────────────────────────────────────────
  bool _isReadyToReceive = false;
  bool _loadingReadyState = true;
  bool _isTogglingReady = false;

  // ── Step 3: The Connect ──────────────────────────────────────────────────
  List<UserModel> _connectedFriends = [];
  bool _loadingFriends = false;
  bool _handshaking = false;
  bool _handshakeDone = false;

  // ── Session lock (active transfer in progress) ────────────────────────────
  bool _sessionLocked = false;

  // ── Incoming transfer info (used for auto-navigation) ────────────────────
  String? _incomingTransferId;
  String? _incomingFileName;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _transferStream;

  // ── Step completion ───────────────────────────────────────────────────────
  bool get _step1Done => _hasPrivateKey && _hasPublicKey;
  bool get _step2Done => _isReadyToReceive;
  bool get _step3Done =>
      _sessionManager.activeSenderUid != null && _handshakeDone;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionManager.stateNotifier.addListener(_onSessionStateChanged);
    _checkKeyStatus();
    _loadConnectedFriends();
    _loadReadyToReceiveState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionManager.stateNotifier.removeListener(_onSessionStateChanged);
    EncryptionService.unbindSession(); // cancel reactive kill-switch binding
    _sessionManager.dispose();
    super.dispose();
  }

  void _onSessionStateChanged() {
    if (!mounted) return;
    setState(() {});
    // Reactive navigation: the moment SessionManager enters decrypting state
    // (triggered by _handleIncomingTransfer), auto-push to ReceiverTransferScreen.
    if (_sessionManager.state == SessionState.decrypting &&
        _incomingTransferId != null) {
      _navigateToDecrypt();
    }
  }

  void _navigateToDecrypt() {
    final id = _incomingTransferId;
    final name = _incomingFileName ?? 'file';
    if (id == null) return;
    setState(() {
      _incomingTransferId = null;
      _incomingFileName = null;
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiverTransferScreen(
          transferId: id,
          fileName: name,
          sessionManager: _sessionManager,
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isReadyToReceive) {
      // Delegates to SessionManager — transitions state to terminated, emitting
      // on stateStream so EncryptionService.bindSession reacts and purges keys.
      // SecurityLifecycleMixin.wipeAll zeroes in-memory buffers immediately.
      _sessionManager.handleLifecycleState(state, onBuffersWipe: wipeAll);
    }
  }

  // ─── Step 0: RSA key status ───────────────────────────────────────────────

  Future<void> _checkKeyStatus() async {
    setState(() => _checkingStatus = true);
    try {
      final hasPriv = await _authService.hasKeyPair();
      final pubKey = await _authService.getPublicKey();
      if (mounted) {
        setState(() {
          _hasPrivateKey = hasPriv;
          _hasPublicKey = pubKey != null && pubKey.isNotEmpty;
          _checkingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingStatus = false);
        _showError('Could not load key status: $e');
      }
    }
  }

  Future<void> _generateKeys() async {
    final alreadyHas = _hasPrivateKey;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.vpn_key_rounded, size: 36),
        title:
            Text(alreadyHas ? 'Regenerate RSA Keys?' : 'Generate RSA Keys'),
        content: Text(
          alreadyHas
              ? 'This will overwrite your existing keypair.\n\n'
                  'Your old private key will be deleted from this device '
                  'and your public key in Firestore will be updated. '
                  'Re-establish connections to share the new key.'
              : 'Generate a 2048-bit RSA keypair.\n\n'
                  '• Private key is stored securely on this device only\n'
                  '• Public key is saved to Firestore for senders to use',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(alreadyHas ? 'Regenerate' : 'Generate')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _showProgressDialog(
        'Generating RSA-2048 keypair…\nThis may take a moment.');
    try {
      await _authService.generateAndStoreKeyPair();
      await _connService.resyncPublicKeyToAllConnections();
      if (!mounted) return;
      Navigator.pop(context);
      await _checkKeyStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('RSA keypair generated and synced!'),
          backgroundColor: Colors.green.shade600,
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError(e.toString());
      }
    }
  }

  // ─── Step 1: Ready to receive ─────────────────────────────────────────────

  Future<void> _loadReadyToReceiveState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadingReadyState = false);
      return;
    }
    setState(() => _loadingReadyState = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirebaseConstants.users)
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _isReadyToReceive =
              doc.data()?['isReadyToReceive'] as bool? ?? false;
          _loadingReadyState = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReadyState = false);
    }
  }

  Future<void> _onToggleReady(bool value) async {
    if (_sessionLocked && !value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot close session — transfer in progress.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    setState(() => _isTogglingReady = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      if (value) {
        // ── OPEN MAILBOX: generate fresh keypair + publish public key ──────
        await EncryptionService.setupReceiverSession(uid);
        // Bind the reactive kill-switch: EncryptionService now listens to
        // SessionManager.stateStream and auto-calls closeReceiverSession
        // when state transitions to terminated (lifecycle / back-nav).
        EncryptionService.bindSession(_sessionManager.stateStream, uid);
        if (mounted) {
          setState(() {
            _isReadyToReceive = true;
            _hasPrivateKey = true;
            _hasPublicKey = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Ready to receive. Public key shared.'),
              backgroundColor: Colors.green.shade600,
            ),
          );
        }
      } else {
        // ── CLOSE MAILBOX: show confirmation then auto-wipe ────────────────
        final confirmed = await _showCloseSessionDialog();
        if (!confirmed) {
          setState(() => _isTogglingReady = false);
          return;
        }
        // Unbind before the imperative close so the reactive listener does
        // not fire a redundant closeReceiverSession after we complete cleanup.
        EncryptionService.unbindSession();
        await EncryptionService.closeReceiverSession(uid);
        wipeAll(); // zero any in-memory buffers via SecurityLifecycleMixin
        _sessionManager.reset(); // clears activeSender + resets state to open
        if (mounted) {
          setState(() {
            _isReadyToReceive = false;
            _hasPrivateKey = false;
            _hasPublicKey = false;
            _sessionLocked = false;
            _handshaking = false;
            _handshakeDone = false;
            _connectedFriends.clear();
            _transferStream = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Session closed. Public key deleted.'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingReady = false);
    }
  }

  Future<bool> _showCloseSessionDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Icon(Icons.lock_rounded, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Close Mailbox?',
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This will permanently:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Text('Delete your public key from Firebase'),
                  Text('Wipe private key from device storage'),
                  Text('Remove all pending key transfers'),
                  Text('Mark you as unavailable'),
                ],
              ),
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
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade700),
                    child: const Text('Close Mailbox'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  // ─── Step 2: Connections ──────────────────────────────────────────────────

  Future<void> _loadConnectedFriends() async {
    setState(() => _loadingFriends = true);
    try {
      final friends = await _connService.getConnectedFriends();
      if (mounted) {
        setState(() {
          _connectedFriends = friends;
          _loadingFriends = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  /// Opens the Find Sender sheet.  A session allows only one active sender;
  /// if one is already selected this is a no-op.
  void _openFindSenderSheet() {
    if (_sessionManager.activeSenderUid != null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FindSenderSheet(
        service: _connService,
        initialConnected: _connectedFriends,
        onConnectionMade: _loadConnectedFriends,
        onSenderSelected: _onSenderSelected,
      ),
    );
  }

  // ─── Step 2 continuation: Atomic handshake after sender selection ────────

  /// Called when the receiver selects a sender from the Find Sender sheet.
  ///
  /// Performs the Receiver-Authorized Handshake as a single atomic operation:
  /// 1. [SessionManager.selectSender] — locks the sender in-memory.
  /// 2. Binds [_transferStream] to the new sender immediately.
  /// 3. [KeyRepository.selectSenderHandshake] — WriteBatch commits:
  ///    a. `users/{receiverUid}.selectedSenderUid = senderUid`
  ///    b. `rsa_key_transfers` doc with `status: 'handshake_complete'`
  ///
  /// The 'Share Public Key' step (formerly Step 3) is now invisible — it
  /// completes here without any user interaction.
  Future<void> _onSenderSelected(UserModel sender) async {
    _sessionManager.selectSender(sender.uid, sender.username);
    // Bind stable transfer-watch stream immediately (fixes double-stream issue).
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _transferStream = FirebaseFirestore.instance
        .collection(FirebaseConstants.transfers)
        .where('receiverId', isEqualTo: myUid)
        .where('senderId', isEqualTo: sender.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
    setState(() => _handshaking = true);
    try {
      await _connService.selectSenderHandshake(
        senderUid: sender.uid,
        senderUsername: sender.username,
      );
      if (mounted) {
        setState(() {
          _handshakeDone = true;
          _handshaking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '🔑 Secure channel open — waiting for @${sender.username}'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _handshaking = false);
        _showError(e.toString());
      }
    }
  }

  // ─── Incoming transfer handler (called from Step 3 StreamBuilder) ─────────

  /// Called when the Firestore StreamBuilder in Step 3 detects a pending
  /// transfer from [_sessionManager.activeSenderUid].
  ///
  /// Guards against re-entry with [_sessionLocked].  On first call:
  /// 1. Locks the session (prevents mailbox close).
  /// 2. Sets [SessionState.decrypting] — triggers [_onSessionStateChanged]
  ///    which auto-pushes to [ReceiverTransferScreen].
  Future<void> _handleIncomingTransfer(
      String transferId, Map<String, dynamic> data) async {
    // Re-entry guard — StreamBuilder may fire multiple times for the same doc.
    if (_sessionLocked) return;

    final fileName = data['fileName'] as String? ?? 'file';
    final senderId = data['senderId'] as String?;

    // Session isolation: only process transfers from the active selected sender.
    if (_sessionManager.activeSenderUid != null &&
        senderId != _sessionManager.activeSenderUid) {
      return;
    }

    String? senderUsername = _sessionManager.activeSenderUsername;
    if (senderUsername == null && senderId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(FirebaseConstants.users)
            .doc(senderId)
            .get();
        senderUsername = doc.data()?['username'] as String?;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _incomingTransferId = transferId;
        _incomingFileName = fileName;
        _sessionLocked = true;
      });
      _sessionManager.lock();
      // Triggers _onSessionStateChanged → _navigateToDecrypt().
      _sessionManager.setDecrypting();
    }
  }

  // ─── RSA Key Manager (biometric gated) ───────────────────────────────────

  Future<void> _openKeyManager() async {
    final authenticated = await BiometricHelper.authenticate(
        'Authenticate to access the RSA Key Manager');
    if (!authenticated || !mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _KeyManagerSheet(
        authService: _authService,
        connService: _connService,
        hasPrivateKey: _hasPrivateKey,
        hasPublicKey: _hasPublicKey,
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _showProgressDialog(String message) {
    showDialog<void>(
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

  // ─── Step content builders ────────────────────────────────────────────────

  Widget _step1Content() {
    if (_checkingStatus) {
      return const LinearProgressIndicator();
    }
    if (_step1Done) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '🔑 Keys Ready ✅',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _KeyInfoRow('Private Key', 'Stored securely on device'),
                const SizedBox(height: 2),
                _KeyInfoRow('Public Key', 'Saved to Firestore'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Regenerate Keys'),
            onPressed: _generateKeys,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange.shade700,
              side: BorderSide(color: Colors.orange.shade400),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      );
    }
    // Keys not yet generated
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔑', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Generate your RSA-2048 keypair',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Required before receiving files',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CrypButton(
          icon: const Icon(Icons.vpn_key_rounded),
          label: const Text('Generate RSA Keys'),
          onPressed: _generateKeys,
          sessionState: _sessionManager.state != SessionState.open
              ? _sessionManager.state
              : null,
        ),
      ],
    );
  }

  Widget _step2Content() {
    if (_loadingReadyState) {
      return const Center(
        child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return GestureDetector(
      onTap: _step1Done ? () => _onToggleReady(!_isReadyToReceive) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _isReadyToReceive
              ? Colors.green.withValues(alpha: 0.10)
              : Colors.grey.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isReadyToReceive
                ? Colors.green.shade300
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isReadyToReceive
                        ? '✅ You are ready to receive files'
                        : 'Set yourself as ready to receive',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _isReadyToReceive
                          ? Colors.green.shade800
                          : null,
                    ),
                  ),
                  if (_isReadyToReceive) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Senders can now send you files',
                      style: TextStyle(
                          fontSize: 12, color: Colors.green.shade600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _isTogglingReady
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.5))
                : Switch(
                    value: _isReadyToReceive,
                    onChanged: _step1Done ? _onToggleReady : null,
                    activeThumbColor: Colors.green,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _step3Content() {
    final cs = Theme.of(context).colorScheme;
    final selectedUid = _sessionManager.activeSenderUid;
    final selectedName = _sessionManager.activeSenderUsername;

    // ── Sender locked in — show badge + inline handshake / transfer status ──
    if (selectedUid != null && selectedName != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sender badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                UserAvatar(username: selectedName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@$selectedName',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        'Active session sender',
                        style: TextStyle(
                            fontSize: 11, color: Colors.green.shade600),
                      ),
                    ],
                  ),
                ),
                // Allow clearing only when session is open
                if (_sessionManager.state == SessionState.open)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() {
                      _sessionManager.clearSender();
                      _transferStream = null;
                      _handshakeDone = false;
                      _handshaking = false;
                    }),
                    tooltip: 'Change sender',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 6),
                Icon(Icons.lock_rounded,
                    color: Colors.green.shade600, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Handshake status / transfer waiting — the 'Share Public Key'
          // step is now invisible: it completes automatically above and
          // this inline widget reflects the result.
          _handshaking
              ? const Row(
                  children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Opening secure channel…',
                        style: TextStyle(fontSize: 13)),
                  ],
                )
              : _handshakeDone
                  ? _transferStatusWidget(selectedUid, selectedName)
                  : const SizedBox.shrink(),
        ],
      );
    }

    // ── No sender selected: show find button ─────────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrypButton(
          icon: const Icon(Icons.search_rounded),
          label: const Text('🔗 Find & Select Sender'),
          onPressed: _step2Done ? _openFindSenderSheet : null,
          color: cs.secondary,
          sessionState: _sessionManager.state != SessionState.open
              ? _sessionManager.state
              : null,
        ),
        if (_loadingFriends) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ] else if (_connectedFriends.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Connected Senders',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final f in _connectedFriends)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ConnectedRow(username: f.username),
            ),
        ],
      ],
    );
  }

  /// Transfer waiting / incoming StreamBuilder — embedded in Step 2 done
  /// state once the atomic handshake completes.  The 'Share Public Key' step
  /// (formerly a separate Step 3 card) is now fully invisible.
  Widget _transferStatusWidget(String senderUid, String senderName) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _transferStream!,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Stream error: ${snap.error}',
              style: TextStyle(fontSize: 12, color: cs.error));
        }

        final hasPending = snap.hasData && snap.data!.docs.isNotEmpty;

        if (hasPending && !_sessionLocked) {
          final doc = snap.data!.docs.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_sessionLocked) {
              _handleIncomingTransfer(doc.id, doc.data());
            }
          });
          return Row(
            children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '🔐 Incoming file — preparing decrypt…',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: cs.primary),
                ),
              ),
            ],
          );
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.inbox_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waiting for file from @$senderName',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Secure channel established ✅',
                      style: TextStyle(
                          fontSize: 11, color: Colors.green.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        );
      },
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _isReadyToReceive) {
          _sessionManager.wipeSession(onBuffersWipe: wipeAll);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Receive File',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.lock_outline_rounded),
              tooltip: 'RSA Key Manager',
              onPressed: _openKeyManager,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Step 1: Key Generation ──────────────────────────────────
              StepCard(
                step: 1,
                title: 'Key Generation',
                done: _step1Done,
                child: _step1Content(),
              ),
              const SizedBox(height: 16),

              // ── Step 2: Ready State ─────────────────────────────────────
              AnimatedOpacity(
                opacity: _step1Done ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: StepCard(
                  step: 2,
                  title: 'Ready State',
                  done: _step2Done,
                  child: _step2Content(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Step 3: The Connect ─────────────────────────────────────
              AnimatedOpacity(
                opacity: _step2Done ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: StepCard(
                  step: 3,
                  title: 'The Connect',
                  done: _step3Done,
                  child: _step3Content(),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Inline helper widgets ────────────────────────────────────────────────────

class _KeyInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _KeyInfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle_outline,
            size: 14, color: Colors.green.shade600),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.green.shade700),
        ),
        Text(value,
            style: TextStyle(
                fontSize: 12, color: Colors.green.shade700)),
      ],
    );
  }
}

class _ConnectedRow extends StatelessWidget {
  final String username;

  const _ConnectedRow({required this.username});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          UserAvatar(username: username),
          const SizedBox(width: 10),
          Expanded(
            child: Text('@$username',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Icon(Icons.check_circle_rounded,
              color: Colors.green.shade600, size: 18),
          const SizedBox(width: 4),
          Text('Connected',
              style: TextStyle(
                  fontSize: 12, color: Colors.green.shade600)),
        ],
      ),
    );
  }
}

// ─── Find Sender bottom sheet ─────────────────────────────────────────────────

class _FindSenderSheet extends StatefulWidget {
  final KeyRepository service;
  final List<UserModel> initialConnected;
  final VoidCallback onConnectionMade;
  /// Called when the user taps "Select" on a connected sender.
  /// The sheet closes itself before calling this.
  final void Function(UserModel) onSenderSelected;

  const _FindSenderSheet({
    required this.service,
    required this.initialConnected,
    required this.onConnectionMade,
    required this.onSenderSelected,
  });

  @override
  State<_FindSenderSheet> createState() => _FindSenderSheetState();
}

class _FindSenderSheetState extends State<_FindSenderSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<UserModel> _results = [];
  bool _isSearching = false;
  final Map<String, String> _statusCache = {};
  late List<UserModel> _connectedList;

  @override
  void initState() {
    super.initState();
    _connectedList = List.from(widget.initialConnected);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await widget.service.searchUsers(value.trim());
      for (final u in results) {
        if (!_statusCache.containsKey(u.uid)) {
          final s = await widget.service.getConnectionStatus(u.uid);
          _statusCache[u.uid] = s ?? 'none';
        }
      }
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _connect(String uid, UserModel user) async {
    setState(() => _statusCache[uid] = 'connecting');
    try {
      await widget.service.sendConnectionRequest(uid);
      if (mounted) {
        setState(() {
          _statusCache[uid] = 'accepted';
          if (!_connectedList.any((u) => u.uid == uid)) {
            _connectedList.add(user);
          }
        });
        widget.onConnectionMade();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusCache[uid] = 'none');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _connectButton(String status, String uid, UserModel user) {
    if (status == 'accepted') {
      return Chip(
        label: const Text('Connected'),
        backgroundColor: Colors.green.withValues(alpha: 0.12),
        labelStyle: const TextStyle(
            color: Colors.green, fontWeight: FontWeight.w600),
        avatar:
            const Icon(Icons.check, color: Colors.green, size: 16),
        side: BorderSide.none,
      );
    }
    if (status == 'connecting') {
      return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => _connect(uid, user),
      child: const Text('Connect'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          const BottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Icon(Icons.link_rounded,
                    color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  '🔗 Find Sender',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search by username…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _results = []);
                            },
                          )
                        : null,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Search results
                if (_results.isEmpty && !_isSearching)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        _searchCtrl.text.isEmpty
                            ? 'Type a username to search'
                            : 'No users found',
                        style:
                            TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  for (final user in _results)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: UserAvatar(
                            username: user.username.isNotEmpty
                                ? user.username
                                : '?'),
                        title: Text(
                          user.username.isNotEmpty
                              ? '@${user.username}'
                              : 'Unknown',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(user.email),
                        trailing: _connectButton(
                          _statusCache[user.uid] ?? 'none',
                          user.uid,
                          user,
                        ),
                      ),
                    ),

                // Connected senders section — tap "Select" to lock in sender
                if (_connectedList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Text(
                      'Select Your Sender',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final f in _connectedList)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: UserAvatar(username: f.username),
                        title: Text(
                          '@${f.username}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Tap Select to start session',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant),
                        ),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14),
                            minimumSize: const Size(0, 36),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onSenderSelected(f);
                          },
                          child: const Text('Select'),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── RSA Key Manager bottom sheet ────────────────────────────────────────────

class _KeyManagerSheet extends StatefulWidget {
  final AuthRepository authService;
  final KeyRepository connService;
  final bool hasPrivateKey;
  final bool hasPublicKey;

  const _KeyManagerSheet({
    required this.authService,
    required this.connService,
    required this.hasPrivateKey,
    required this.hasPublicKey,
  });

  @override
  State<_KeyManagerSheet> createState() => _KeyManagerSheetState();
}

class _KeyManagerSheetState extends State<_KeyManagerSheet> {
  List<Map<String, dynamic>> _sentKeys = [];
  List<Map<String, dynamic>> _receivedKeys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sent = await widget.connService.getSentKeyTransfers();
      final received = await widget.connService.getReceivedKeys();
      if (mounted) {
        setState(() {
          _sentKeys = sent;
          _receivedKeys = received;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load keys: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          const BottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Icon(Icons.lock_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '🔒 RSA Key Manager',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: scroll,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      Text(
                        'My Keypair',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _OwnKeyStatusCard(
                        hasPrivateKey: widget.hasPrivateKey,
                        hasPublicKey: widget.hasPublicKey,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'My Public Key — Sent To',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_sentKeys.isEmpty)
                        _EmptyHint(
                          icon: Icons.send_outlined,
                          text:
                              'Your public key hasn\'t been sent to anyone yet.\n'
                              'Use "Share Public Key" (Step 3) to send it.',
                        )
                      else
                        ..._sentKeys.map((k) => _SentKeyCard(entry: k)),
                      const SizedBox(height: 20),
                      Text(
                        'Public Keys Received',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_receivedKeys.isEmpty)
                        const _EmptyHint(
                          icon: Icons.key_off_outlined,
                          text:
                              'No public keys received from other users yet.',
                        )
                      else
                        ..._receivedKeys.map(
                          (k) => _ReceivedKeyCard(
                            entry: k,
                            connService: widget.connService,
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _OwnKeyStatusCard extends StatelessWidget {
  final bool hasPrivateKey;
  final bool hasPublicKey;

  const _OwnKeyStatusCard(
      {required this.hasPrivateKey, required this.hasPublicKey});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _KeyRow(
              icon: Icons.key_rounded,
              label: 'Private key',
              value: hasPrivateKey
                  ? '● Stored securely on this device'
                  : '✗ Not generated yet',
              valueColor: hasPrivateKey
                  ? Colors.green.shade700
                  : Theme.of(context).colorScheme.error,
            ),
            const Divider(height: 18),
            _KeyRow(
              icon: Icons.cloud_done_outlined,
              label: 'Public key',
              value: hasPublicKey
                  ? '● Saved to Firestore'
                  : '✗ Not generated yet',
              valueColor: hasPublicKey
                  ? Colors.green.shade700
                  : Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  const _KeyRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 18,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
              Text(value,
                  style:
                      TextStyle(fontSize: 13, color: valueColor)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SentKeyCard extends StatelessWidget {
  final Map<String, dynamic> entry;

  const _SentKeyCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final toUsername = entry['toUsername'] as String? ?? 'Unknown';
    final sentAt = entry['sentAt'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: UserAvatar(username: toUsername),
        title: Text(toUsername,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          sentAt != null ? _fmt(sentAt.toDate()) : 'Just now',
          style:
              TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: Chip(
          label: const Text('Sent'),
          avatar:
              const Icon(Icons.check, color: Colors.green, size: 14),
          backgroundColor: Colors.green.withValues(alpha: 0.1),
          labelStyle: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w600,
              fontSize: 12),
          side: BorderSide.none,
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

class _ReceivedKeyCard extends StatefulWidget {
  final Map<String, dynamic> entry;
  final KeyRepository connService;

  const _ReceivedKeyCard(
      {required this.entry, required this.connService});

  @override
  State<_ReceivedKeyCard> createState() => _ReceivedKeyCardState();
}

class _ReceivedKeyCardState extends State<_ReceivedKeyCard> {
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.connService
        .isKeySaved(widget.entry['fromUserId'] as String)
        .then((v) {
      if (mounted) setState(() => _saved = v);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.connService.saveReceivedKey(
      widget.entry['fromUserId'] as String,
      widget.entry['publicKey'] as String,
    );
    if (mounted) {
      setState(() {
        _saved = true;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${widget.entry['fromUsername']}\'s public key saved locally!'),
          backgroundColor: Colors.green.shade600,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final from =
        widget.entry['fromUsername'] as String? ?? 'Unknown';
    final sentAt = widget.entry['sentAt'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: UserAvatar(username: from),
        title: Text(from,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          sentAt != null
              ? '${sentAt.toDate().day}/${sentAt.toDate().month}/${sentAt.toDate().year}'
              : 'Just now',
          style:
              TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: _saved
            ? Chip(
                label: const Text('Saved'),
                avatar: const Icon(Icons.check_circle,
                    color: Colors.green, size: 14),
                backgroundColor:
                    Colors.green.withValues(alpha: 0.1),
                labelStyle: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w600),
                side: BorderSide.none,
              )
            : _saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(
                    onPressed: _save,
                    child: const Text('Save Key'),
                  ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
