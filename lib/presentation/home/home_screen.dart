import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/notification_service.dart';
import '../../data/repositories/handshake_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../widgets/shared_widgets.dart';
import 'find_friends_screen.dart';
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

  final _handshakeRepo = HandshakeRepository();
  final _transferRepo = TransferRepository();
  StreamSubscription<QuerySnapshot>? _pendingProposalSub;
  StreamSubscription<QuerySnapshot>? _outcomePendingSub;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _recentTransfersStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeAsProposerStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeAsPartnerStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _outgoingPendingStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _incomingPendingStream;
  String? _lastSeenProposalId; // deduplication — mirrors _lastBannerDocId
  // ignore: prefer_final_fields
  Map<String, StreamSubscription> _outcomeSubs = {};

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _recentTransfersStream = _transferRepo.streamRecentTransfers(uid);
    _activeAsProposerStream = _handshakeRepo.streamActiveConnectionsAsProposer();
    _activeAsPartnerStream = _handshakeRepo.streamActiveConnectionsAsPartner();
    _outgoingPendingStream = _handshakeRepo.streamOutgoingPending();
    _incomingPendingStream = _handshakeRepo.streamIncomingPending();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNotifListener();
      _startHandshakeListener();
      _startOutcomeListener();
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _bannerEntry?.remove();
    _pendingProposalSub?.cancel();
    _outcomePendingSub?.cancel();
    for (final sub in _outcomeSubs.values) {
      sub.cancel();
    }
    _outcomeSubs.clear();
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

  void _startHandshakeListener() {
    _pendingProposalSub = _incomingPendingStream.listen((snap) {
      if (!mounted) return;
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final docId = change.doc.id;
          if (docId == _lastSeenProposalId) continue; // deduplication
          _lastSeenProposalId = docId;
          _showProposalBanner(change.doc);
        }
      }
    });
  }

  void _startOutcomeListener() {
    // Subscribe to outgoing pending docs. For each, open a per-doc outcome stream
    // that fires the outcome _NotifBanner when the partner responds (D-08).
    _outcomePendingSub = _outgoingPendingStream.listen((snap) {
      if (!mounted) return;
      for (final change in snap.docChanges) {
        final docId = change.doc.id;
        if (change.type == DocumentChangeType.added &&
            !_outcomeSubs.containsKey(docId)) {
          // New outgoing proposal — start watching its status
          _outcomeSubs[docId] = _handshakeRepo
              .streamProposalOutcome(docId)
              .listen((docSnap) {
            if (!mounted) return;
            final status = docSnap.data()?['status'] as String?;
            if (status == 'connected' || status == 'rejected') {
              // Outcome received — fire banner and clean up this sub
              final partnerUsername =
                  docSnap.data()?['partnerUsername'] as String? ?? 'your contact';
              final message = status == 'connected'
                  ? 'Connection accepted by @$partnerUsername'
                  : 'Connection request declined';
              _showNotifBanner({
                'type': 'outcome',
                'message': message,
                'docId': docId,
              });
              // Cancel and remove this per-doc sub — outcome is final
              _outcomeSubs[docId]?.cancel();
              _outcomeSubs.remove(docId);
            }
          });
        } else if (change.type == DocumentChangeType.removed) {
          // Doc deleted (cancelled by proposer or cleaned up) — remove sub
          _outcomeSubs[docId]?.cancel();
          _outcomeSubs.remove(docId);
        }
      }
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
          if (type != 'outcome') {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) NotificationService.markRead(uid, docId);
          }
        },
        onTap: () {
          entry.remove();
          if (_bannerEntry == entry) _bannerEntry = null;
          if (type != 'outcome') {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid != null) NotificationService.markRead(uid, docId);
          }
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

  void _showProposalBanner(DocumentSnapshot<Map<String, dynamic>> doc) {
    _bannerEntry?.remove();
    final data = doc.data() ?? {};
    final proposerUsername = data['proposerUsername'] as String? ?? 'Someone';
    final docId = doc.id;
    final proposerId = data['proposerId'] as String? ?? '';

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ProposalBanner(
        message: '@$proposerUsername wants to connect',
        onAccept: () {
          entry.remove();
          if (_bannerEntry == entry) _bannerEntry = null;
          _handshakeRepo.acceptProposal(docId, proposerId).catchError((e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("Couldn't accept request. Try again."),
              backgroundColor: Theme.of(context).colorScheme.error,
            ));
          });
        },
        onReject: () {
          entry.remove();
          if (_bannerEntry == entry) _bannerEntry = null;
          _handshakeRepo.rejectProposal(docId).catchError((e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text("Couldn't decline request. Try again."),
              backgroundColor: Theme.of(context).colorScheme.error,
            ));
          });
        },
        onDismiss: () {
          entry.remove();
          if (_bannerEntry == entry) _bannerEntry = null;
          // No action — proposal stays pending per D-03
        },
      ),
    );
    _bannerEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _openAddConnectionSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FindFriendsScreen()),
    );
  }

  void _openRolePicker({
    required String partnerUid,
    required String partnerUsername,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RolePickerSheet(
        partnerUid: partnerUid,
        partnerUsername: partnerUsername,
        onSendFile: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SenderScreen(
                preFilledPartnerUid: partnerUid,
                preFilledPartnerUsername: partnerUsername,
              ),
            ),
          );
        },
        onReceiveFile: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiverScreen(
                preFilledSenderUid: partnerUid,
                preFilledSenderUsername: partnerUsername,
              ),
            ),
          );
        },
      ),
    );
  }

  void _cancelProposal({required String docId, required String partnerUsername}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return GlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BottomSheetHandle(),
              const SizedBox(height: 16),
              Text(
                'Cancel connection request?',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                "Cancel request to @$partnerUsername? They won't be notified.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              CrypButton(
                label: const Text('Cancel Request'),
                color: cs.error,
                onPressed: () {
                  Navigator.pop(ctx);
                  _handshakeRepo.cancelProposal(docId).catchError((_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Couldn't cancel request. Try again.")));
                  });
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Keep Waiting', style: GoogleFonts.poppins(fontSize: 14)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _acceptProposal(
      {required String docId, required String proposerId}) async {
    try {
      await _handshakeRepo.acceptProposal(docId, proposerId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Couldn't accept request. Try again."),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      rethrow;
    }
  }

  Future<void> _rejectProposal({required String docId}) async {
    try {
      await _handshakeRepo.rejectProposal(docId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Couldn't decline request. Try again."),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      rethrow;
    }
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              borderRadius: 28,
              color: cs.primary.withValues(alpha: 0.1),
              borderColor: cs.primary.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.waving_hand_rounded, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $username!',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Welcome back to secure transfers.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Active Connections ─────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.link_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  'Active Connections',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openAddConnectionSheet,
                  icon: Icon(Icons.add_rounded, size: 18, color: cs.primary),
                  label: Text(
                    'Add New',
                    style: GoogleFonts.poppins(fontSize: 13, color: cs.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ActiveConnectionsSection(
              activeAsProposerStream: _activeAsProposerStream,
              activeAsPartnerStream: _activeAsPartnerStream,
              outgoingPendingStream: _outgoingPendingStream,
              currentUid: FirebaseAuth.instance.currentUser?.uid ?? '',
              onConnectionTap: _openRolePicker,
              onCancelTap: _cancelProposal,
              onAddPressed: _openAddConnectionSheet,
              onShowError: (msg) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), backgroundColor: cs.error),
              ),
            ),
            const SizedBox(height: 32),

            // ── Pending Requests ───────────────────────────────────────────────
            _PendingRequestsSection(
              incomingPendingStream: _incomingPendingStream,
              onAccept: _acceptProposal,
              onReject: _rejectProposal,
              onShowError: (msg) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), backgroundColor: cs.error),
              ),
            ),
            const SizedBox(height: 32),

            // ── Recent transfers section ─────────
            Row(
              children: [
                Icon(Icons.history_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Recent Transfers',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const Spacer(),
                Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            StreamBuilder<QuerySnapshot>(
              stream: _recentTransfersStream,
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

// ─── Proposal Banner (Accept / Reject) ─────────────────────────────────────
// Used for incoming neutral handshake proposals. Distinct from _NotifBanner
// which handles RSA key and file-received notifications.

class _ProposalBanner extends StatefulWidget {
  final String message;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDismiss;

  const _ProposalBanner({
    required this.message,
    required this.onAccept,
    required this.onReject,
    required this.onDismiss,
  });

  @override
  State<_ProposalBanner> createState() => _ProposalBannerState();
}

class _ProposalBannerState extends State<_ProposalBanner> {
  late final Timer _timer;
  bool _accepting = false;
  bool _rejecting = false;

  @override
  void initState() {
    super.initState();
    // 5-second auto-dismiss — same as _NotifBanner; no action taken on auto-dismiss
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
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: GlassContainer(
          color: Colors.deepPurple.withValues(alpha: 0.2),
          borderColor: Colors.deepPurple.withValues(alpha: 0.4),
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.white70),
                    onPressed: widget.onDismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Dismiss',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: (_accepting || _rejecting)
                        ? null
                        : () async {
                            setState(() => _accepting = true);
                            try {
                              await widget.onAccept();
                            } finally {
                              if (mounted) setState(() => _accepting = false);
                            }
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade400,
                      minimumSize: const Size(44, 44),
                    ),
                    child: _accepting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Accept Request'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: (_accepting || _rejecting)
                        ? null
                        : () async {
                            setState(() => _rejecting = true);
                            try {
                              await widget.onReject();
                            } finally {
                              if (mounted) setState(() => _rejecting = false);
                            }
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                      minimumSize: const Size(44, 44),
                    ),
                    child: _rejecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Decline Request'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Active Connections Section ────────────────────────────────────────────────

class _ActiveConnectionsSection extends StatelessWidget {
  final Stream<QuerySnapshot> activeAsProposerStream;
  final Stream<QuerySnapshot> activeAsPartnerStream;
  final Stream<QuerySnapshot> outgoingPendingStream;
  final String currentUid;
  final void Function({required String partnerUid, required String partnerUsername})
      onConnectionTap;
  final void Function({required String docId, required String partnerUsername})
      onCancelTap;
  final VoidCallback onAddPressed;
  final void Function(String msg) onShowError;

  const _ActiveConnectionsSection({
    required this.activeAsProposerStream,
    required this.activeAsPartnerStream,
    required this.outgoingPendingStream,
    required this.currentUid,
    required this.onConnectionTap,
    required this.onCancelTap,
    required this.onAddPressed,
    required this.onShowError,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: activeAsProposerStream,
      builder: (context, proposerSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: activeAsPartnerStream,
          builder: (context, partnerSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: outgoingPendingStream,
              builder: (context, pendingSnap) {
                if (proposerSnap.hasError || partnerSnap.hasError || pendingSnap.hasError) {
                  final cs = Theme.of(context).colorScheme;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Could not load connections. Check your connection.',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (proposerSnap.connectionState == ConnectionState.waiting ||
                    partnerSnap.connectionState == ConnectionState.waiting ||
                    pendingSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final proposerDocs = proposerSnap.data?.docs ?? [];
                final partnerDocs = partnerSnap.data?.docs ?? [];
                final pendingDocs = pendingSnap.data?.docs ?? [];

                // Deduplicate: build a set of partner UIDs from proposer docs
                final seenUids = <String>{};
                final connectedRows = <Widget>[];

                for (final doc in proposerDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final uid = data['partnerId'] as String? ?? '';
                  final username = data['partnerUsername'] as String? ?? '';
                  if (seenUids.add(uid)) {
                    connectedRows.add(_ActiveConnectionRow(
                      username: username,
                      partnerUid: uid,
                      isConnected: true,
                      docId: doc.id,
                      onConnectionTap: onConnectionTap,
                      onCancelTap: onCancelTap,
                    ));
                  }
                }

                for (final doc in partnerDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final uid = data['proposerId'] as String? ?? '';
                  final username = data['proposerUsername'] as String? ?? '';
                  if (seenUids.add(uid)) {
                    connectedRows.add(_ActiveConnectionRow(
                      username: username,
                      partnerUid: uid,
                      isConnected: true,
                      docId: doc.id,
                      onConnectionTap: onConnectionTap,
                      onCancelTap: onCancelTap,
                    ));
                  }
                }

                // Pending outgoing rows
                final pendingRows = <Widget>[];
                for (final doc in pendingDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final uid = data['partnerId'] as String? ?? '';
                  final username = data['partnerUsername'] as String? ?? '';
                  pendingRows.add(_ActiveConnectionRow(
                    username: username,
                    partnerUid: uid,
                    isConnected: false,
                    docId: doc.id,
                    onConnectionTap: onConnectionTap,
                    onCancelTap: onCancelTap,
                  ));
                }

                final allRows = [...connectedRows, ...pendingRows];

                if (allRows.isEmpty) {
                  return _EmptyConnectionsPrompt(onAddPressed: onAddPressed);
                }

                return Column(
                  children: [
                    for (int i = 0; i < allRows.length; i++) ...[
                      allRows[i],
                      if (i < allRows.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── Active Connection Row ─────────────────────────────────────────────────────

class _ActiveConnectionRow extends StatelessWidget {
  final String username;
  final String partnerUid;
  final bool isConnected;
  final String docId;
  final void Function({required String partnerUid, required String partnerUsername})
      onConnectionTap;
  final void Function({required String docId, required String partnerUsername})
      onCancelTap;

  const _ActiveConnectionRow({
    required this.username,
    required this.partnerUid,
    required this.isConnected,
    required this.docId,
    required this.onConnectionTap,
    required this.onCancelTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          UserAvatar(username: username),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@$username',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _StatusBadge(isConnected: isConnected),
          if (!isConnected)
            IconButton(
              icon: Icon(Icons.cancel_outlined, color: Colors.amber.shade400),
              tooltip: 'Cancel connection request',
              onPressed: () =>
                  onCancelTap(docId: docId, partnerUsername: username),
            ),
        ],
      ),
    );

    if (isConnected) {
      return InkWell(
        onTap: () =>
            onConnectionTap(partnerUid: partnerUid, partnerUsername: username),
        borderRadius: BorderRadius.circular(16),
        child: row,
      );
    } else {
      return row;
    }
  }
}

// ─── Pending Requests Section ──────────────────────────────────────────────────

class _PendingRequestsSection extends StatelessWidget {
  final Stream<QuerySnapshot> incomingPendingStream;
  final Future<void> Function({required String docId, required String proposerId}) onAccept;
  final Future<void> Function({required String docId}) onReject;
  final void Function(String msg) onShowError;

  const _PendingRequestsSection({
    required this.incomingPendingStream,
    required this.onAccept,
    required this.onReject,
    required this.onShowError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot>(
      stream: incomingPendingStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError) {
          onShowError('Could not load pending requests. Check your connection.');
          return const SizedBox.shrink();
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.pending_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Pending Requests',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...docs.asMap().entries.map((entry) {
              final i = entry.key;
              final doc = entry.value;
              final data = doc.data() as Map<String, dynamic>;
              final proposerUsername =
                  data['proposerUsername'] as String? ?? 'Unknown';
              final proposerId = data['proposerId'] as String? ?? '';
              return Padding(
                padding: EdgeInsets.only(bottom: i < docs.length - 1 ? 8 : 0),
                child: _PendingRequestRow(
                  proposerUsername: proposerUsername,
                  docId: doc.id,
                  proposerId: proposerId,
                  onAccept: onAccept,
                  onReject: onReject,
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ─── Pending Request Row ───────────────────────────────────────────────────────

class _PendingRequestRow extends StatefulWidget {
  final String proposerUsername;
  final String docId;
  final String proposerId;
  final Future<void> Function({required String docId, required String proposerId}) onAccept;
  final Future<void> Function({required String docId}) onReject;

  const _PendingRequestRow({
    required this.proposerUsername,
    required this.docId,
    required this.proposerId,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_PendingRequestRow> createState() => _PendingRequestRowState();
}

class _PendingRequestRowState extends State<_PendingRequestRow> {
  bool _accepting = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLoading = _accepting || _rejecting;

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(username: widget.proposerUsername),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '@${widget.proposerUsername} wants to connect',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        setState(() => _rejecting = true);
                        try {
                          await widget.onReject(docId: widget.docId);
                        } finally {
                          if (mounted) setState(() => _rejecting = false);
                        }
                      },
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  minimumSize: const Size(44, 44),
                ),
                child: _rejecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Decline Request'),
              ),
              const SizedBox(width: 8),
              CrypButton(
                label: const Text('Accept Request'),
                color: Colors.green.shade400,
                onPressed: isLoading
                    ? null
                    : () async {
                        setState(() => _accepting = true);
                        try {
                          await widget.onAccept(
                              docId: widget.docId, proposerId: widget.proposerId);
                        } finally {
                          if (mounted) setState(() => _accepting = false);
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty Connections Prompt ──────────────────────────────────────────────────

class _EmptyConnectionsPrompt extends StatelessWidget {
  final VoidCallback onAddPressed;

  const _EmptyConnectionsPrompt({required this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off_rounded, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No connections yet',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a connection request to a contact to start a secure transfer.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            CrypButton(
              label: const Text('Add New Connection'),
              onPressed: onAddPressed,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Role Picker Sheet ─────────────────────────────────────────────────────────

class _RolePickerSheet extends StatelessWidget {
  final String partnerUid;
  final String partnerUsername;
  final VoidCallback onSendFile;
  final VoidCallback onReceiveFile;

  const _RolePickerSheet({
    required this.partnerUid,
    required this.partnerUsername,
    required this.onSendFile,
    required this.onReceiveFile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start a session with @$partnerUsername',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                // Send File tile
                InkWell(
                  onTap: onSendFile,
                  borderRadius: BorderRadius.circular(16),
                  child: GlassContainer(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(Icons.upload_file_rounded,
                            size: 32, color: cs.primary),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Send File',
                                style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'You encrypt and transmit',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Receive File tile
                InkWell(
                  onTap: onReceiveFile,
                  borderRadius: BorderRadius.circular(16),
                  child: GlassContainer(
                    borderRadius: 16,
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(Icons.download_rounded,
                            size: 32, color: cs.secondary),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Receive File',
                                style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'You decrypt and save',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool isConnected;

  const _StatusBadge({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    if (isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade400.withValues(alpha: 0.15),
          border: Border.all(
              color: Colors.green.shade400.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Connected',
          style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade400),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.shade700.withValues(alpha: 0.15),
          border: Border.all(
              color: Colors.amber.shade400.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Pending',
          style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade400),
        ),
      );
    }
  }
}
