import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../widgets/shared_widgets.dart';

class UserManagementList extends StatefulWidget {
  const UserManagementList({super.key});

  @override
  State<UserManagementList> createState() => _UserManagementListState();
}

class _UserManagementListState extends State<UserManagementList> {
  final _adminRepo = AdminRepository();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return StreamBuilder<List<UserModel>>(
      stream: _adminRepo.streamAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading data', style: TextStyle(color: cs.error)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final all = snapshot.data!.where((u) =>
          u.username.isNotEmpty &&
          u.email.isNotEmpty &&
          u.username != '@'
        ).toList();

        final users = _query.isEmpty
            ? all
            : all.where((u) =>
                u.username.toLowerCase().contains(_query) ||
                u.email.toLowerCase().contains(_query),
              ).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _searchController,
                style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search by username or email…',
                  hintStyle: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.4)),
                  prefixIcon: Icon(Icons.search_rounded, color: cs.onSurface.withValues(alpha: 0.4), size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: cs.onSurface.withValues(alpha: 0.4), size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            if (users.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _query.isEmpty ? 'No valid users found' : 'No users match "$_query"',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: users.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, i) {
                    final user = users[i];
                    final isSecured = user.hasPublicKey;

                    return GlassContainer(
                      padding: const EdgeInsets.all(16),
                      borderColor: user.isActive
                          ? (isSecured ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant)
                          : cs.error.withValues(alpha: 0.3),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (user.isAdmin ? cs.tertiary : cs.primary).withValues(alpha: 0.1),
                              border: Border.all(
                                color: (user.isAdmin ? cs.tertiary : cs.primary).withValues(alpha: 0.2),
                              ),
                            ),
                            child: Icon(
                              isSecured ? Icons.shield_rounded : (user.isAdmin ? Icons.admin_panel_settings : Icons.person_rounded),
                              color: user.isAdmin ? cs.tertiary : cs.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '@${user.username}',
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user.email,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _RevokeButton(
                            user: user,
                            onToggle: (val) => _adminRepo.setUserActiveStatus(user.uid, val),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RevokeButton extends StatefulWidget {
  final UserModel user;
  final Future<void> Function(bool) onToggle;

  const _RevokeButton({required this.user, required this.onToggle});

  @override
  State<_RevokeButton> createState() => _RevokeButtonState();
}

class _RevokeButtonState extends State<_RevokeButton> {
  bool _loading = false;

  Future<void> _handleToggle(bool val) async {
    if (_loading) return;
    if (!val) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: const Text('Revoke Access'),
          content: Text('Disable @${widget.user.username}? They will be unable to sign in.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Revoke', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() => _loading = true);
    try {
      await widget.onToggle(val);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.user.isAdmin) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.tertiary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'ADMIN',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.tertiary,
          ),
        ),
      );
    }

    if (_loading) {
      return const SizedBox(
        width: 40,
        height: 24,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Switch(
      value: widget.user.isActive,
      activeThumbColor: cs.secondary,
      activeTrackColor: cs.secondary.withValues(alpha: 0.2),
      inactiveThumbColor: cs.error,
      inactiveTrackColor: cs.error.withValues(alpha: 0.2),
      onChanged: _handleToggle,
    );
  }
}
