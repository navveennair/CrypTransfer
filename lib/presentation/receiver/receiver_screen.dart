import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/utils/biometric_helper.dart';
import '../../data/repositories/key_repository.dart';
import 'decrypt_screen.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  final _authService = AuthRepository();
  final _connService = KeyRepository();

  bool _hasPrivateKey = false;
  bool _hasPublicKey = false;
  bool _checkingStatus = true;

  List<UserModel> _connectedFriends = [];
  bool _loadingFriends = false;
  Set<String> _keySentTo = {};

  bool _isReadyToReceive = false;

  StreamSubscription<QuerySnapshot>? _transferSub;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _checkKeyStatus();
    _loadConnectedFriends();
    _loadReadyToReceiveState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _startTransferListener());
  }

  @override
  void dispose() {
    _transferSub?.cancel();
    super.dispose();
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

  // ─── Connected friends + Send Key ────────────────────────────────────────

  Future<void> _loadConnectedFriends() async {
    setState(() => _loadingFriends = true);
    try {
      final friends = await _connService.getConnectedFriends();
      final sent = await _connService.getSentKeyTransfers();
      final sentUids = sent.map((s) => s['toUserId'] as String).toSet();
      if (mounted) {
        setState(() {
          _connectedFriends = friends;
          _keySentTo = sentUids;
          _loadingFriends = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _sendKey(String toUserId, String toUsername) async {
    try {
      await _connService.sendPublicKey(
        toUserId: toUserId,
        toUsername: toUsername,
      );
      if (mounted) {
        setState(() => _keySentTo.add(toUserId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RSA Key sent to $toUsername'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  // ─── Ready to Receive toggle ─────────────────────────────────────────────

  Future<void> _loadReadyToReceiveState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _isReadyToReceive =
              doc.data()?['isReadyToReceive'] as bool? ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleReadyToReceive() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isReadyToReceive': !_isReadyToReceive,
        'readySince':
            !_isReadyToReceive ? FieldValue.serverTimestamp() : null,
      });
      if (mounted) setState(() => _isReadyToReceive = !_isReadyToReceive);
    } catch (e) {
      if (mounted) _showError('Could not update ready status: $e');
    }
  }

  // ─── Pending transfer listener ───────────────────────────────────────────

  void _startTransferListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _transferSub = FirebaseFirestore.instance
        .collection('transfers')
        .where('receiverId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      if (!_initialLoadDone) {
        _initialLoadDone = true;
        return; // skip docs that existed on startup
      }

      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          _showIncomingDialog(change.doc.id, data);
          break; // one dialog at a time
        }
      }
    });
  }

  void _showIncomingDialog(String transferId, Map<String, dynamic> data) {
    final fileName = data['fileName'] as String? ?? 'file';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.file_download_rounded, size: 36),
        title: const Text('Incoming Transfer'),
        content: Text(
          'You have received an encrypted file:\n\n'
          '"$fileName"\n\n'
          'Would you like to open it now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DecryptScreen(transferId: transferId),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  // ─── RSA Key Generation ───────────────────────────────────────────────────

  Future<void> _generateKeys() async {
    final alreadyHas = _hasPrivateKey;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.vpn_key_rounded, size: 36),
        title: Text(alreadyHas ? 'Regenerate RSA Keys?' : 'Generate RSA Keys'),
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(alreadyHas ? 'Regenerate' : 'Generate'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _showProgressDialog('Generating RSA-2048 keypair…\nThis may take a moment.');
    try {
      await _authService.generateAndStoreKeyPair();
      // Push updated public key to all existing connections
      await _connService.resyncPublicKeyToAllConnections();
      if (!mounted) return;
      Navigator.pop(context); // dismiss dialog
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

  // ─── Establish Connection ─────────────────────────────────────────────────

  void _openConnectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ConnectionSheet(service: _connService),
    );
  }

  // ─── RSA Key Manager (biometric gated) ───────────────────────────────────

  Future<void> _openKeyManager() async {
    final authenticated = await BiometricHelper.authenticate(
        'Authenticate to access the RSA Key Manager');
    if (!authenticated || !mounted) return;

    showModalBottomSheet(
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
    showDialog(
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Receiver',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Key status card ───────────────────────────────
            _checkingStatus
                ? const LinearProgressIndicator()
                : _KeyStatusCard(
                    hasPrivateKey: _hasPrivateKey,
                    hasPublicKey: _hasPublicKey,
                  ),
            const SizedBox(height: 24),

            // ── Action buttons ────────────────────────────────
            _ActionTile(
              icon: Icons.vpn_key_rounded,
              color: _hasPrivateKey ? Colors.orange.shade700 : Colors.green.shade700,
              title: _hasPrivateKey ? 'Regenerate RSA Keys' : 'Generate RSA Keys',
              subtitle: 'Create your 2048-bit RSA-OAEP keypair',
              badge: _hasPrivateKey ? '✓ Key stored' : null,
              onTap: _generateKeys,
            ),
            const SizedBox(height: 12),

            // ── Ready to Receive toggle ───────────────────────
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.inbox_rounded,
                  color: _isReadyToReceive ? Colors.green : Colors.grey,
                ),
                title: const Text('Ready to Receive Files'),
                subtitle: Text(
                  _isReadyToReceive
                      ? 'Senders can now send you files'
                      : 'Toggle on to receive files',
                ),
                trailing: Switch(
                  value: _isReadyToReceive,
                  onChanged: (_) => _toggleReadyToReceive(),
                  activeThumbColor: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 12),

            _ActionTile(
              icon: Icons.person_search_rounded,
              color: Colors.green.shade700,
              title: 'Establish Connection',
              subtitle: 'Find a sender and share your public key',
              onTap: _hasPublicKey ? _openConnectionSheet : null,
              disabledHint: _hasPublicKey
                  ? null
                  : 'Generate RSA keys first',
            ),

            // ── Send RSA Key to connected friends ─────────────
            if (_hasPublicKey &&
                (_loadingFriends || _connectedFriends.isNotEmpty)) ...[
              const SizedBox(height: 16),
              _SendKeySection(
                loading: _loadingFriends,
                friends: _connectedFriends,
                keySentTo: _keySentTo,
                onSendKey: _sendKey,
              ),
            ],
            const SizedBox(height: 12),

            _ActionTile(
              icon: Icons.lock_rounded,
              color: Colors.indigo.shade700,
              title: 'RSA Key Manager',
              subtitle: 'View key status  ·  Face ID / PIN required',
              onTap: _openKeyManager,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Key status card ──────────────────────────────────────────────────────────

class _KeyStatusCard extends StatelessWidget {
  final bool hasPrivateKey;
  final bool hasPublicKey;

  const _KeyStatusCard({
    required this.hasPrivateKey,
    required this.hasPublicKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allGood = hasPrivateKey && hasPublicKey;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allGood
            ? Colors.green.withValues(alpha: 0.1)
            : cs.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: allGood ? Colors.green.shade300 : cs.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allGood ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
                color: allGood ? Colors.green.shade700 : cs.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                allGood ? 'Keys Ready' : 'Setup Required',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: allGood ? Colors.green.shade800 : cs.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatusRow(
            label: 'Private key',
            ok: hasPrivateKey,
            okText: 'Stored on device',
            failText: 'Not generated',
          ),
          const SizedBox(height: 4),
          _StatusRow(
            label: 'Public key',
            ok: hasPublicKey,
            okText: 'Saved to Firestore',
            failText: 'Not generated',
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String okText;
  final String failText;

  const _StatusRow({
    required this.label,
    required this.ok,
    required this.okText,
    required this.failText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 16,
          color: ok ? Colors.green.shade700 : Colors.grey,
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        Text(
          ok ? okText : failText,
          style: TextStyle(
            fontSize: 13,
            color: ok ? Colors.green.shade700 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// ─── Action tile ──────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;
  final String? disabledHint;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.badge,
    this.onTap,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onTap == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Material(
        color: disabled ? cs.surfaceContainerHighest : color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        disabledHint ?? subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Connection bottom sheet ──────────────────────────────────────────────────

class _ConnectionSheet extends StatefulWidget {
  final KeyRepository service;

  const _ConnectionSheet({required this.service});

  @override
  State<_ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<_ConnectionSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<UserModel> _results = [];
  bool _isSearching = false;
  final Map<String, String> _statusCache = {};

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
        final uid = u.uid;
        if (!_statusCache.containsKey(uid)) {
          final s = await widget.service.getConnectionStatus(uid);
          _statusCache[uid] = s ?? 'none';
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

  Future<void> _connect(String uid) async {
    setState(() => _statusCache[uid] = 'connecting');
    try {
      await widget.service.sendConnectionRequest(uid);
      if (mounted) setState(() => _statusCache[uid] = 'accepted');
    } catch (e) {
      if (mounted) {
        setState(() => _statusCache[uid] = 'none');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Establish Connection',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 18)),
                Text(
                  'Find a sender by username. Your public RSA key will be '
                  'shared automatically when you connect.',
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
            child: _results.isEmpty && !_isSearching
                ? Center(
                    child: Text(
                      _searchCtrl.text.isEmpty
                          ? 'Type a username to search'
                          : 'No users found',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final user = _results[i];
                      final uid = user.uid;
                      final status = _statusCache[uid] ?? 'none';
                      final username = user.username.isNotEmpty ? user.username : 'Unknown';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              username.isNotEmpty
                                  ? username[0].toUpperCase()
                                  : '?',
                              style:
                                  TextStyle(color: cs.onPrimaryContainer),
                            ),
                          ),
                          title: Text(username,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(user.email),
                          trailing: _connectionButton(status, uid),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _connectionButton(String status, String uid) {
    if (status == 'accepted') {
      return Chip(
        label: const Text('Connected'),
        backgroundColor: Colors.green.withValues(alpha: 0.12),
        labelStyle: const TextStyle(
            color: Colors.green, fontWeight: FontWeight.w600),
        avatar: const Icon(Icons.check, color: Colors.green, size: 16),
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
          backgroundColor: Colors.green.shade600),
      onPressed: () => _connect(uid),
      child: const Text('Connect'),
    );
  }
}

// ─── Key manager bottom sheet ─────────────────────────────────────────────────

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
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Icon(Icons.lock_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Text('RSA Key Manager',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 18)),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // ── Own key status ──────────────────────
                      Text('My Keypair',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 13,
                              color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      _OwnKeyStatusCard(
                        hasPrivateKey: widget.hasPrivateKey,
                        hasPublicKey: widget.hasPublicKey,
                      ),
                      const SizedBox(height: 20),

                      // ── Sent to senders ─────────────────────
                      Text(
                        'My Public Key — Sent To',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      if (_sentKeys.isEmpty)
                        _EmptyHint(
                          icon: Icons.send_outlined,
                          text: 'Your public key hasn\'t been sent to anyone yet.\n'
                              'Use "Establish Connection" to connect with senders.',
                        )
                      else
                        ..._sentKeys.map((k) => _SentKeyCard(entry: k)),
                      const SizedBox(height: 20),

                      // ── Received keys ───────────────────────
                      Text(
                        'Public Keys Received',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      if (_receivedKeys.isEmpty)
                        _EmptyHint(
                          icon: Icons.key_off_outlined,
                          text: 'No public keys received from other users yet.',
                        )
                      else
                        ..._receivedKeys.map((k) => _ReceivedKeyCard(
                              entry: k,
                              connService: widget.connService,
                            )),
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
    final cs = Theme.of(context).colorScheme;
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
              valueColor: hasPrivateKey ? Colors.green.shade700 : cs.error,
            ),
            const Divider(height: 18),
            _KeyRow(
              icon: Icons.cloud_done_outlined,
              label: 'Public key',
              value: hasPublicKey
                  ? '● Saved to Firestore'
                  : '✗ Not generated yet',
              valueColor: hasPublicKey ? Colors.green.shade700 : cs.error,
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
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
              Text(value,
                  style: TextStyle(fontSize: 13, color: valueColor)),
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
    final toUsername = entry['toUsername'] ?? 'Unknown';
    final sentAt = entry['sentAt'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(
            toUsername.isNotEmpty ? toUsername[0].toUpperCase() : '?',
            style: TextStyle(color: cs.onPrimaryContainer),
          ),
        ),
        title: Text(toUsername,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          sentAt != null ? _fmt(sentAt.toDate()) : 'Just now',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: Chip(
          label: const Text('Sent'),
          avatar: const Icon(Icons.check, color: Colors.green, size: 14),
          backgroundColor: Colors.green.withValues(alpha: 0.1),
          labelStyle: const TextStyle(
              color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
        .isKeySaved(widget.entry['fromUserId'])
        .then((v) { if (mounted) setState(() => _saved = v); });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.connService.saveReceivedKey(
        widget.entry['fromUserId'], widget.entry['publicKey']);
    if (mounted) {
      setState(() { _saved = true; _saving = false; });
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
    final from = widget.entry['fromUsername'] ?? 'Unknown';
    final sentAt = widget.entry['sentAt'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(from.isNotEmpty ? from[0].toUpperCase() : '?',
              style: TextStyle(color: cs.onPrimaryContainer)),
        ),
        title: Text(from,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          sentAt != null
              ? '${sentAt.toDate().day}/${sentAt.toDate().month}/${sentAt.toDate().year}'
              : 'Just now',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: _saved
            ? Chip(
                label: const Text('Saved'),
                avatar: const Icon(Icons.check_circle,
                    color: Colors.green, size: 14),
                backgroundColor: Colors.green.withValues(alpha: 0.1),
                labelStyle: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w600),
              )
            : _saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
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
              style:
                  TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Send Key section ─────────────────────────────────────────────────────────

class _SendKeySection extends StatelessWidget {
  final bool loading;
  final List<UserModel> friends;
  final Set<String> keySentTo;
  final void Function(String uid, String username) onSendKey;

  const _SendKeySection({
    required this.loading,
    required this.friends,
    required this.keySentTo,
    required this.onSendKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return const LinearProgressIndicator();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Send RSA Key to Connected Senders',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        ...friends.map((f) {
          final uid = f.uid;
          final username = f.username.isNotEmpty ? f.username : 'Unknown';
          final sent = keySentTo.contains(uid);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(color: cs.onPrimaryContainer),
                ),
              ),
              title: Text(username,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: sent
                  ? Chip(
                      label: const Text('Sent ✅'),
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                      labelStyle: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w600),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade600),
                      onPressed: () => onSendKey(uid, username),
                      child: const Text('Send Key'),
                    ),
            ),
          );
        }),
      ],
    );
  }
}
