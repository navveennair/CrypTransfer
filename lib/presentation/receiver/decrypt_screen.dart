import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/models/transfer_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../../data/services/encryption_service.dart';
import 'download_confirm_screen.dart';

// ─── Top-level isolate helper (compute() requires top-level / static) ─────────

Uint8List _decryptAesKeyIsolate(List<dynamic> args) {
  final privateKeyJson = args[0] as String;
  final encryptedBytes = args[1] as Uint8List;
  return EncryptionService.decryptAesKeyWithPrivateKeyJson(
    privateKeyJson,
    encryptedBytes,
  );
}

// ─── Screen phases ────────────────────────────────────────────────────────────

enum _Phase { loading, ready, decrypting, done, error }

// ─── DecryptScreen ────────────────────────────────────────────────────────────

class DecryptScreen extends StatefulWidget {
  final String transferId;

  const DecryptScreen({super.key, required this.transferId});

  @override
  State<DecryptScreen> createState() => _DecryptScreenState();
}

class _DecryptScreenState extends State<DecryptScreen>
    with SecurityLifecycleMixin<DecryptScreen> {
  static const _fileChannel = MethodChannel('com.example.cryptransfer/file');

  final _repo = TransferRepository();
  final _auth = AuthRepository();

  _Phase _phase = _Phase.loading;
  String? _error;

  late TransferModel _transfer;
  String _senderUsername = '';

  // Radioactive buffer — zeroed by SecurityLifecycleMixin on dispose.
  Uint8List? _decryptedBytes;

  // Temp file path for preview; deleted on wipe, pop, or dispose.
  String? _tempFilePath;

  bool _saving = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _loadTransfer();
  }

  // Zero remanence: delete temp file whenever buffers are wiped.
  @override
  void onBuffersWiped() {
    _deleteTempFile();
  }

  // ─── Step: load transfer metadata ────────────────────────────────────────

  Future<void> _loadTransfer() async {
    try {
      final transfer = await _repo.getTransfer(widget.transferId);

      final results = await Future.wait([
        _auth.getUserProfile(transfer.senderId),
        _repo.markReceived(widget.transferId),
      ]);
      final senderUsername = (results[0] as UserModel?)?.username ?? 'Unknown';

      if (mounted) {
        setState(() {
          _transfer = transfer;
          _senderUsername = senderUsername;
          _phase = _Phase.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _phase = _Phase.error;
        });
      }
    }
  }

  // ─── Step: decrypt ────────────────────────────────────────────────────────

  Future<void> _decrypt() async {
    setState(() => _phase = _Phase.decrypting);

    try {
      await _repo.updateReceiverStatus(widget.transferId, 'downloading');

      final encryptedBytes =
          await _repo.downloadEncryptedFile(widget.transferId);

      const storage = FlutterSecureStorage();
      final privateKeyJson =
          await storage.read(key: FirebaseConstants.privateKeyStorageKey);
      if (privateKeyJson == null) {
        throw Exception('Private RSA key not found on this device');
      }

      final encryptedAESKeyBytes = base64Decode(_transfer.encryptedAESKey);
      final aesKey = await compute(
        _decryptAesKeyIsolate,
        [privateKeyJson, encryptedAESKeyBytes],
      );
      registerBuffer(aesKey);

      await _repo.updateReceiverStatus(widget.transferId, 'decrypting');

      final ivBuffer = Uint8List.fromList(base64Decode(_transfer.iv));
      registerBuffer(ivBuffer);

      final decryptedBytes = await EncryptionService.decryptAesGcm(
        encryptedBytes,
        aesKey,
        ivBuffer,
      );
      registerBuffer(decryptedBytes);

      await _repo.updateReceiverStatus(widget.transferId, 'decrypted');

      _decryptedBytes = decryptedBytes;

      // Write to temp dir so the file is available for preview immediately.
      final tempDir = await getTemporaryDirectory();
      _tempFilePath = '${tempDir.path}/${_transfer.fileName}';
      await File(_tempFilePath!).writeAsBytes(_decryptedBytes!);

      if (mounted) {
        setState(() => _phase = _Phase.done);
      }
    } catch (e) {
      wipeAll();
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _phase = _Phase.error;
        });
      }
    }
  }

  // ─── Step: preview ────────────────────────────────────────────────────────

  Future<void> _preview() async {
    if (_tempFilePath == null) return;
    setState(() => _previewing = true);
    try {
      final result = await OpenFile.open(_tempFilePath!);
      if (result.type == ResultType.noAppToOpen && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app found to open this file type')),
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  // ─── Step: save then navigate ─────────────────────────────────────────────

  Future<void> _saveAndWipe() async {
    setState(() => _saving = true);
    try {
      // Native channel writes to public Downloads via MediaStore (Android 10+)
      // or direct FileOutputStream (Android <10).
      await _fileChannel.invokeMethod<String>('saveToDownloads', {
        'fileName': _transfer.fileName,
        'bytes': _decryptedBytes!,
      });

      await _repo.updateReceiverStatus(widget.transferId, 'saved');

      // Eagerly wipe decrypted bytes before navigating.
      _decryptedBytes?.fillRange(0, _decryptedBytes!.length, 0);
      _decryptedBytes = null;
      _deleteTempFile();
      wipeAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('File saved to Downloads'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DownloadConfirmScreen(
              transferId: widget.transferId,
              fileName: _transfer.fileName,
              fileSize: _transfer.fileSize,
              senderUsername: _senderUsername,
              senderId: _transfer.senderId,
              receiverId: _transfer.receiverId,
              savedPath: 'Downloads/${_transfer.fileName}',
              transferredAt: DateTime.now(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ─── Delete temp file (fire-and-forget, zero-remanence) ──────────────────

  void _deleteTempFile() {
    final path = _tempFilePath;
    _tempFilePath = null;
    if (path == null) return;
    File(path).exists().then((exists) {
      if (exists) File(path).delete().ignore();
    }).ignore();
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _phase != _Phase.decrypting && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) wipeAll();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Decrypt File',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          automaticallyImplyLeading:
              _phase != _Phase.decrypting && !_saving,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(cs),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    return switch (_phase) {
      _Phase.loading => const Center(child: CircularProgressIndicator()),
      _Phase.ready => _buildReady(cs),
      _Phase.decrypting => _buildDecrypting(cs),
      _Phase.done => _buildDone(cs),
      _Phase.error => _buildError(cs),
    };
  }

  Widget _buildReady(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(Icons.lock_rounded, size: 44, color: cs.primary),
              const SizedBox(height: 12),
              Text(
                _transfer.fileName,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 15),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _fmtSize(_transfer.fileSize),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.person_rounded,
                label: 'From',
                value: '@$_senderUsername',
              ),
              const SizedBox(height: 6),
              _InfoRow(
                icon: Icons.security_rounded,
                label: 'Encryption',
                value: 'AES-256-GCM + RSA-2048-OAEP',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your private RSA key will be used to recover the AES key. '
                  'The decrypted file is only available locally on this device.',
                  style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontSize: 13,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Decrypt File'),
          onPressed: _decrypt,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }

  Widget _buildDecrypting(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(height: 28),
        Text(
          'Decrypting…',
          style:
              GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 20),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Downloading and decrypting your file.\nPlease wait.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildDone(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Success header ────────────────────────────────────────────────
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade600,
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Decryption Complete',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.green.shade700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _transfer.fileName,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500, fontSize: 14),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          _fmtSize(_transfer.fileSize),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          textAlign: TextAlign.center,
        ),

        // ── Status line ───────────────────────────────────────────────────
        const SizedBox(height: 16),
        if (_error != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 14, color: cs.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Save failed: $_error',
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 14, color: Colors.green.shade600),
              const SizedBox(width: 6),
              Text(
                'Ready to save',
                style: TextStyle(
                    fontSize: 12, color: Colors.green.shade600),
              ),
            ],
          ),

        const Spacer(),

        // ── Preview button ────────────────────────────────────────────────
        OutlinedButton.icon(
          icon: _previewing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.visibility_rounded),
          label: Text(_previewing ? 'Opening…' : 'Preview File'),
          onPressed: (_previewing || _saving || _tempFilePath == null)
              ? null
              : _preview,
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50)),
        ),

        const SizedBox(height: 10),

        // ── Save & Continue button ─────────────────────────────────────────
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_alt_rounded),
          label: Text(_saving ? 'Saving…' : 'Save & Continue'),
          onPressed: _saving ? null : _saveAndWipe,
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }

  Widget _buildError(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_rounded, size: 64, color: cs.error),
        const SizedBox(height: 16),
        Text(
          'Decryption Failed',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, fontSize: 18, color: cs.error),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'An unknown error occurred.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
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
