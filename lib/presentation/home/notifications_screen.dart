import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/utils/notification_service.dart';
import '../../data/repositories/auth_repository.dart';

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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isRead ? null : accentColor.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRead
            ? BorderSide.none
            : BorderSide(color: accentColor.withValues(alpha: 0.3)),
      ),
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
          style: TextStyle(
              fontSize: 13,
              fontWeight: isRead ? FontWeight.normal : FontWeight.w600),
        ),
        subtitle: ts != null
            ? Text(
                _fmtTime(ts.toDate()),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
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
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'transfer_completed':
        return Icons.check_circle_rounded;
      case 'transfer_aborted':
        return Icons.cancel_rounded;
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
