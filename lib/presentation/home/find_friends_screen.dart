import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/models/user_model.dart';
import '../../data/repositories/handshake_repository.dart';
import '../../data/repositories/key_repository.dart';
import '../widgets/shared_widgets.dart';

Future<bool?> _showDisconnectDialog(BuildContext context, String username) {
  final cs = Theme.of(context).colorScheme;
  return showDialog<bool>(
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
            Icon(Icons.link_off_rounded, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text(
              'Disconnect?',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Remove @$username from your connections?',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: CrypButton(
                    label: const Text('Cancel'),
                    onPressed: () => Navigator.pop(ctx, false),
                    color: cs.onSurfaceVariant,
                    height: 44,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CrypButton(
                    label: const Text('Disconnect'),
                    color: cs.error,
                    onPressed: () => Navigator.pop(ctx, true),
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

class FindFriendsScreen extends StatefulWidget {
  const FindFriendsScreen({super.key});

  @override
  State<FindFriendsScreen> createState() => _FindFriendsScreenState();
}

class _FindFriendsScreenState extends State<FindFriendsScreen> {
  final _searchController = TextEditingController();
  final _keyRepo = KeyRepository(); // search only
  final _hsRepo = HandshakeRepository();

  List<UserModel> _searchResults = [];
  // Each entry: {uid, username, email, docId}
  List<Map<String, dynamic>> _connectedUsers = [];
  // Each entry: {docId, proposerId, proposerUsername}
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _searching = false;

  StreamSubscription<QuerySnapshot>? _proposerSub;
  StreamSubscription<QuerySnapshot>? _partnerSub;
  StreamSubscription<QuerySnapshot>? _pendingSub;

  @override
  void initState() {
    super.initState();
    _subscribeConnections();
    _subscribePending();
  }

  @override
  void dispose() {
    _proposerSub?.cancel();
    _partnerSub?.cancel();
    _pendingSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeConnections() {
    final fromProposer = <Map<String, dynamic>>[];
    final fromPartner = <Map<String, dynamic>>[];

    void merge() {
      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      for (final entry in [...fromProposer, ...fromPartner]) {
        if (seen.add(entry['uid'] as String)) merged.add(entry);
      }
      if (mounted) setState(() => _connectedUsers = merged);
    }

    _proposerSub = _hsRepo.streamActiveConnectionsAsProposer().listen((snap) {
      fromProposer
        ..clear()
        ..addAll(snap.docs.map((doc) {
          final d = doc.data();
          return {
            'uid': d['partnerId'],
            'username': d['partnerUsername'] ?? '',
            'email': '',
            'docId': doc.id,
          };
        }));
      merge();
    }, onError: (_) {
      _proposerSub?.cancel();
      _proposerSub = null;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _subscribeConnections();
      });
    });

    _partnerSub = _hsRepo.streamActiveConnectionsAsPartner().listen((snap) {
      fromPartner
        ..clear()
        ..addAll(snap.docs.map((doc) {
          final d = doc.data();
          return {
            'uid': d['proposerId'],
            'username': d['proposerUsername'] ?? '',
            'email': '',
            'docId': doc.id,
          };
        }));
      merge();
    }, onError: (_) {
      _partnerSub?.cancel();
      _partnerSub = null;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _subscribeConnections();
      });
    });
  }

  void _subscribePending() {
    _pendingSub = _hsRepo.streamIncomingPending().listen((snap) {
      final requests = snap.docs.map((doc) {
        final d = doc.data();
        return {
          'docId': doc.id,
          'proposerId': d['proposerId'] as String? ?? '',
          'proposerUsername': d['proposerUsername'] as String? ?? 'Unknown',
        };
      }).toList();
      if (mounted) setState(() => _pendingRequests = requests);
    }, onError: (_) {
      _pendingSub?.cancel();
      _pendingSub = null;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _subscribePending();
      });
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await _keyRepo.searchUsers(query);
      if (mounted) setState(() => _searchResults = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> req) async {
    try {
      await _hsRepo.acceptProposal(
          req['docId'] as String, req['proposerId'] as String);
      // Auto-clear the awareness notification so the bell badge doesn't linger.
      _hsRepo
          .clearConnectionRequestNotif(req['proposerId'] as String)
          .ignore();
      if (mounted) {
        setState(() {
          _pendingRequests.removeWhere((r) => r['docId'] == req['docId']);
          final alreadyConnected = _connectedUsers
              .any((u) => u['uid'] == req['proposerId']);
          if (!alreadyConnected) {
            _connectedUsers.add({
              'uid': req['proposerId'],
              'username': req['proposerUsername'] ?? '',
              'email': '',
              'docId': req['docId'],
            });
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Connection established!'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _declineRequest(Map<String, dynamic> req) async {
    try {
      await _hsRepo.rejectProposal(req['docId'] as String);
      _hsRepo
          .clearConnectionRequestNotif(req['proposerId'] as String)
          .ignore();
      if (mounted) {
        setState(() =>
            _pendingRequests.removeWhere((r) => r['docId'] == req['docId']));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _disconnect(Map<String, dynamic> conn) async {
    final username = conn['username'] as String;
    final uid = conn['uid'] as String;

    final confirmed = await _showDisconnectDialog(context, username);
    if (confirmed != true) return;

    try {
      await _hsRepo.disconnectFromUser(uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected from @$username',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'Connections',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Welcome banner ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: GlassContainer(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
                color: cs.secondary.withValues(alpha: 0.1),
                borderColor: cs.secondary.withValues(alpha: 0.2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.secondary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.people_alt_rounded,
                          color: cs.secondary, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Network',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurface),
                          ),
                          Text(
                            'Manage connections for secure transfers.',
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
            ),
          ),

          // Search Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _searchController,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search by username...',
                  prefixIcon: Icon(Icons.search, color: cs.primary),
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _performSearch('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
                onSubmitted: _performSearch,
                textInputAction: TextInputAction.search,
              ),
            ),
          ),

          // My Connections Section
          if (_connectedUsers.isNotEmpty &&
              _searchController.text.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Row(
                  children: [
                    Icon(Icons.people_outline_rounded,
                        size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'My Connections',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final conn = _connectedUsers[i];
                  final username = conn['username'] as String;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 6),
                    child: GlassContainer(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor:
                              cs.primary.withValues(alpha: 0.1),
                          foregroundColor: cs.primary,
                          child: Text(username.isNotEmpty
                              ? username[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(
                          '@$username',
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.link_off_rounded,
                              color: cs.error, size: 22),
                          onPressed: () => _disconnect(conn),
                          tooltip: 'Disconnect',
                        ),
                      ),
                      ),
                    ),
                  );
                },
                childCount: _connectedUsers.length,
              ),
            ),
          ],

          // Pending Requests Section
          if (_pendingRequests.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Row(
                  children: [
                    Icon(Icons.mark_email_unread_outlined,
                        size: 18, color: cs.secondary),
                    const SizedBox(width: 8),
                    Text(
                      'Incoming Requests',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final req = _pendingRequests[i];
                  final proposerUsername =
                      req['proposerUsername'] as String;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 6),
                    child: GlassContainer(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      borderColor: cs.secondary.withValues(alpha: 0.3),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: cs.secondary,
                          foregroundColor: cs.onSecondary,
                          child: Text(proposerUsername.isNotEmpty
                              ? proposerUsername[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(
                          '@$proposerUsername',
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface),
                        ),
                        subtitle: Text('Wants to connect with you',
                            style:
                                TextStyle(color: cs.onSurfaceVariant)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.close_rounded,
                                  color: cs.error, size: 20),
                              onPressed: () => _declineRequest(req),
                              tooltip: 'Decline',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            const SizedBox(width: 4),
                            CrypButton(
                              onPressed: () => _acceptRequest(req),
                              label: const Text('Accept',
                                  style: TextStyle(fontSize: 11)),
                              color: cs.secondary,
                              height: 30,
                              width: 70,
                            ),
                          ],
                        ),
                      ),
                      ),
                    ),
                  );
                },
                childCount: _pendingRequests.length,
              ),
            ),
          ],

          // Search Results Label
          if (_searchResults.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Text(
                  'Search Results',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Search Results List
          if (_searching)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searchResults.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _SearchResultTile(
                  key: ValueKey(_searchResults[i].uid),
                  user: _searchResults[i],
                  hsRepo: _hsRepo,
                ),
                childCount: _searchResults.length,
              ),
            )
          else if (_searchController.text.isNotEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_search_rounded,
                        size: 64, color: cs.outline),
                    const SizedBox(height: 16),
                    Text(
                      'No users found',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.connect_without_contact_rounded,
                        size: 80,
                        color: cs.primary.withValues(alpha: 0.1)),
                    const SizedBox(height: 20),
                    Text(
                      'Connect with Friends',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 48),
                      child: Text(
                        'Secure transfers require a bidirectional connection. Search for friends to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }
}

// ── Search result tile with reactive handshake status ────────────────────────

class _SearchResultTile extends StatefulWidget {
  final UserModel user;
  final HandshakeRepository hsRepo;

  const _SearchResultTile({
    super.key,
    required this.user,
    required this.hsRepo,
  });

  @override
  State<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<_SearchResultTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseOpacity;
  StreamSubscription<({String status, String docId})?>? _statusSub;
  ({String status, String docId})? _current;
  bool _isSending = false;
  bool _isDisconnecting = false;
  bool _streamReady = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseOpacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _statusSub = widget.hsRepo
        .streamHandshakeWithUser(widget.user.uid)
        .listen(_onStatus, onError: (_) {});
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onStatus(({String status, String docId})? data) {
    if (!mounted) return;
    setState(() { _current = data; _streamReady = true; });
    if (data?.status == 'pending_sent') {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  Future<void> _sendRequest() async {
    setState(() => _isSending = true);
    try {
      await widget.hsRepo.sendProposal(
        partnerUid: widget.user.uid,
        partnerUsername: widget.user.username,
      );
      // Stream will emit pending_sent automatically after Firestore write.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _accept(String docId) async {
    try {
      await widget.hsRepo.acceptProposal(docId, widget.user.uid);
      widget.hsRepo
          .clearConnectionRequestNotif(widget.user.uid)
          .ignore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Connection established!'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _disconnect(String docId) async {
    final confirmed = await _showDisconnectDialog(context, widget.user.username);
    if (confirmed != true) return;
    setState(() => _isDisconnecting = true);
    try {
      await widget.hsRepo.disconnectFromUser(widget.user.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Disconnected from @${widget.user.username}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDisconnecting = false);
    }
  }

  Widget _buildTrailing(ColorScheme cs) {
    if (_isSending || _isDisconnecting || !_streamReady) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final status = _current?.status;
    final docId = _current?.docId;

    if (status == 'accepted') {
      return PopupMenuButton<String>(
        onSelected: (val) {
          if (val == 'disconnect' && docId != null) _disconnect(docId);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'disconnect',
            child: Row(
              children: [
                Icon(Icons.link_off_rounded, color: cs.error, size: 20),
                const SizedBox(width: 8),
                Text('Disconnect', style: TextStyle(color: cs.error)),
              ],
            ),
          ),
        ],
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: cs.secondary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  color: cs.secondary, size: 16),
              const SizedBox(width: 4),
              Text('Connected',
                  style: TextStyle(
                      color: cs.secondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              Icon(Icons.arrow_drop_down,
                  color: cs.secondary, size: 18),
            ],
          ),
        ),
      );
    }

    if (status == 'pending_sent') {
      return FadeTransition(
        opacity: _pulseOpacity,
        child: Text(
          'Pending',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      );
    }

    if (status == 'pending_received') {
      return CrypButton(
        label: const Text('Accept', style: TextStyle(fontSize: 11)),
        onPressed: docId != null ? () => _accept(docId) : null,
        color: cs.secondary,
        height: 30,
        width: 70,
      );
    }

    return CrypButton(
      label: const Text('Connect', style: TextStyle(fontSize: 11)),
      onPressed: _sendRequest,
      color: cs.primary,
      height: 30,
      width: 70,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: GlassContainer(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: cs.surfaceContainerHigh,
            foregroundColor: cs.primary,
            child: Text(widget.user.username[0].toUpperCase()),
          ),
          title: Text(
            '@${widget.user.username}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          subtitle: Text(
            widget.user.email,
            style:
                TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          trailing: _buildTrailing(cs),
        ),
        ),
      ),
    );
  }
}
