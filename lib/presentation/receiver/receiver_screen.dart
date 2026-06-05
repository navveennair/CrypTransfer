import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/biometric_helper.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../core/utils/session_manager.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../../data/services/encryption_service.dart';
import '../vault/rsa_key_manager_screen.dart';
import '../widgets/shared_widgets.dart';
import 'receiver_transfer_screen.dart';

class ReceiverScreen extends StatefulWidget {
  final String? preFilledSenderUid;
  final String? preFilledSenderUsername;
  final String? handshakeDocId;

  const ReceiverScreen({
    super.key,
    this.preFilledSenderUid,
    this.preFilledSenderUsername,
    this.handshakeDocId,
  });

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen>
    with SecurityLifecycleMixin<ReceiverScreen>, WidgetsBindingObserver {
  final _authService = AuthRepository();
  final _connService = KeyRepository();
  final _transferRepo = TransferRepository();
  final _sessionManager = SessionManager();

  bool _hasPrivateKey = false;
  bool _hasPublicKey = false;
  bool _checkingStatus = true;

  bool _isReadyToReceive = false;
  bool _loadingReadyState = true;
  bool _isTogglingReady = false;

  List<UserModel> _connectedFriends = [];
  StreamSubscription<List<UserModel>>? _friendsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingHandshakeSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _senderPresenceSub;
  bool _senderPresenceConfirmed = false;
  bool _handshaking = false;
  bool _handshakeDone = false;

  bool _sessionLocked = false;
  bool _incomingHandled = false;
  UserModel? _pendingPrefilledSender;

  String? _incomingTransferId;
  String? _incomingFileName;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _transferStream;
  String? _handshakeDocId;

  // Survives the close/reopen cycle so receiver can auto-reconnect to the
  // same sender without manual re-selection.
  UserModel? _lastConnectedSender;

  bool get _step1Done => _hasPrivateKey && _hasPublicKey;
  bool get _step2Done => _isReadyToReceive;
  bool get _step3Done =>
      _sessionManager.activeSenderUid != null && _handshakeDone;

  @override
  void initState() {
    super.initState();
    _handshakeDocId = widget.handshakeDocId;
    WidgetsBinding.instance.addObserver(this);
    _sessionManager.stateNotifier.addListener(_onSessionStateChanged);
    _checkKeyStatus().then((_) {
      if (mounted && widget.preFilledSenderUid != null) {
        // D-14: defer sender selection until mailbox is open.
        // _onSenderSelected needs the public key in Firestore (written by
        // setupReceiverSession inside _onToggleReady(true)). Storing here and
        // consuming in _onToggleReady(true) prevents the KeyNotFoundException.
        setState(() {
          _pendingPrefilledSender = UserModel(
            uid: widget.preFilledSenderUid!,
            username: widget.preFilledSenderUsername ?? '',
            email: '',
            phone: '',
          );
        });
      }
    });
    _subscribeToFriends();
    _loadReadyToReceiveState();
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _incomingHandshakeSub?.cancel();
    _senderPresenceSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _sessionManager.stateNotifier.removeListener(_onSessionStateChanged);
    EncryptionService.unbindSession();
    _sessionManager.dispose();
    super.dispose();
  }

  void _subscribeToFriends() {
    _friendsSub = _connService.streamConnectedFriends().listen(
      (friends) {
        if (mounted) setState(() => _connectedFriends = friends);
      },
      onError: (_) {}, // silently ignore errors — list stays at last known value
    );
  }

  void _startIncomingHandshakeListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _incomingHandshakeSub = _connService
        .streamIncomingHandshakes(uid)
        .listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;

      // Auto-select first incoming handshake with a sender
      final doc = snap.docs.firstWhere(
        (d) => (d.data()['senderId'] as String?)?.isNotEmpty ?? false,
        orElse: () => snap.docs.first,
      );

      final senderUid = doc.data()['senderId'] as String?;
      // Get sender username from fromUsername field (set by selectSenderHandshake)
      final senderUsername = doc.data()['fromUsername'] as String? ?? 'Sender';

      if (senderUid != null && senderUid.isNotEmpty && !_handshakeDone && !_handshaking) {
        // Auto-select this sender (guard prevents re-entry from the doc the
        // call itself creates, which would loop indefinitely).
        _onSenderSelected(UserModel(
          uid: senderUid,
          username: senderUsername,
          email: '',
          phone: '',
        ));
      }
    });
  }

  void _stopIncomingHandshakeListener() {
    _incomingHandshakeSub?.cancel();
    _incomingHandshakeSub = null;
  }

  void _onSessionStateChanged() {
    if (!mounted) return;
    setState(() {});
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
    // Do not fire the kill-switch while a transfer is locked in progress.
    // The private key must survive until DecryptScreen completes or fails.
    if (_isReadyToReceive && !_sessionLocked) {
      _sessionManager.handleLifecycleState(state, onBuffersWipe: wipeAll);
    }
  }

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

  Future<void> _loadReadyToReceiveState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadingReadyState = false);
      return;
    }
    setState(() => _loadingReadyState = true);
    try {
      final isReady = await _authService.getIsReadyToReceive(uid);
      if (mounted) {
        setState(() {
          _isReadyToReceive = isReady;
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
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() => _isTogglingReady = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isTogglingReady = false);
        _showError('Not authenticated.');
        return;
      }

      if (value) {
        await EncryptionService.setupReceiverSession(uid);
        EncryptionService.bindSession(_sessionManager.stateStream, uid);
        // Signal readiness: receiver's mailbox is now open, authorizing any sender
        await _connService.setReadyToReceive(true);
        if (mounted) {
          setState(() {
            _isReadyToReceive = true;
            _hasPrivateKey = true;
            _hasPublicKey = true;
          });
          // Start listening for incoming handshakes (automatic sender detection)
          _startIncomingHandshakeListener();
          // Consume deferred pre-fill: public key is now in Firestore,
          // so selectSenderHandshake will succeed (D-14).
          final pending = _pendingPrefilledSender;
          if (pending != null) {
            _pendingPrefilledSender = null;
            _onSenderSelected(pending);
          } else if (_lastConnectedSender != null) {
            // Auto-reconnect: receiver re-opened after a previous session with a
            // known sender. New RSA key pair is in Firestore — re-run handshake
            // so sender gets the updated public key without manual re-selection.
            _onSenderSelected(_lastConnectedSender!);
          }
        }
      } else {
        final confirmed = await _showCloseSessionDialog();
        if (!confirmed) {
          setState(() => _isTogglingReady = false);
          return;
        }
        // Stop listening for incoming handshakes and sender presence
        _stopIncomingHandshakeListener();
        _senderPresenceSub?.cancel();
        _senderPresenceSub = null;
        _senderPresenceConfirmed = false;
        // Signal unreadiness: receiver's mailbox is now closed
        await _connService.setReadyToReceive(false);
        EncryptionService.unbindSession();
        await EncryptionService.closeReceiverSession(uid);
        wipeAll();
        _sessionManager.reset();
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
            _handshakeDocId = null;
          });
        }
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isTogglingReady = false);
    }
  }

  Future<bool> _showCloseSessionDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BottomSheetHandle(),
            const SizedBox(height: 10),
            Icon(Icons.power_settings_new_rounded, size: 48, color: Theme.of(ctx).colorScheme.tertiary),
            const SizedBox(height: 16),
            Text(
              'Close Mailbox?',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'This will delete your public key from Firebase and wipe your session data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: CrypButton(
                    label: const Text('Cancel'),
                    onPressed: () => Navigator.pop(ctx, false),
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    height: 44,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CrypButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    label: const Text('Close Session'),
                    color: Theme.of(ctx).colorScheme.tertiary,
                    height: 44,
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

Future<void> _onSenderSelected(UserModel sender) async {
    _sessionManager.selectSender(sender.uid, sender.username);
    final receiverUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _transferStream = _transferRepo.watchPendingTransfersFromSender(
      receiverUid,
      sender.uid,
    );
    setState(() => _handshaking = true);
    try {
      final docId = await _connService.selectSenderHandshake(
        senderUid: sender.uid,
        senderUsername: sender.username,
      );
      _handshakeDocId = docId;

      // Role validation: if roles are assigned, verify the handshake doc names us as receiver.
      if (docId.isNotEmpty && mounted) {
        try {
          final handshakeDoc =
              await FirebaseFirestore.instance.collection(FirebaseConstants.handshakes).doc(docId).get();
          final handshakeReceiverUid = handshakeDoc.data()?['receiverUid'] as String?;
          if (handshakeReceiverUid != null && handshakeReceiverUid.isNotEmpty && handshakeReceiverUid != receiverUid) {
            if (mounted) {
              setState(() => _handshaking = false);
              _showError('Role conflict — partner chose a different role. Try again.');
              await _onToggleReady(false);
            }
            return;
          }
        } catch (e) {
          // Silently ignore read errors; role validation is optional
        }
      }

      if (mounted) {
        _lastConnectedSender = sender;
        setState(() {
          _handshakeDone = true;
          _handshaking = false;
        });
        _startSenderPresenceWatch(sender.uid, receiverUid);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _handshaking = false);
        _showError(e.toString());
      }
    }
  }

  void _startSenderPresenceWatch(String senderUid, String receiverUid) {
    _senderPresenceSub?.cancel();
    _senderPresenceConfirmed = false;
    _senderPresenceSub = FirebaseFirestore.instance
        .collection(FirebaseConstants.users)
        .doc(senderUid)
        .snapshots()
        .listen((snap) {
      if (!mounted || _sessionLocked) return;
      final field = snap.data()?[FirebaseConstants.pendingSenderFor] as String?;
      if (field == receiverUid) {
        _senderPresenceConfirmed = true;
      } else if (_senderPresenceConfirmed) {
        // Sender was confirmed present, now their claim is gone — they abandoned.
        _senderPresenceSub?.cancel();
        _senderPresenceSub = null;
        _senderPresenceConfirmed = false;
        setState(() {
          _sessionManager.clearSender();
          _transferStream = null;
          _handshakeDone = false;
          _handshaking = false;
          _handshakeDocId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sender left the session.')),
        );
      }
    });
  }

  Future<void> _handleIncomingTransfer(
      String transferId, Map<String, dynamic> data) async {
    if (_sessionLocked) return;
    final fileName = data['fileName'] as String? ?? 'file';
    final senderId = data['senderId'] as String?;

    if (_sessionManager.activeSenderUid != null &&
        senderId != _sessionManager.activeSenderUid) {
      return;
    }

    if (mounted) {
      setState(() {
        _incomingTransferId = transferId;
        _incomingFileName = fileName;
        _sessionLocked = true;
      });
      _sessionManager.lock();
      _sessionManager.setDecrypting();
    }
  }

  Future<void> _openKeyManager() async {
    final authenticated = await BiometricHelper.authenticate('Access RSA Key Manager');
    if (!authenticated || !mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _KeyManagerSheet(
        authService: _authService,
        connService: _connService,
        hasPrivateKey: _hasPrivateKey,
        hasPublicKey: _hasPublicKey,
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

  Widget _step1Content() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_checkingStatus) return const LinearProgressIndicator();
    if (_step1Done) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(14),
            color: cs.secondary.withValues(alpha: 0.1),
            borderColor: cs.secondary.withValues(alpha: 0.2),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_rounded, color: cs.secondary, size: 18),
                    const SizedBox(width: 8),
                    Text('RSA-2048 Ready', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.secondary)),
                  ],
                ),
                const SizedBox(height: 8),
                _KeyInfoRow('Status', 'Local keypair verified'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CrypButton(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Regenerate Keys'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RsaKeyManagerScreen()),
            ).then((_) => _checkKeyStatus()),
            color: cs.primary,
            height: 48,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.tertiary.withValues(alpha: 0.1),
            border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RsaKeyManagerScreen()),
            ).then((_) => _checkKeyStatus()),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No RSA keys found — tap to generate',
                    style: TextStyle(color: cs.tertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _step2Content() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_loadingReadyState) return const LinearProgressIndicator();
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isReadyToReceive ? cs.secondary.withValues(alpha: 0.1) : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isReadyToReceive ? 'Ready to receive' : 'Not receiving',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: _isReadyToReceive,
            onChanged: _step1Done && !_isTogglingReady ? _onToggleReady : null,
            activeThumbColor: cs.secondary,
          ),
        ],
      ),
    );
  }

  Widget _step3Content() {
    final cs = Theme.of(context).colorScheme;
    final selectedUid = _sessionManager.activeSenderUid;
    final selectedName = _sessionManager.activeSenderUsername;

    if (selectedUid != null && selectedName != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(14),
            color: cs.primary.withValues(alpha: 0.1),
            child: Row(
              children: [
                UserAvatar(username: selectedName, radius: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$selectedName', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Selected Sender', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (_sessionManager.state == SessionState.open)
                  Tooltip(
                    message: 'Change sender',
                    child: IconButton(
                      icon: const Icon(Icons.sync_alt_rounded, size: 20),
                      onPressed: () => setState(() {
                        _sessionManager.clearSender();
                        _transferStream = null;
                        _handshakeDone = false;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _handshaking
              ? const LinearProgressIndicator()
              : _handshakeDone
                  ? _transferStatusWidget(selectedUid, selectedName)
                  : const SizedBox.shrink(),
        ],
      );
    }

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty_rounded, color: cs.onSurfaceVariant, size: 20),
          const SizedBox(width: 14),
          const Expanded(child: Text('Waiting for connected sender…', style: TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _transferStatusWidget(String senderUid, String senderName) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _transferStream!,
      builder: (context, snap) {
        final cs = Theme.of(context).colorScheme;
        if (snap.hasError) {
          return GlassContainer(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Transfer monitor error — tap to retry',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
          );
        }
        final hasPending = snap.hasData && snap.data!.docs.isNotEmpty;
        if (hasPending && !_sessionLocked && !_incomingHandled) {
          _incomingHandled = true; // set synchronously before post-frame to prevent re-entry
          final doc = snap.data!.docs.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleIncomingTransfer(doc.id, doc.data());
          });
        }

        return GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.hourglass_empty_rounded, color: cs.onSurfaceVariant, size: 20),
              const SizedBox(width: 14),
              const Expanded(child: Text('Waiting for file transfer…', style: TextStyle(fontSize: 13))),
              if (hasPending) const CircularProgressIndicator(strokeWidth: 2),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Treat empty string the same as null: assignTransferRole() returns '' when no
    // real handshake doc was created, so canPop must not be blocked by an empty ID.
    final hasRealHandshakeDoc = _handshakeDocId != null && _handshakeDocId!.isNotEmpty;
    return PopScope(
      canPop: _isReadyToReceive ? false : !hasRealHandshakeDoc,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_sessionLocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Cannot close session — transfer in progress.'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          } else if (_isReadyToReceive) {
            // Mailbox open — require confirmation before wipe.
            final navigator = Navigator.of(context);
            _showCloseSessionDialog().then((confirmed) {
              if (confirmed && mounted) {
                navigator.pop();
                _sessionManager.wipeSession(onBuffersWipe: wipeAll);
              }
            });
          }
        } else {
          // D-04: didPop==true means canPop was true (mailbox closed).
          // Always attempt to clear stale role fields on back-navigation.
          // clearTransferRoles() handles empty/null docId safely.
          _connService
              .clearTransferRoles(handshakeDocId: _handshakeDocId ?? '')
              .catchError((_) {});
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Receive File', style: Theme.of(context).textTheme.titleMedium),
          centerTitle: true,
          actions: [
            Tooltip(
              message: _isReadyToReceive ? 'Key manager unavailable while mailbox is open' : 'Manage RSA keys',
              child: IconButton(
                icon: const Icon(Icons.settings_suggest_rounded),
                onPressed: _isReadyToReceive ? null : _openKeyManager,
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              // ── Welcome banner ────────────────────────────────
              GlassContainer(
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
                      child: Icon(Icons.download_rounded, color: cs.primary, size: 24),
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
                            'Establish handshakes and receive data.',
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
              ),
              const SizedBox(height: 32),

              AnimatedOpacity(
                opacity: _isReadyToReceive ? 0.4 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: _isReadyToReceive,
                  child: StepCard(
                      step: 1,
                      title: 'RSA Keypair',
                      done: _step1Done,
                      child: _step1Content()),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedOpacity(
                opacity: _step1Done ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: StepCard(step: 2, title: 'Receive Mode', done: _step2Done, child: _step2Content()),
              ),
              const SizedBox(height: 16),
              AnimatedOpacity(
                opacity: _step2Done ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: StepCard(step: 3, title: 'Sender Handshake', done: _step3Done, child: _step3Content()),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _KeyInfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.circle, size: 6, color: cs.secondary),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _FindSenderSheet extends StatefulWidget {
  final KeyRepository service;
  final List<UserModel> initialConnected;
  final VoidCallback onConnectionMade;
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
  final Map<String, String> _statusCache = {};
  final Map<String, bool> _sendingKey = {};
  late List<UserModel> _connectedList;
  StreamSubscription<List<UserModel>>? _friendsSub;

  @override
  void initState() {
    super.initState();
    _connectedList = List.from(widget.initialConnected);
    // Subscribe to live friend updates so the sheet reflects changes without
    // needing to close and reopen.
    _friendsSub = widget.service.streamConnectedFriends().listen(
      (friends) {
        if (mounted) setState(() => _connectedList = friends);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await widget.service.searchUsers(value.trim());
        for (final u in results) {
          if (!_statusCache.containsKey(u.uid)) {
            try {
              final s = await widget.service.getConnectionStatus(u.uid);
              _statusCache[u.uid] = s ?? 'none';
            } catch (_) {
              _statusCache[u.uid] = 'none';
            }
          }
        }
        if (mounted) setState(() => _results = results);
      } catch (_) {
        // Search failed silently — leave results empty
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
          if (!_connectedList.any((u) => u.uid == uid)) _connectedList.add(user);
        });
        widget.onConnectionMade();
      }
    } catch (e) {
      if (mounted) setState(() => _statusCache[uid] = 'none');
    }
  }

  Future<void> _sendKey(UserModel user) async {
    setState(() => _sendingKey[user.uid] = true);
    try {
      // All handshake creation now happens in _onSenderSelected via selectSenderHandshake()
      // This method just triggers the selection flow.
      if (mounted) {
        setState(() => _sendingKey[user.uid] = false);
        Navigator.pop(context);
        widget.onSenderSelected(user);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingKey[user.uid] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          const BottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search senders…',
                prefixIcon: const Icon(Icons.search_rounded),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: cs.primary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_results.isNotEmpty) ...[
                  Text('Search Results', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  ..._results.map((u) => Card(
                    child: ListTile(
                      leading: UserAvatar(username: u.username),
                      title: Text(u.username),
                      trailing: _statusCache[u.uid] == 'accepted'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Friend',
                                style: TextStyle(
                                  color: cs.secondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _sendingKey[u.uid] == true
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : CrypButton(
                                      label: const Text('Send'),
                                      onPressed: () => _sendKey(u),
                                      color: cs.secondary,
                                      height: 40,
                                    ),
                            ],
                          )
                        : CrypButton(label: const Text('Connect'), onPressed: () => _connect(u.uid, u), color: cs.primary, height: 40),
                    ),
                  )),
                ],
                if (_connectedList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Active Connections', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  ..._connectedList.map((f) => Card(
                    child: ListTile(
                      leading: UserAvatar(username: f.username),
                      title: Text(f.username),
                      trailing: CrypButton(
                        label: const Text('Select', style: TextStyle(fontSize: 12)),
                        onPressed: () { Navigator.pop(context); widget.onSenderSelected(f); },
                        color: cs.primary,
                        height: 36,
                      ),
                    ),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyManagerSheet extends StatefulWidget {
  final AuthRepository authService;
  final KeyRepository connService;
  final bool hasPrivateKey;
  final bool hasPublicKey;
  const _KeyManagerSheet({required this.authService, required this.connService, required this.hasPrivateKey, required this.hasPublicKey});
  @override
  State<_KeyManagerSheet> createState() => _KeyManagerSheetState();
}

class _KeyManagerSheetState extends State<_KeyManagerSheet> {
  List<Map<String, dynamic>> _sentKeys = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final sent = await widget.connService.getSentKeyTransfers();
    if (mounted) setState(() { _sentKeys = sent; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GlassContainer(
      borderRadius: 24,
      child: Column(
        children: [
          const BottomSheetHandle(),
          Expanded(
            child: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('RSA Identity', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _OwnKeyStatusCard(hasPrivateKey: widget.hasPrivateKey, hasPublicKey: widget.hasPublicKey),
                const SizedBox(height: 24),
                Text('Shared Keys', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                ..._sentKeys.map((k) => ListTile(title: Text(k['toUsername'] ?? 'User'), subtitle: Text('Access Granted', style: TextStyle(color: cs.secondary)))),
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
  const _OwnKeyStatusCard({required this.hasPrivateKey, required this.hasPublicKey});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          _Row('Device Private Key', hasPrivateKey ? 'Encrypted & Local' : 'Missing'),
          const Divider(),
          _Row('Firestore Public Key', hasPublicKey ? 'Published' : 'Offline'),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String l; final String v;
  const _Row(this.l, this.v);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ]),
  );
  }
}
