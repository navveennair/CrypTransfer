import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/notification_service.dart';
import 'notifications_screen.dart';
import '../receiver/receiver_screen.dart';
import '../sender/sender_screen.dart';
import 'sidebar_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<Map<String, dynamic>?>? _notifSub;
  OverlayEntry? _bannerEntry;
  String? _lastBannerDocId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startNotifListener());
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _bannerEntry?.remove();
    super.dispose();
  }

  void _startNotifListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _notifSub =
        NotificationService.latestUnreadStream(uid).listen((notif) {
      if (!mounted || notif == null) return;
      final docId = notif['docId'] as String;
      if (docId == _lastBannerDocId) return;
      _lastBannerDocId = docId;
      _showNotifBanner(notif);
    });
  }

  void _showNotifBanner(Map<String, dynamic> notif) {
    _bannerEntry?.remove();
    final docId = notif['docId'] as String;
    final message = notif['message'] as String? ?? 'New notification';
    final type = notif['type'] as String? ?? '';

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NotifBanner(
        message: message,
        onDismiss: () {
          entry.remove();
          if (_bannerEntry == entry) _bannerEntry = null;
          NotificationService.markRead(FirebaseAuth.instance.currentUser!.uid, docId);
        },
        onTap: () {
          entry.remove();
          if (_bannerEntry == entry) _bannerEntry = null;
          NotificationService.markRead(FirebaseAuth.instance.currentUser!.uid, docId);
          if (!mounted) return;
          if (type == 'rsa_key_received') {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SenderScreen()));
          } else if (type == 'file_received') {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReceiverScreen()));
          }
        },
      ),
    );
    _bannerEntry = entry;
    Overlay.of(context).insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final username =
        FirebaseAuth.instance.currentUser?.displayName ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: Text('CrypTransfer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: cs.surface,
        surfaceTintColor: cs.primary,
        elevation: 0,
        actions: const [_NotifBellButton()],
      ),
      drawer: const SidebarDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Welcome banner ────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.waving_hand_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Hello, $username!',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Role buttons ──────────────────────────────────
            _RoleButton(
              emoji: '📤',
              label: 'I am a Sender',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SenderScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _RoleButton(
              emoji: '📥',
              label: 'I am a Receiver',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceiverScreen()),
              ),
            ),
            const SizedBox(height: 28),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 12),

            // ── Recent transfers (from transfers_log) ─────────
            Row(
              children: [
                Icon(Icons.history_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Transfers',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(FirebaseConstants.transferLogs)
                    .where('participants',
                        arrayContains:
                            FirebaseAuth.instance.currentUser?.uid ?? '')
                    .orderBy('loggedAt', descending: true)
                    .limit(10)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 48, color: cs.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text('No transfers yet',
                              style:
                                  TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    );
                  }
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid ?? '';
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final data =
                          docs[i].data() as Map<String, dynamic>;
                      final isSender = data['senderId'] == uid;
                      final fileName =
                          data['fileName'] as String? ?? 'file';
                      final date =
                          data['transferDate'] as String? ?? '';
                      final time =
                          data['transferTime'] as String? ?? '';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSender
                                  ? Icons.upload_rounded
                                  : Icons.download_rounded,
                              size: 20,
                              color: isSender
                                  ? Colors.indigo.shade600
                                  : Colors.deepPurple.shade600,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '$date  $time',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isSender ? 'Sent' : 'Received',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _RoleButton extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _RoleButton({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green.shade600,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        child: Text(
          '$emoji  $label',
          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─── Notification bell button (AppBar action) ─────────────────────────────────

class _NotifBellButton extends StatelessWidget {
  const _NotifBellButton();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<int>(
      stream: NotificationService.unreadCountStream(uid),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationsScreen()),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── In-app notification banner (Overlay) ─────────────────────────────────────

class _NotifBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _NotifBanner({
    required this.message,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  State<_NotifBanner> createState() => _NotifBannerState();
}

class _NotifBannerState extends State<_NotifBanner> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade700,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: const Icon(Icons.close,
                      color: Colors.white70, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
