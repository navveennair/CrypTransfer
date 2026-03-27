import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/notification_service.dart';
import 'notifications_screen.dart';
import 'receiver_screen.dart';
import 'sender_screen.dart';
import 'sidebar_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlatformFile? _selectedFile;
  bool _isUploading = false;

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
          NotificationService.markRead(docId);
        },
        onTap: () {
          entry.remove();
          if (_bannerEntry == entry) _bannerEntry = null;
          NotificationService.markRead(docId);
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withReadStream: false);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.first);
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;
    setState(() => _isUploading = true);

    await Future.delayed(const Duration(seconds: 2)); // placeholder

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${_selectedFile!.name}" uploaded successfully!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      setState(() {
        _selectedFile = null;
        _isUploading = false;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

            Text(
              'Send a File',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),

            // ── Drop zone ─────────────────────────────────────
            GestureDetector(
              onTap: _isUploading ? null : _pickFile,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 180,
                decoration: BoxDecoration(
                  color: _selectedFile != null
                      ? cs.primaryContainer.withValues(alpha: 0.5)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedFile != null ? cs.primary : cs.outline,
                    width: _selectedFile != null ? 2 : 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: _selectedFile == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file_rounded,
                              size: 48, color: cs.primary),
                          const SizedBox(height: 10),
                          Text(
                            'Tap to select a file',
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'File will be encrypted before upload',
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            _fileIcon(_selectedFile!.extension, cs),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedFile!.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatSize(_selectedFile!.size),
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, color: cs.error),
                              onPressed: _isUploading
                                  ? null
                                  : () =>
                                      setState(() => _selectedFile = null),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Upload button ─────────────────────────────────
            _isUploading
                ? Column(
                    children: [
                      LinearProgressIndicator(
                          borderRadius: BorderRadius.circular(8)),
                      const SizedBox(height: 10),
                      Text('Encrypting & uploading…',
                          style: TextStyle(color: cs.primary)),
                    ],
                  )
                : FilledButton.icon(
                    onPressed: _selectedFile != null ? _uploadFile : null,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload Encrypted'),
                  ),

            const SizedBox(height: 32),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 12),

            // ── Recent transfers placeholder ──────────────────
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
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 48, color: cs.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text(
                      'No transfers yet',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileIcon(String? ext, ColorScheme cs) {
    IconData icon;
    Color color;
    switch (ext?.toLowerCase()) {
      case 'pdf':
        icon = Icons.picture_as_pdf_outlined;
        color = Colors.red;
        break;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        icon = Icons.image_outlined;
        color = Colors.green;
        break;
      case 'mp4':
      case 'mov':
      case 'avi':
        icon = Icons.videocam_outlined;
        color = Colors.purple;
        break;
      case 'doc':
      case 'docx':
        icon = Icons.description_outlined;
        color = Colors.blue;
        break;
      case 'zip':
      case 'rar':
        icon = Icons.folder_zip_outlined;
        color = Colors.orange;
        break;
      default:
        icon = Icons.insert_drive_file_outlined;
        color = cs.primary;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 36),
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
