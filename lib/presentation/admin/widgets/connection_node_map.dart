import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../widgets/shared_widgets.dart';

class ConnectionNodeMap extends StatelessWidget {
  final _adminRepo = AdminRepository();
  final _userRepo = UserRepository();

  ConnectionNodeMap({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _adminRepo.streamUserConnections(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final users = snapshot.data!.docs;
        
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: users.length,
          itemBuilder: (context, i) {
            final data = users[i].data() as Map<String, dynamic>;
            final username = data['username'] as String? ?? '...';
            final uid = users[i].id;

            return StreamBuilder<Map<String, dynamic>?>(
              stream: _userRepo.streamUserWithFriendships(uid),
              builder: (context, connSnap) {
                final connCount = (connSnap.data?['friendships'] as List?)?.length ?? 0;
                return _NodeTile(
                  username: username,
                  connectionCount: connCount,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NodeTile extends StatelessWidget {
  final String username;
  final int connectionCount;

  const _NodeTile({
    required this.username,
    required this.connectionCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = connectionCount > 0;
    final color = isActive ? cs.primary : cs.onSurface.withValues(alpha: 0.1);

    return GlassContainer(
      borderRadius: 20,
      borderColor: isActive ? cs.primary.withValues(alpha: 0.5) : cs.outline,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.1),
                ),
              ),
              Icon(Icons.person_rounded, color: color, size: 30),
              if (isActive)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      connectionCount.toString(),
                      style: TextStyle(color: cs.onSecondary, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '@$username',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            isActive ? 'CONNECTED' : 'ISOLATED',
            style: TextStyle(
              color: isActive ? cs.secondary : cs.onSurface.withValues(alpha: 0.24),
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
