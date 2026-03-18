import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'connection_service.dart';

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  final _service = ConnectionService();
  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loadingFriends = true);
    final friends = await _service.getConnectedFriends();
    if (mounted) {
      setState(() {
        _friends = friends;
        _loadingFriends = false;
      });
    }
  }

  void _openSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SearchSheet(
        service: _service,
        onConnectionAdded: _loadFriends,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sender', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadFriends,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Establish Connection button ────────────────────
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _openSearchSheet,
              icon: const Icon(Icons.person_search_rounded),
              label: Text('Establish Connection',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 28),

            // ── Connected Friends ──────────────────────────────
            Row(
              children: [
                Icon(Icons.group_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Connected Friends',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh, color: cs.primary, size: 20),
                  onPressed: _loadFriends,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_loadingFriends)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ))
            else if (_friends.isEmpty)
              _EmptyState(
                icon: Icons.people_outline,
                message: 'No connections yet.\nTap "Establish Connection" to find friends.',
              )
            else
              ...(_friends.map((f) => _FriendCard(
                    username: f['username'] ?? 'Unknown',
                    uid: f['uid'],
                    onSendFile: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Send File to ${f['username']} — coming in Week 2'),
                        ),
                      );
                    },
                  ))),
          ],
        ),
      ),
    );
  }
}

// ─── Search bottom sheet ──────────────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  final ConnectionService service;
  final VoidCallback onConnectionAdded;

  const _SearchSheet(
      {required this.service, required this.onConnectionAdded});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  // uid → 'none' | 'pending' | 'accepted'
  final Map<String, String> _statusCache = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
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
        if (!_statusCache.containsKey(u['uid'])) {
          final status = await widget.service.getConnectionStatus(u['uid']);
          _statusCache[u['uid']] = status ?? 'none';
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

  Future<void> _addFriend(String uid) async {
    setState(() => _statusCache[uid] = 'accepted');
    try {
      await widget.service.sendConnectionRequest(uid);
      widget.onConnectionAdded();
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
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
            child: Text(
              'Find Users',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
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
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _results = []);
                            },
                          )
                        : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty && !_isSearching
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'Type a username to search'
                          : 'No users found',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final user = _results[i];
                      final uid = user['uid'] as String;
                      final status = _statusCache[uid] ?? 'none';
                      final username = user['username'] ?? 'Unknown';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
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
                          subtitle: Text(user['email'] ?? ''),
                          trailing: status == 'accepted'
                              ? Chip(
                                  label: const Text('Connected'),
                                  backgroundColor:
                                      Colors.green.withValues(alpha: 0.15),
                                  labelStyle: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600),
                                )
                              : FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green.shade600,
                                  ),
                                  onPressed: () => _addFriend(uid),
                                  child: const Text('Add'),
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

// ─── Friend card ──────────────────────────────────────────────────────────────

class _FriendCard extends StatelessWidget {
  final String username;
  final String uid;
  final VoidCallback onSendFile;

  const _FriendCard({
    required this.username,
    required this.uid,
    required this.onSendFile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Text(
            username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: TextStyle(
                color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(username,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Connected'),
        trailing: FilledButton.tonal(
          onPressed: onSendFile,
          child: const Text('Send File'),
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
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
