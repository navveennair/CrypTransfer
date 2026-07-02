import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/notification_service.dart';
import '../../core/utils/transfer_status_utils.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/handshake_repository.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../widgets/shared_widgets.dart';
import 'find_friends_screen.dart';
import 'transfer_summary_screen.dart';
import 'notifications_screen.dart';
import '../auth/login_screen.dart';
import '../receiver/receiver_screen.dart';
import '../sender/sender_screen.dart';
import 'sidebar_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  StreamSubscription? _profileSub;
  StreamSubscription<Map<String, dynamic>?>? _notifSub;
  OverlayEntry? _bannerEntry;          // rsa_key_received / file_received
  OverlayEntry? _outcomeEntry;         // connection accepted/declined (separate slot)
  String? _lastBannerDocId;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  final _connService = KeyRepository();
  final _handshakeRepo = HandshakeRepository();
  final _transferRepo = TransferRepository();
  final _authRepo = AuthRepository();
  final _userRepo = UserRepository();
  StreamSubscription<QuerySnapshot>? _outcomePendingSub;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _recentTransfersStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeAsProposerStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeAsPartnerStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _outgoingPendingStream;
  // ignore: prefer_final_fields
  Map<String, StreamSubscription> _outcomeSubs = {};

  @override
  void initState() {
    super.initState();
    final uid = _authRepo.currentUid ?? '';
    _recentTransfersStream = _transferRepo.streamRecentTransfers(uid);
    _activeAsProposerStream = _handshakeRepo.streamActiveConnectionsAsProposer();
    _activeAsPartnerStream = _handshakeRepo.streamActiveConnectionsAsPartner();
    _outgoingPendingStream = _handshakeRepo.streamOutgoingPending();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _profileSub = _authRepo.streamUserProfile(uid).listen((profile) {
      if (profile != null && profile.isActive == false && mounted) {
        _forceLogout();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNotifListener();
      _startOutcomeListener();
    });
  }

  Future<void> _forceLogout() async {
    _profileSub?.cancel();
    await _authRepo.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _pulseCtrl.dispose();
    _notifSub?.cancel();
    _bannerEntry?.remove();
    _outcomeEntry?.remove();
    _outcomePendingSub?.cancel();
    for (final sub in _outcomeSubs.values) {
      sub.cancel();
    }
    _outcomeSubs.clear();
    super.dispose();
  }

  void _showErrorSnackBar(String message, {Color? bgColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bgColor ?? Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
    );
  }


  void _showRoleConflictDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz_rounded, size: 48, color: Theme.of(ctx).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Role Conflict',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'One user must be sender, another must be receiver. Please try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: CrypButton(
                  label: const Text('OK'),
                  color: Theme.of(ctx).colorScheme.primary,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startNotifListener() {
    final uid = _authRepo.currentUid;
    if (uid == null) return;
    _notifSub =
        NotificationService.latestUnreadStream(uid).listen((notif) {
      if (!mounted || notif == null) return;
      // Connection requests intentionally do NOT pop a transient banner — they
      // surface as the bell badge + an entry in NotificationsScreen. The user
      // marks the notification read, returns Home, taps "+ View" and acts on the
      // request in the FindFriends "Incoming Requests" list. (friend_request is
      // skipped for the same reason.)
      final type = notif['type'] as String? ?? '';
      // connection_request / friend_request surface as bell badge + FindFriends list only.
      // transfer_completed / transfer_aborted are shown live in the transfer screens —
      // popping a banner when the user returns to Home is redundant noise.
      if (type == 'connection_request' ||
          type == 'friend_request' ||
          type == 'transfer_completed' ||
          type == 'transfer_aborted') {
        return;
      }
      final docId = notif['docId'] as String;
      if (docId == _lastBannerDocId) return;
      _lastBannerDocId = docId;
      _showNotifBanner(notif);
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
              _showOutcomeBanner(message);
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
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + kToolbarHeight + 8,
        left: 16,
        right: 16,
        child: _NotifBanner(
          message: message,
          onDismiss: () {
            entry.remove();
            if (_bannerEntry == entry) _bannerEntry = null;
            // Do NOT markRead on auto-dismiss — notification must persist in
            // NotificationsScreen until the user explicitly acknowledges it.
          },
          onTap: () {
            entry.remove();
            if (_bannerEntry == entry) _bannerEntry = null;
            final uid = _authRepo.currentUid;
            if (uid != null) NotificationService.markRead(uid, docId);
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
      ),
    );
    _bannerEntry = entry;
    Overlay.of(context).insert(entry);
  }

  // Outcome banners (connection accepted/declined) use a separate slot so they
  // never remove a live rsa_key_received / file_received notification banner.
  // They pin to the bottom of the screen to visually separate from top banners.
  void _showOutcomeBanner(String message) {
    _outcomeEntry?.remove();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        bottom: MediaQuery.of(ctx).padding.bottom + 16,
        left: 16,
        right: 16,
        child: _NotifBanner(
          message: message,
          onDismiss: () {
            entry.remove();
            if (_outcomeEntry == entry) _outcomeEntry = null;
          },
          onTap: () {
            entry.remove();
            if (_outcomeEntry == entry) _outcomeEntry = null;
          },
        ),
      ),
    );
    _outcomeEntry = entry;
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
        currentUserUid: _authRepo.currentUid ?? '',
        keyRepository: _connService,
        userRepo: _userRepo,
        onSendFile: () async {
          try {
            final handshakeDocId = await _connService.assignTransferRole(
              partnerUid: partnerUid,
              isSender: true,
            );
            if (!mounted) return;
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SenderScreen(
                  preFilledPartnerUid: partnerUid,
                  preFilledPartnerUsername: partnerUsername,
                  handshakeDocId: handshakeDocId,
                ),
              ),
            );
          } catch (e) {
            if (!mounted) return;
            if (e is RoleConflictException) {
              _showRoleConflictDialog(e.toString());
            } else {
              _showInfoSnackBar('Error: ${e.toString()}');
            }
          }
        },
        onReceiveFile: () async {
          try {
            final handshakeDocId = await _connService.assignTransferRole(
              partnerUid: partnerUid,
              isSender: false,
            );
            if (!mounted) return;
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReceiverScreen(
                  preFilledSenderUid: partnerUid,
                  preFilledSenderUsername: partnerUsername,
                  handshakeDocId: handshakeDocId,
                ),
              ),
            );
          } catch (e) {
            if (!mounted) return;
            if (e is RoleConflictException) {
              _showRoleConflictDialog(e.toString());
            } else {
              _showInfoSnackBar('Error: ${e.toString()}');
            }
          }
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
        final tt = Theme.of(ctx).textTheme;
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
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                "Cancel request to @$partnerUsername? They won't be notified.",
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              CrypButton(
                label: const Text('Cancel Request'),
                color: cs.error,
                onPressed: () {
                  Navigator.pop(ctx);
                  _handshakeRepo.cancelProposal(docId).catchError((_) {
                    _showErrorSnackBar("Couldn't cancel request. Try again.");
                  });
                },
              ),
              const SizedBox(height: 8),
              CrypButton(
                label: Text('Keep Waiting', style: tt.bodyMedium),
                onPressed: () => Navigator.pop(ctx),
                color: cs.onSurfaceVariant,
                height: 48,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final username = _authRepo.currentDisplayName ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: Text('CrypTransfer', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [_NotifBellButton(authRepo: _authRepo), const SizedBox(width: 8)],
      ),
      drawer: const SidebarDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Welcome banner ────────────────────────────────
            _WelcomeBanner(username: username),
            const SizedBox(height: 32),

            // ── Active Connections ─────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.link_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  'Active Connections',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                _SectionButton(label: '+ View', onTap: _openAddConnectionSheet),
              ],
            ),
            const SizedBox(height: 12),
            _ActiveConnectionsSection(
              activeAsProposerStream: _activeAsProposerStream,
              activeAsPartnerStream: _activeAsPartnerStream,
              outgoingPendingStream: _outgoingPendingStream,
              currentUid: _authRepo.currentUid ?? '',
              onConnectionTap: _openRolePicker,
              onCancelTap: _cancelProposal,
              onAddPressed: _openAddConnectionSheet,
              pulseAnim: MediaQuery.of(context).disableAnimations ? null : _pulseAnim,
            ),
            const SizedBox(height: 32),

            // ── Recent Transfers ──────────────────────────────
            _RecentTransfersSection(
              transfersStream: _recentTransfersStream,
              currentUid: _authRepo.currentUid ?? '',
              onViewAll: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TransferSummaryScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Transfer status badge ───────────────────────────────────────────────────

// ─── Section header pill button ───────────────────────────────────────────────

class _SectionButton extends StatefulWidget {
  const _SectionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_SectionButton> createState() => _SectionButtonState();
}

class _SectionButtonState extends State<_SectionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.diagonal3Values(
          _pressed ? 0.94 : 1.0,
          _pressed ? 0.94 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: _pressed ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withValues(alpha: _pressed ? 0.50 : 0.30)),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.primary,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

bool _isFailedStatus(String status) => isFailedTransferStatus(status);

Widget _transferStatusBadge(BuildContext context, String status, bool isSender) {
  final cs = Theme.of(context).colorScheme;
  if (_isFailedStatus(status)) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cancel_outlined, size: 13, color: cs.error),
          const SizedBox(width: 4),
          Text(
            'Failed',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  return SecurityBadge(label: isSender ? 'Sent' : 'Received');
}

// ─── Notification bell button (AppBar action) ─────────────────────────────────

class _NotifBellButton extends StatelessWidget {
  final AuthRepository authRepo;
  const _NotifBellButton({required this.authRepo});

  @override
  Widget build(BuildContext context) {
    final uid = authRepo.currentUid ?? '';
    return StreamBuilder<int>(
      stream: NotificationService.unreadCountStream(uid),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          alignment: Alignment.center,
          children: [
            GlassContainer(
              blur: 0,
              borderRadius: 12,
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
                    color: Theme.of(context).colorScheme.error,
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
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onError,
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
    final cs = Theme.of(context).colorScheme;
    // NOTE: positioning is owned by the OverlayEntry builder (Positioned root).
    // This widget must return a normally-sized subtree — returning a Positioned
    // here produces a zero-size render box and a per-frame hit-test exception storm.
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: widget.onTap,
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: cs.tertiary.withValues(alpha: 0.2),
          borderColor: cs.tertiary.withValues(alpha: 0.3),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.notifications_active_rounded,
                    color: cs.onSurface, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.message,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 20),
                onPressed: widget.onDismiss,
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
  final Animation<double>? pulseAnim;

  const _ActiveConnectionsSection({
    required this.activeAsProposerStream,
    required this.activeAsPartnerStream,
    required this.outgoingPendingStream,
    required this.currentUid,
    required this.onConnectionTap,
    required this.onCancelTap,
    required this.onAddPressed,
    this.pulseAnim,
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
                  return const SizedBox.shrink();
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
                      pulseAnim: pulseAnim,
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
                      pulseAnim: pulseAnim,
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
  final Animation<double>? pulseAnim;

  const _ActiveConnectionRow({
    required this.username,
    required this.partnerUid,
    required this.isConnected,
    required this.docId,
    required this.onConnectionTap,
    required this.onCancelTap,
    this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = GlassContainer(
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _StatusBadge(isConnected: isConnected),
          if (!isConnected)
            IconButton(
              icon: Icon(Icons.cancel_outlined, color: cs.onSurfaceVariant),
              tooltip: 'Cancel connection request',
              onPressed: () =>
                  onCancelTap(docId: docId, partnerUsername: username),
            ),
        ],
      ),
    );

    if (isConnected) {
      // Wrap connected rows with a pulsing border to guide the user to tap.
      final anim = pulseAnim;
      final tappable = InkWell(
        onTap: () =>
            onConnectionTap(partnerUid: partnerUid, partnerUsername: username),
        borderRadius: BorderRadius.circular(16),
        child: card,
      );
      if (anim == null) {
        // Reduced-motion or animation disabled: static highlight border.
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.12),
                blurRadius: 10,
                spreadRadius: 0,
              ),
            ],
          ),
          child: tappable,
        );
      }
      return AnimatedBuilder(
        animation: anim,
        builder: (context, child) {
          final t = anim.value;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.3 + 0.5 * t),
                width: 1.0 + 1.0 * t,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.08 + 0.12 * t),
                  blurRadius: 8 + 8 * t,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: child,
          );
        },
        child: tappable,
      );
    } else {
      return card;
    }
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a connection request to a contact to start a secure transfer.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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

class _RolePickerSheet extends StatefulWidget {
  final String partnerUid;
  final String partnerUsername;
  final String currentUserUid;
  final KeyRepository keyRepository;
  final UserRepository userRepo;
  final Future<void> Function() onSendFile;
  final Future<void> Function() onReceiveFile;

  const _RolePickerSheet({
    required this.partnerUid,
    required this.partnerUsername,
    required this.currentUserUid,
    required this.keyRepository,
    required this.userRepo,
    required this.onSendFile,
    required this.onReceiveFile,
  });

  @override
  State<_RolePickerSheet> createState() => _RolePickerSheetState();
}

class _RolePickerSheetState extends State<_RolePickerSheet> {
  bool _loading = false;
  String? _loadingRole;

  Future<void> _handleTap(
    String role,
    Future<void> Function() handler,
  ) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadingRole = role;
    });
    try {
      await handler();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingRole = null;
        });
      }
    }
  }

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
                  'Start a session with @${widget.partnerUsername}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: widget.userRepo.streamUser(widget.partnerUid),
                  builder: (context, snap) {
                    final data = snap.data?.data() ?? {};
                    // Partner claimed Sender toward me → I cannot also be Sender.
                    final senderBlocked =
                        (data[FirebaseConstants.pendingSenderFor] as String?) == widget.currentUserUid;
                    // Partner claimed Receiver with me as their Sender → I cannot also be Receiver.
                    // Covers both the committed claim (selectedSenderUid) and the
                    // in-progress claim (pendingReceiverFor) — either means partner
                    // is already receiving from me, so I can't also try to receive.
                    final receiverBlocked =
                        (data['selectedSenderUid'] as String?) == widget.currentUserUid ||
                        (data[FirebaseConstants.pendingReceiverFor] as String?) == widget.currentUserUid;
                    return Column(
                      children: [
                        // Send File tile
                        Opacity(
                          opacity: senderBlocked ? 0.4 : 1.0,
                          child: InkWell(
                            onTap: (_loading || senderBlocked)
                                ? null
                                : () => _handleTap('send', widget.onSendFile),
                            borderRadius: BorderRadius.circular(16),
                            child: GlassContainer(
                              borderRadius: 16,
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  if (_loadingRole == 'send')
                                    SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(cs.primary),
                                      ),
                                    )
                                  else
                                    Icon(Icons.upload_file_rounded,
                                        size: 32, color: cs.primary),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Send File',
                                          style: Theme.of(context).textTheme.titleLarge,
                                        ),
                                        Text(
                                          senderBlocked
                                              ? 'Partner is already the sender'
                                              : 'You encrypt and transmit',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                        ),
                        const SizedBox(height: 16),
                        // Receive File tile
                        Opacity(
                          opacity: receiverBlocked ? 0.4 : 1.0,
                          child: InkWell(
                            onTap: (_loading || receiverBlocked)
                                ? null
                                : () => _handleTap('receive', widget.onReceiveFile),
                            borderRadius: BorderRadius.circular(16),
                            child: GlassContainer(
                              borderRadius: 16,
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  if (_loadingRole == 'receive')
                                    SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(cs.secondary),
                                      ),
                                    )
                                  else
                                    Icon(Icons.download_rounded,
                                        size: 32, color: cs.secondary),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Receive File',
                                          style: Theme.of(context).textTheme.titleLarge,
                                        ),
                                        Text(
                                          receiverBlocked
                                              ? 'Partner is already the receiver'
                                              : 'You decrypt and save',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                        ),
                      ],
                    );
                  },
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
    final cs = Theme.of(context).colorScheme;
    if (isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondary.withValues(alpha: 0.15),
          border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Connected',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.secondary),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.tertiary.withValues(alpha: 0.15),
          border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Pending',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.tertiary),
        ),
      );
    }
  }
}

// ─── Welcome Banner ────────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  final String username;

  const _WelcomeBanner({required this.username});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassContainer(
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Welcome back to secure transfers.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Transfers Section ──────────────────────────────────────────────────

class _RecentTransfersSection extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> transfersStream;
  final String currentUid;
  final VoidCallback onViewAll;

  const _RecentTransfersSection({
    required this.transfersStream,
    required this.currentUid,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 10),
            Text(
              'Recent Transfers',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            _SectionButton(label: '+ View', onTap: onViewAll),
          ],
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: transfersStream,
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
                      Icon(Icons.inbox_outlined, size: 40, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        'No transfers yet',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final cs = Theme.of(context).colorScheme;
                final data = docs[i].data() as Map<String, dynamic>;
                final isSender = data['senderId'] == currentUid;
                final fileName = data['fileName'] as String? ?? 'file';
                final ts = data['loggedAt'] as Timestamp?;
                final dt = ts?.toDate().toLocal();
                final date = dt != null
                    ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
                    : '';
                final time = dt != null
                    ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                    : '';
                final senderUsername = data['senderUsername'] as String?;
                final receiverUsername = data['receiverUsername'] as String?;
                final peer = isSender ? receiverUsername : senderUsername;
                return GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (_isFailedStatus(data['status'] as String? ?? '')
                                  ? cs.error
                                  : isSender
                                      ? cs.primary
                                      : cs.tertiary)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isFailedStatus(data['status'] as String? ?? '')
                              ? Icons.cancel_outlined
                              : isSender
                                  ? Icons.upload_rounded
                                  : Icons.download_rounded,
                          size: 20,
                          color: _isFailedStatus(data['status'] as String? ?? '')
                              ? cs.error
                              : isSender
                                  ? cs.primary
                                  : cs.tertiary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            if (peer != null)
                              Text(
                                '${isSender ? "→" : "←"} @$peer',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (date.isNotEmpty)
                              Text(
                                '$date • $time',
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _transferStatusBadge(context, data['status'] as String? ?? '', isSender),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
