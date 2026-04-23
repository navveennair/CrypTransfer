import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/notification_service.dart';
import '../widgets/shared_widgets.dart';
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
        actions: const [_NotifBellButton(), SizedBox(width: 8)],
      ),
      drawer: const SidebarDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Welcome banner ────────────────────────────────
            GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              color: cs.primary.withValues(alpha: 0.1),
              borderColor: cs.primary.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.waving_hand_rounded, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $username!',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Welcome back to secure transfers.',
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
            const SizedBox(height: 24),

            Text(
              'Actions',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // ── Role buttons ──────────────────────────────────
            GlassButton(
              icon: const Text('📤', style: TextStyle(fontSize: 18)),
              label: const Text('I am a Sender'),
              color: Colors.green.shade400,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SenderScreen()),
              ),
            ),
            const SizedBox(height: 12),
            GlassButton(
              icon: const Text('📥', style: TextStyle(fontSize: 18)),
              label: const Text('I am a Receiver'),
              color: cs.primary,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceiverScreen()),
              ),
            ),
            const SizedBox(height: 32),

            // ── Recent transfers section ─────────
            Row(
              children: [
                Icon(Icons.history_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Transfers',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(FirebaseConstants.users)
                  .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
                  .collection(FirebaseConstants.auditLogs)
                  .orderBy('loggedAt', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return GlassContainer(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 40, color: cs.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('No transfers yet',
                              style:
                                  TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }
                final uid =
                    FirebaseAuth.instance.currentUser?.uid ?? '';
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final data =
                        docs[i].data() as Map<String, dynamic>;
                    final isSender = data['senderId'] == uid;
                    final fileName =
                        data['fileName'] as String? ?? 'file';
                    final ts = data['loggedAt'] as Timestamp?;
                    final dt = ts?.toDate().toLocal();
                    final date = dt != null
                        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
                        : '';
                    final time = dt != null
                        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                        : '';
                    final senderUsername =
                        data['senderUsername'] as String?;
                    final receiverUsername =
                        data['receiverUsername'] as String?;
                    final peer =
                        isSender ? receiverUsername : senderUsername;
                    return GlassContainer(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isSender ? Colors.blue : Colors.purple).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isSender
                                  ? Icons.upload_rounded
                                  : Icons.download_rounded,
                              size: 20,
                              color: isSender
                                  ? Colors.blue.shade400
                                  : Colors.purple.shade400,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                if (peer != null)
                                  Text(
                                    '${isSender ? "→" : "←"} @$peer',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (date.isNotEmpty)
                                  Text(
                                    '$date • $time',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SecurityBadge(label: isSender ? 'Sent' : 'Received'),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
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
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(Icons.notifications_none_rounded, size: 22),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                right: 4,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
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
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: Colors.indigo.withValues(alpha: 0.2),
            borderColor: Colors.indigo.withValues(alpha: 0.3),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
