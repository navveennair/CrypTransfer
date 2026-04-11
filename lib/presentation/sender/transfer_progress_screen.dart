import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/security_lifecycle_mixin.dart';
import '../session/end_session_screen.dart';

class TransferProgressScreen extends StatefulWidget {
  final String transferId;
  final Uint8List encryptedBytes;
  final String fileName;
  final int fileSize;
  final String receiverUsername;
  final String receiverId;
  final String senderId;
  final String encryptedAESKeyB64;
  final String ivB64;

  /// Raw AES key bytes — passed through to EndSessionScreen for in-memory zeroing.
  final Uint8List? aesKey;

  const TransferProgressScreen({
    super.key,
    required this.transferId,
    required this.encryptedBytes,
    required this.fileName,
    required this.fileSize,
    required this.receiverUsername,
    required this.receiverId,
    required this.senderId,
    required this.encryptedAESKeyB64,
    required this.ivB64,
    this.aesKey,
  });

  @override
  State<TransferProgressScreen> createState() =>
      _TransferProgressScreenState();
}

class _TransferProgressScreenState extends State<TransferProgressScreen>
    with SingleTickerProviderStateMixin,
        SecurityLifecycleMixin<TransferProgressScreen> {
  double _progress = 0.0;
  int _bytesTransferred = 0;
  int _totalBytes = 0;
  bool _done = false;
  String? _error;
  DateTime? _completedAt;

  // ── Non-repudiation listener state ────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _transferListener;
  bool _receiverDecrypted = false;
  bool _canEndSession = false;
  String? _statusMessage;

  late AnimationController _successCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.encryptedBytes.length;
    // Register sensitive buffers — zeroed automatically on dispose.
    registerBuffer(widget.encryptedBytes);
    if (widget.aesKey != null) registerBuffer(widget.aesKey!);

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = CurvedAnimation(
      parent: _successCtrl,
      curve: Curves.elasticOut,
    );

    _startUpload();
    _startTransferListener();
  }

  @override
  void dispose() {
    _transferListener?.cancel();
    _successCtrl.dispose();
    super.dispose();
  }

  // ─── Non-repudiation: real-time receiver status ───────────────────────────

  void _startTransferListener() {
    _transferListener = FirebaseFirestore.instance
        .collection('transfers')
        .doc(widget.transferId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      final receiverStatus = data['receiverStatus'] as String?;

      if (receiverStatus == 'decrypted' && mounted) {
        setState(() {
          _receiverDecrypted = true;
          _statusMessage = '✅ Receiver successfully decrypted file';
        });
        _clearSenderLocalMetadata();
      }

      if (receiverStatus == 'saved' && mounted) {
        setState(() {
          _statusMessage = '✅ Receiver saved the file securely';
          _canEndSession = true;
        });
      }
    });
  }

  Future<void> _clearSenderLocalMetadata() async {
    await FirebaseFirestore.instance
        .collection('transfers')
        .doc(widget.transferId)
        .update({
      'senderStatus': 'metadata_cleared',
      'metadataClearedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _startUpload() async {
    try {
      final ref = FirebaseStorage.instance
          .ref('transfers/${widget.transferId}/encrypted_file');

      final metadata = SettableMetadata(
        contentType: 'application/octet-stream',
        customMetadata: {'fileName': widget.fileName},
      );

      final uploadTask = ref.putData(widget.encryptedBytes, metadata);

      uploadTask.snapshotEvents.listen((snapshot) {
        if (mounted && snapshot.totalBytes > 0) {
          setState(() {
            _bytesTransferred = snapshot.bytesTransferred;
            _totalBytes = snapshot.totalBytes;
            _progress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('transfers')
          .doc(widget.transferId)
          .set({
        'senderId': widget.senderId,
        'receiverId': widget.receiverId,
        'encryptedAESKey': widget.encryptedAESKeyB64,
        'encryptedFileUrl': downloadUrl,
        'fileName': widget.fileName,
        'fileSize': widget.fileSize,
        'iv': widget.ivB64,
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Notify receiver (non-critical)
      try {
        final senderUsername =
            FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUserId': widget.receiverId,
          'fromUsername': senderUsername,
          'type': 'file_received',
          'message': '📁 $senderUsername sent you an encrypted file',
          'transferId': widget.transferId,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      } catch (_) {}

      if (mounted) {
        setState(() {
          _progress = 1.0;
          _done = true;
          _completedAt = DateTime.now();
        });
        _successCtrl.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      // Prevent back-swipe while upload is in progress
      canPop: _done || _error != null,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _done ? 'Transfer Complete' : 'Sending File',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          automaticallyImplyLeading: _done || _error != null,
        ),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // ── File info card ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(
                      _done
                          ? Icons.lock_open_rounded
                          : Icons.lock_rounded,
                      size: 40,
                      color: _done ? Colors.green.shade600 : cs.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.fileName,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 15),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmt(widget.fileSize),
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_forward_rounded,
                            size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '@${widget.receiverUsername}',
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // ── Progress / success / error ────────────────────────────
              if (_error != null) ...[
                Icon(Icons.error_rounded, size: 64, color: cs.error),
                const SizedBox(height: 16),
                Text(
                  'Upload Failed',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: cs.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46)),
                  child: const Text('Go Back'),
                ),
              ] else if (_done) ...[
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.shade600,
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white, size: 48),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'File Sent Successfully!',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: Colors.green.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The encrypted file has been uploaded\nand the transfer record saved.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurfaceVariant, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Receiver status badge (live) ──────────────────────────
                if (_receiverDecrypted || _canEndSession)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      key: ValueKey(_statusMessage),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: (_canEndSession
                                ? Colors.green
                                : Colors.deepPurple)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _canEndSession
                              ? Colors.green.shade300
                              : Colors.deepPurple.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _canEndSession
                                ? Icons.verified_rounded
                                : Icons.lock_open_rounded,
                            size: 18,
                            color: _canEndSession
                                ? Colors.green.shade700
                                : Colors.deepPurple.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _canEndSession
                                    ? Colors.green.shade800
                                    : Colors.deepPurple.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_clock_rounded),
                  label: const Text('End Session'),
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EndSessionScreen(
                        transferId: widget.transferId,
                        fileName: widget.fileName,
                        fileSize: widget.fileSize,
                        senderUsername:
                            FirebaseAuth.instance.currentUser?.displayName ??
                                'Unknown',
                        receiverUsername: widget.receiverUsername,
                        senderId: widget.senderId,
                        receiverId: widget.receiverId,
                        transferredAt: _completedAt ?? DateTime.now(),
                        aesKey: widget.aesKey,
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ] else ...[
                Text(
                  'Uploading encrypted file…',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 14,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${(_progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                    color: cs.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '${_fmt(_bytesTransferred)} / ${_fmt(_totalBytes)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
