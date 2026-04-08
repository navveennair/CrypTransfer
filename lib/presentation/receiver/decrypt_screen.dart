import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firebase_constants.dart';
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

enum _Phase { loading, ready, decrypting, error }

// ─── DecryptScreen ────────────────────────────────────────────────────────────

class DecryptScreen extends StatefulWidget {
  final String transferId;

  const DecryptScreen({super.key, required this.transferId});

  @override
  State<DecryptScreen> createState() => _DecryptScreenState();
}

class _DecryptScreenState extends State<DecryptScreen> {
  final _repo = TransferRepository();
  final _auth = AuthRepository();

  _Phase _phase = _Phase.loading;
  String? _error;

  late TransferModel _transfer;
  String _senderUsername = '';

  @override
  void initState() {
    super.initState();
    _loadTransfer();
  }

  // ─── Step: load transfer metadata ────────────────────────────────────────

  Future<void> _loadTransfer() async {
    try {
      final transfer = await _repo.getTransfer(widget.transferId);

      // Sender username is not stored in TransferModel — fetch from users.
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

    // Track AES key locally so we can zero it if a later step fails.
    Uint8List? localAesKey;

    try {
      // Download encrypted file bytes from Firebase Storage.
      final encryptedBytes =
          await _repo.downloadEncryptedFile(widget.transferId);

      // Read RSA private key from secure storage.
      const storage = FlutterSecureStorage();
      final privateKeyJson =
          await storage.read(key: FirebaseConstants.privateKeyStorageKey);
      if (privateKeyJson == null) {
        throw Exception('Private RSA key not found on this device');
      }

      // RSA-OAEP decrypt the AES key in a background isolate via compute().
      // compute() requires a top-level function — see _decryptAesKeyIsolate.
      final encryptedAesKeyBytes = base64Decode(_transfer.encryptedAesKey);
      final aesKey = await compute(
        _decryptAesKeyIsolate,
        [privateKeyJson, encryptedAesKeyBytes],
      );
      localAesKey = aesKey;

      // AES-256-GCM decrypt the file payload.
      final iv = base64Decode(_transfer.iv);
      final decryptedBytes = await EncryptionService.decryptAesGcm(
        encryptedBytes,
        aesKey,
        iv,
      );
      localAesKey = null; // ownership transfers to DownloadConfirmScreen

      if (mounted) {
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
              decryptedBytes: decryptedBytes,
              aesKey: aesKey,
              transferredAt: DateTime.now(),
            ),
          ),
        );
      }
    } catch (e) {
      // Zero key bytes on failure before surfacing the error.
      localAesKey?.fillRange(0, localAesKey.length, 0);
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _phase = _Phase.error;
        });
      }
    }
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
      canPop: _phase != _Phase.decrypting,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Decrypt File',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          automaticallyImplyLeading: _phase != _Phase.decrypting,
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
