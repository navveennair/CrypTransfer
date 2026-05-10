import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_theme.dart';
import '../../core/constants/firebase_constants.dart';
import '../../core/utils/biometric_helper.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../core/utils/session_manager.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/services/encryption_service.dart';
import '../vault/rsa_key_manager_screen.dart';
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

  bool _hasPrivateKey = false;
  bool _hasPublicKey = false;
  bool _checkingStatus = true;

  bool _isReadyToReceive = false;
  bool _loadingReadyState = true;
  bool _isTogglingReady = false;

  List<UserModel> _connectedFriends = [];
  StreamSubscription<List<UserModel>>? _friendsSub;
  bool _handshaking = false;
  bool _handshakeDone = false;

  bool _sessionLocked = false;
  bool _incomingHandled = false;

  String? _incomingTransferId;
  String? _incomingFileName;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _transferStream;

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
    _subscribeToFriends();
    _loadReadyToReceiveState();
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
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
    if (_isReadyToReceive) {
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
        const SnackBar(content: Text('Cannot close session — transfer in progress.')),
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
        if (mounted) {
          setState(() {
            _isReadyToReceive = true;
            _hasPrivateKey = true;
            _hasPublicKey = true;
          });
        }
      } else {
        final confirmed = await _showCloseSessionDialog();
        if (!confirmed) {
          setState(() => _isTogglingReady = false);
          return;
        }
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
            const Icon(Icons.power_settings_new_rounded, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Close Mailbox?',
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
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
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    label: const Text('Close Session'),
                    color: Colors.orange,
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

  void _openFindSenderSheet() {
    if (_sessionManager.activeSenderUid != null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FindSenderSheet(
        service: _connService,
        initialConnected: _connectedFriends,
        onConnectionMade: () {}, // no-op: stream keeps the list live
        onSenderSelected: _onSenderSelected,
      ),
    );
  }

  Future<void> _onSenderSelected(UserModel sender) async {
    _sessionManager.selectSender(sender.uid, sender.username);
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
      }
    } catch (e) {
      if (mounted) {
        setState(() => _handshaking = false);
        _showError(e.toString());
      }
    }
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
    if (_checkingStatus) return const LinearProgressIndicator();
    if (_step1Done) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassContainer(
            padding: const EdgeInsets.all(14),
            color: Colors.green.withValues(alpha: 0.1),
            borderColor: Colors.green.withValues(alpha: 0.2),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text('RSA-2048 Ready', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 8),
                _KeyInfoRow('Status', 'Local keypair verified'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Regenerate Keys'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RsaKeyManagerScreen()),
            ).then((_) => _checkKeyStatus()),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
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
            color: Colors.amber.withValues(alpha: 0.1),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RsaKeyManagerScreen()),
            ).then((_) => _checkKeyStatus()),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No RSA keys found — tap to generate',
                    style: TextStyle(color: Colors.amber),
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
    if (_loadingReadyState) return const LinearProgressIndicator();
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isReadyToReceive ? Colors.green.withValues(alpha: 0.1) : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isReadyToReceive ? 'Ready to receive' : 'Not receiving',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          Switch(
            value: _isReadyToReceive,
            onChanged: _step1Done && !_isTogglingReady ? _onToggleReady : null,
            activeThumbColor: Colors.green,
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
                      const Text('Selected Sender', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                if (_sessionManager.state == SessionState.open)
                  IconButton(
                    icon: const Icon(Icons.sync_alt_rounded, size: 20),
                    onPressed: () => setState(() {
                      _sessionManager.clearSender();
                      _transferStream = null;
                      _handshakeDone = false;
                    }),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassButton(
          icon: const Icon(Icons.link_rounded, size: 20),
          label: const Text('Find & Select Sender'),
          onPressed: _step2Done ? _openFindSenderSheet : null,
          color: AppTheme.primaryBlue,
        ),
        if (_connectedFriends.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Frequent Senders', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          ..._connectedFriends.take(3).map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ConnectedRow(username: f.username),
          )),
        ],
      ],
    );
  }

  Widget _transferStatusWidget(String senderUid, String senderName) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _transferStream!,
      builder: (context, snap) {
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
              const Icon(Icons.hourglass_empty_rounded, color: AppTheme.primaryBlue, size: 20),
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _isReadyToReceive) {
          _sessionManager.wipeSession(onBuffersWipe: wipeAll);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Receive File', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_suggest_rounded),
              onPressed: _openKeyManager,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              // ── Welcome banner ────────────────────────────────
              GlassContainer(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                color: cs.primary.withValues(alpha: 0.1),
                borderColor: cs.primary.withValues(alpha: 0.2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.download_rounded, color: cs.primary, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Secure Inbox',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Establish handshakes and receive data.',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              StepCard(step: 1, title: 'RSA Keypair', done: _step1Done, child: _step1Content()),
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
    return Row(
      children: [
        const Icon(Icons.circle, size: 6, color: Colors.green),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ConnectedRow extends StatelessWidget {
  final String username;
  const _ConnectedRow({required this.username});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: 12,
      child: Row(
        children: [
          UserAvatar(username: username, radius: 14),
          const SizedBox(width: 10),
          Text('@$username', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const Spacer(),
          const Icon(Icons.bolt_rounded, color: Colors.amber, size: 16),
        ],
      ),
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
  final Set<String> _keySentTo = {};
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
      await widget.service.publishRSAPublicKey(user.uid);
      if (mounted) {
        setState(() {
          _sendingKey[user.uid] = false;
          _keySentTo.add(user.uid);
        });
        // Brief tick display, then close sheet and complete the handshake.
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          Navigator.pop(context);
          widget.onSenderSelected(user);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingKey[user.uid] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send key: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              decoration: const InputDecoration(
                hintText: 'Search senders…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_results.isNotEmpty) ...[
                  Text('Search Results', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  ..._results.map((u) => Card(
                    child: ListTile(
                      leading: UserAvatar(username: u.username),
                      title: Text(u.username),
                      trailing: _statusCache[u.uid] == 'accepted'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Friend',
                                style: TextStyle(
                                  color: Colors.green,
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
                                : _keySentTo.contains(u.uid)
                                  ? const Icon(Icons.check_rounded, color: Colors.green, size: 22)
                                  : FilledButton(
                                      onPressed: () => _sendKey(u),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Send'),
                                    ),
                            ],
                          )
                        : TextButton(onPressed: () => _connect(u.uid, u), child: const Text('Connect')),
                    ),
                  )),
                ],
                if (_connectedList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Active Connections', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  ..._connectedList.map((f) => Card(
                    child: ListTile(
                      leading: UserAvatar(username: f.username),
                      title: Text(f.username),
                      trailing: GlassButton(
                        label: const Text('Select', style: TextStyle(fontSize: 12)),
                        onPressed: () { Navigator.pop(context); widget.onSenderSelected(f); },
                        color: AppTheme.primaryBlue,
                        borderRadius: 8,
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
    return GlassContainer(
      borderRadius: 24,
      child: Column(
        children: [
          const BottomSheetHandle(),
          Expanded(
            child: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('RSA Identity', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _OwnKeyStatusCard(hasPrivateKey: widget.hasPrivateKey, hasPublicKey: widget.hasPublicKey),
                const SizedBox(height: 24),
                Text('Shared Keys', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold)),
                ..._sentKeys.map((k) => ListTile(title: Text(k['toUsername'] ?? 'User'), subtitle: const Text('Access Granted', style: TextStyle(color: Colors.green)))),
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
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      color: AppTheme.darkSurface,
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ]),
  );
}
