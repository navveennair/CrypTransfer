import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'connection_service.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  final _service = ConnectionService();
  List<Map<String, dynamic>> _receivedKeys = [];
  bool _loadingKeys = true;

  @override
  void initState() {
    super.initState();
    _loadReceivedKeys();
  }

  Future<void> _loadReceivedKeys() async {
    setState(() => _loadingKeys = true);
    final keys = await _service.getReceivedKeys();
    if (mounted) {
      setState(() {
        _receivedKeys = keys;
        _loadingKeys = false;
      });
    }
  }

  void _openKeyManagerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _KeyManagerSheet(service: _service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Receiver',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadReceivedKeys,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── RSA Key Manager button ────────────────────────
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _openKeyManagerSheet,
              icon: const Icon(Icons.vpn_key_rounded),
              label: Text('RSA Key Manager',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 28),

            // ── Received RSA Keys ─────────────────────────────
            Row(
              children: [
                Icon(Icons.key_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Received RSA Keys',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh, color: cs.primary, size: 20),
                  onPressed: _loadReceivedKeys,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_loadingKeys)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_receivedKeys.isEmpty)
              _EmptyState(
                icon: Icons.vpn_key_off_outlined,
                message:
                    'No RSA keys received yet.\nAsk a friend to send you their public key.',
              )
            else
              ...(_receivedKeys.map((k) => _ReceivedKeyCard(
                    fromUsername: k['fromUsername'] ?? 'Unknown',
                    fromUserId: k['fromUserId'] ?? '',
                    publicKey: k['publicKey'] ?? '',
                    sentAt: k['sentAt'] as Timestamp?,
                    service: _service,
                  ))),
          ],
        ),
      ),
    );
  }
}

// ─── RSA Key Manager bottom sheet ────────────────────────────────────────────

class _KeyManagerSheet extends StatefulWidget {
  final ConnectionService service;

  const _KeyManagerSheet({required this.service});

  @override
  State<_KeyManagerSheet> createState() => _KeyManagerSheetState();
}

class _KeyManagerSheetState extends State<_KeyManagerSheet> {
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;
  // uid → true while sending
  final Map<String, bool> _sending = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final friends = await widget.service.getConnectedFriends();
    if (mounted) {
      setState(() {
        _friends = friends;
        _loading = false;
      });
    }
  }

  Future<void> _sendKey(String toUserId, String toUsername) async {
    setState(() => _sending[toUserId] = true);
    try {
      await widget.service.sendPublicKey(toUserId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Public key sent to $toUsername!'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending[toUserId] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RSA Key Manager',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 18),
                ),
                Text(
                  'Send your public key to a connected friend so they can encrypt files for you.',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _friends.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No connected friends yet.\nGo to Sender → Establish Connection first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _friends.length,
                        itemBuilder: (_, i) {
                          final f = _friends[i];
                          final uid = f['uid'] as String;
                          final username = f['username'] ?? 'Unknown';
                          final isSending = _sending[uid] == true;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: cs.primaryContainer,
                                child: Text(
                                  username.isNotEmpty
                                      ? username[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(username,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              trailing: isSending
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            Colors.green.shade600,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () =>
                                          _sendKey(uid, username),
                                      child: const Text('Send Key'),
                                    ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Received key card ────────────────────────────────────────────────────────

class _ReceivedKeyCard extends StatefulWidget {
  final String fromUsername;
  final String fromUserId;
  final String publicKey;
  final Timestamp? sentAt;
  final ConnectionService service;

  const _ReceivedKeyCard({
    required this.fromUsername,
    required this.fromUserId,
    required this.publicKey,
    required this.sentAt,
    required this.service,
  });

  @override
  State<_ReceivedKeyCard> createState() => _ReceivedKeyCardState();
}

class _ReceivedKeyCardState extends State<_ReceivedKeyCard> {
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checkSaved();
  }

  Future<void> _checkSaved() async {
    final saved = await widget.service.isKeySaved(widget.fromUserId);
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _saveKey() async {
    setState(() => _saving = true);
    await widget.service.saveReceivedKey(widget.fromUserId, widget.publicKey);
    if (mounted) {
      setState(() {
        _saved = true;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${widget.fromUsername}\'s public key saved locally!'),
          backgroundColor: Colors.green.shade600,
        ),
      );
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'Just now';
    final dt = ts.toDate();
    return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Text(
                widget.fromUsername.isNotEmpty
                    ? widget.fromUsername[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.fromUsername,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Received ${_formatDate(widget.sentAt)}',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _saved
                ? Chip(
                    label: const Text('Saved'),
                    avatar: const Icon(Icons.check_circle,
                        color: Colors.green, size: 16),
                    backgroundColor:
                        Colors.green.withValues(alpha: 0.12),
                    labelStyle: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w600),
                  )
                : _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                        ),
                        onPressed: _saveKey,
                        child: const Text('Save Key'),
                      ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 52, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                TextStyle(color: cs.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
