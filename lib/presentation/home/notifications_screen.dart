import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/utils/notification_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/shared_widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepo = AuthRepository();
    final uid = authRepo.currentUid ?? '';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            onPressed: () => NotificationService.markAllRead(uid),
            tooltip: 'Mark all as read',
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: NotificationService.allStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('No notifications yet',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: items.length,
            itemBuilder: (_, i) => _NotificationTile(uid: uid, item: items[i]),
          );
        },
      ),
    );
  }
}

// ─── Notification tile ────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> item;
  const _NotificationTile({required this.uid, required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRead = item['read'] == true;
    final docId = item['docId'] as String;
    final type = item['type'] as String? ?? '';
    final message = item['message'] as String? ?? '';
    final ts = item['createdAt'] as Timestamp?;

    final isFailure = type == 'transfer_aborted';
    final accentColor = isFailure ? cs.error : cs.tertiary;

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: 12,
      color: isRead ? null : accentColor.withValues(alpha: 0.08),
      borderColor: isRead ? null : accentColor.withValues(alpha: 0.3),
      // ListTile paints its ink/background on the nearest Material ancestor.
      // GlassContainer is a coloured DecoratedBox, so without an intervening
      // Material the tile's splash is hidden (and debug asserts). A transparent
      // Material gives the tile a surface to paint on, above the box colour.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accentColor.withValues(alpha: isRead ? 0.08 : 0.15),
          child: Icon(
            _typeIcon(type),
            color: isRead ? accentColor.withValues(alpha: 0.6) : accentColor,
            size: 20,
          ),
        ),
        title: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isRead ? FontWeight.normal : FontWeight.w600),
        ),
        subtitle: ts != null
            ? Text(
                _fmtTime(ts.toDate()),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              )
            : null,
        trailing: isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: accentColor, shape: BoxShape.circle),
              ),
        onTap: () async {
          await NotificationService.markRead(uid, docId);
        },
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'transfer_completed':
        return Icons.check_circle_rounded;
      case 'transfer_aborted':
        return Icons.cancel_rounded;
      case 'connection_request':
        return Icons.person_add_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _fmtTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
