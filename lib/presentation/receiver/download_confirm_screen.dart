import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/security_lifecycle_mixin.dart';
import '../session/end_session_screen.dart';

// ─── DownloadConfirmScreen ────────────────────────────────────────────────────

class DownloadConfirmScreen extends StatefulWidget {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String senderUsername;
  final String senderId;
  final String receiverId;
  /// Null when the file was already saved upstream (save-and-wipe pattern).
  final Uint8List? decryptedBytes;
  final Uint8List? aesKey;
  final DateTime transferredAt;
  /// Pre-populated save path when the caller already wrote the file.
  final String? savedPath;

  const DownloadConfirmScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.senderUsername,
    required this.senderId,
    required this.receiverId,
    this.decryptedBytes,
    this.aesKey,
    required this.transferredAt,
    this.savedPath,
  });

  @override
  State<DownloadConfirmScreen> createState() => _DownloadConfirmScreenState();
}

class _DownloadConfirmScreenState extends State<DownloadConfirmScreen>
    with SecurityLifecycleMixin<DownloadConfirmScreen> {
  bool _saving = false;
  String? _savedPath;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    // Pre-populate path when caller already saved the file.
    if (widget.savedPath != null) _savedPath = widget.savedPath;
    // Register plaintext and key — null when save-and-wipe pattern was used.
    if (widget.decryptedBytes != null) registerBuffer(widget.decryptedBytes!);
    if (widget.aesKey != null) registerBuffer(widget.aesKey!);
  }

  // ─── Save file ──────────────────────────────────────────────────────────────

  Future<void> _saveFile() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final Directory saveDir;

      if (Platform.isAndroid) {
        // Direct path to the public Downloads folder on Android.
        final androidDownloads = Directory('/storage/emulated/0/Download');
        saveDir = await androidDownloads.exists()
            ? androidDownloads
            : await getApplicationDocumentsDirectory();
      } else {
        saveDir = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
      }

      if (widget.decryptedBytes == null) return; // already saved upstream
      final filePath = '${saveDir.path}/${widget.fileName}';
      await File(filePath).writeAsBytes(widget.decryptedBytes!);

      if (mounted) setState(() => _savedPath = filePath);
    } catch (e) {
      if (mounted) setState(() => _saveError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Copy path to clipboard ─────────────────────────────────────────────────

  Future<void> _copyPath() async {
    if (_savedPath == null) return;
    await Clipboard.setData(ClipboardData(text: _savedPath!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Path copied to clipboard')),
      );
    }
  }

  // ─── Confirm delete dialog then end session ─────────────────────────────────

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Colors.red.shade700, size: 36),
        title: const Text('Permanently Delete?'),
        content: const Text(
          'This will delete the encrypted file and transfer record from the '
          'server. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) _goToEndSession();
  }

  // ─── Navigate to end session ────────────────────────────────────────────────

  void _goToEndSession() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EndSessionScreen(
          transferId: widget.transferId,
          fileName: widget.fileName,
          fileSize: widget.fileSize,
          senderUsername: widget.senderUsername,
          receiverUsername:
              FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown',
          senderId: widget.senderId,
          receiverId: widget.receiverId,
          transferredAt: widget.transferredAt,
          aesKey: widget.aesKey,
        ),
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text('File Decrypted',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          automaticallyImplyLeading: !_saving,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Success header ──────────────────────────────────────────────
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.shade600,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 46),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'File Decrypted Successfully!',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: Colors.green.shade700,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // ── File details card ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      icon: Icons.insert_drive_file_rounded,
                      label: 'File',
                      value: widget.fileName,
                      cs: cs,
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      icon: Icons.data_usage_rounded,
                      label: 'Size',
                      value: _fmtSize(widget.fileSize),
                      cs: cs,
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      icon: Icons.person_rounded,
                      label: 'From',
                      value: '@${widget.senderUsername}',
                      cs: cs,
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      icon: Icons.security_rounded,
                      label: 'Encryption',
                      value: 'AES-256-GCM + RSA-2048-OAEP',
                      cs: cs,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Saved path card (appears after save) ────────────────────────
              if (_savedPath != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_rounded,
                          color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Saved to: $_savedPath',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _copyPath,
                        icon: Icon(Icons.copy_rounded,
                            size: 18, color: Colors.green.shade700),
                        tooltip: 'Copy path',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Save error (if any) ─────────────────────────────────────────
              if (_saveError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 16, color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Save failed: $_saveError',
                          style:
                              TextStyle(fontSize: 13, color: cs.error),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Action buttons ──────────────────────────────────────────────
              // Save button only shown when bytes are available in memory.
              if (widget.decryptedBytes != null)
                if (_savedPath == null)
                  OutlinedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(_saving ? 'Saving…' : '💾 Save to Downloads'),
                    onPressed: _saving ? null : _saveFile,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                  )
                else
                  OutlinedButton.icon(
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('💾 Save Again'),
                    onPressed: _saving ? null : _saveFile,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50)),
                  ),

              const SizedBox(height: 10),

              FilledButton.icon(
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('🗑️ Permanently Delete'),
                onPressed: _saving ? null : _confirmDelete,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  minimumSize: const Size.fromHeight(50),
                ),
              ),

              const SizedBox(height: 10),

              TextButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: const Text('✅ Done'),
                onPressed: _saving ? null : _goToEndSession,
                style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(46)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail row ───────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: cs.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
