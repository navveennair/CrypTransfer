import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/user_model.dart';
import '../../data/repositories/key_repository.dart';

class FindFriendsScreen extends StatefulWidget {
  const FindFriendsScreen({super.key});

  @override
  State<FindFriendsScreen> createState() => _FindFriendsScreenState();
}

class _FindFriendsScreenState extends State<FindFriendsScreen> {
  final _searchController = TextEditingController();
  final _repo = KeyRepository();
  
  List<UserModel> _searchResults = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  final Map<String, String?> _statuses = {};
  bool _searching = false;
  bool _loadingRequests = true;

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final reqs = await _repo.getPendingRequests();
      if (mounted) setState(() => _pendingRequests = reqs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await _repo.searchUsers(query);
      for (final user in res) {
        final status = await _repo.getConnectionStatus(user.uid);
        _statuses[user.uid] = status;
      }
      if (mounted) setState(() => _searchResults = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(UserModel user) async {
    setState(() => _statuses[user.uid] = 'sending...');
    try {
      await _repo.sendConnectionRequest(user.uid);
      final status = await _repo.getConnectionStatus(user.uid);
      if (mounted) {
        setState(() => _statuses[user.uid] = status);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request sent to @${user.username}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statuses[user.uid] = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> req) async {
    final senderId = req['senderId'] as String;
    try {
      await _repo.acceptConnectionRequest(req['docId'], senderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection established!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadPendingRequests();
        if (_statuses.containsKey(senderId)) {
          _statuses[senderId] = 'accepted';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept: $e')),
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
          'Establish Connections',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          // Search Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.inter(),
                decoration: InputDecoration(
                  hintText: 'Search by username...',
                  prefixIcon: Icon(Icons.search, color: cs.primary),
                  filled: true,
                  fillColor: cs.surfaceContainerLowest,
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
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                ),
                onSubmitted: _performSearch,
                textInputAction: TextInputAction.search,
              ),
            ),
          ),

          // Pending Requests Section
          if (_loadingRequests)
            const SliverToBoxAdapter(child: LinearProgressIndicator())
          else if (_pendingRequests.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Row(
                  children: [
                    Icon(Icons.mark_email_unread_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Incoming Requests',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.5,
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
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        child: Text(req['senderUsername'][0].toUpperCase()),
                      ),
                      title: Text(
                        '@${req['senderUsername']}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Wants to connect with you'),
                      trailing: FilledButton(
                        onPressed: () => _acceptRequest(req),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Accept'),
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
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.5,
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
                (ctx, i) {
                  final user = _searchResults[i];
                  final status = _statuses[user.uid];
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: cs.surfaceContainerHigh,
                        child: Text(user.username[0].toUpperCase()),
                      ),
                      title: Text(
                        '@${user.username}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(user.email, style: const TextStyle(fontSize: 12)),
                      trailing: _buildAction(user, status, cs),
                    ),
                  );
                },
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
                    Icon(Icons.person_search_rounded, size: 64, color: cs.outlineVariant),
                    const SizedBox(height: 16),
                    Text(
                      'No users found',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
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
                    Icon(Icons.connect_without_contact_rounded, size: 80, color: cs.primary.withValues(alpha: 0.1)),
                    const SizedBox(height: 20),
                    Text(
                      'Connect with Friends',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        'Secure transfers require a bidirectional connection. Search for friends to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
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

  Widget _buildAction(UserModel user, String? status, ColorScheme cs) {
    if (status == 'accepted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
            SizedBox(width: 4),
            Text('Connected', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      );
    }

    if (status == 'pending_sent') {
      return Text(
        'Pending',
        style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13),
      );
    }

    if (status == 'pending_received') {
      return FilledButton(
        onPressed: () => _loadPendingRequests(), // refresh
        style: FilledButton.styleFrom(
          backgroundColor: cs.secondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('View Request'),
      );
    }

    if (status == 'sending...') {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return OutlinedButton(
      onPressed: () => _sendRequest(user),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Connect'),
    );
  }
}
