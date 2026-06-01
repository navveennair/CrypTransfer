import 'package:flutter/material.dart';

import '../../../data/repositories/admin_repository.dart';
import '../../widgets/shared_widgets.dart';

class ConnectionNodeMap extends StatefulWidget {
  const ConnectionNodeMap({super.key});

  @override
  State<ConnectionNodeMap> createState() => _ConnectionNodeMapState();
}

class _ConnectionNodeMapState extends State<ConnectionNodeMap> {
  final _adminRepo = AdminRepository();
  late Future<List<Map<String, dynamic>>> _futureConnections;

  @override
  void initState() {
    super.initState();
    _futureConnections = _adminRepo.fetchUserConnections();
  }

  void _refresh() {
    setState(() {
      _futureConnections = _adminRepo.fetchUserConnections();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futureConnections,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading data',
              style: TextStyle(color: cs.error),
            ),
          );
        }
        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return Center(
            child: Text(
              'No network nodes found',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          );
        }

        return Stack(
          children: [
            GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: users.length,
              itemBuilder: (context, i) {
                final record = users[i];
                return _NodeTile(
                  username: record['username'] as String? ?? '',
                  connectionCount: record['connectionCount'] as int? ?? 0,
                );
              },
            ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                  tooltip: 'Refresh network map',
                  onPressed: _refresh,
                ),
              ),
            ),
          ],
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
