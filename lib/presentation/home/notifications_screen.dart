import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/notification_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../receiver/receiver_screen.dart';
import '../sender/sender_screen.dart';

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
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => NotificationService.markAllRead(uid),
            child: const Text('Mark all read'),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isRead ? null : cs.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRead
            ? BorderSide.none
            : BorderSide(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isRead ? cs.surfaceContainerHighest : cs.primaryContainer,
          child: Icon(
            _typeIcon(type),
            color: isRead ? cs.onSurfaceVariant : cs.primary,
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
                decoration: const BoxDecoration(
                    color: Colors.deepPurple, shape: BoxShape.circle),
              ),
        onTap: () async {
          if (!isRead) await NotificationService.markRead(uid, docId);
          if (!context.mounted) return;
          final nav = Navigator.of(context);
          nav.pop();
          if (type == 'rsa_key_received') {
            nav.push(
                MaterialPageRoute(builder: (_) => const SenderScreen()));
          } else if (type == 'file_received') {
            nav.push(
                MaterialPageRoute(builder: (_) => const ReceiverScreen()));
          }
        },
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'rsa_key_received':
        return Icons.vpn_key_rounded;
      case 'file_received':
        return Icons.download_rounded;
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
