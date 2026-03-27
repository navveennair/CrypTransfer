import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import 'end_session_screen.dart';

// ─── Top-level isolate function (must be top-level for compute()) ─────────────

Uint8List _runAesGcmDecrypt(List<Uint8List> args) {
  final ciphertext = args[0]; // ciphertext + 16-byte GCM tag appended
  final key = args[1]; // 32 bytes
  final iv = args[2]; // 12 bytes

  final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
  final cipher = GCMBlockCipher(AESEngine())..init(false, params);
  return cipher.process(ciphertext);
}

// ─── Screen phases ─────────────────────────────────────────────────────────────

enum _Phase { loading, ready, decrypting, done, error }

// ─── DecryptScreen ─────────────────────────────────────────────────────────────

class DecryptScreen extends StatefulWidget {
  final String transferId;

  const DecryptScreen({super.key, required this.transferId});

  @override
  State<DecryptScreen> createState() => _DecryptScreenState();
}

class _DecryptScreenState extends State<DecryptScreen> {
  _Phase _phase = _Phase.loading;
  String? _error;

  String _fileName = '';
  int _fileSize = 0;
  String _senderUsername = '';
  String _senderId = '';
  String _receiverId = '';
  String _encryptedAesKeyB64 = '';
  String _ivB64 = '';

  Uint8List? _decryptedBytes;
  Uint8List? _aesKey;

  @override
  void initState() {
    super.initState();
    _loadTransfer();
  }

  Future<void> _loadTransfer() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('transfers')
          .doc(widget.transferId)
          .get();

      if (!doc.exists) throw Exception('Transfer not found');

      final data = doc.data()!;
      final senderId = data['senderId'] as String;

      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(senderId)
          .get();
      final senderUsername =
          senderDoc.data()?['username'] as String? ?? 'Unknown';

      // Mark as received
      await FirebaseFirestore.instance
          .collection('transfers')
          .doc(widget.transferId)
          .update({
        'status': 'received',
        'receivedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _fileName = data['fileName'] as String? ?? 'file';
          _fileSize = data['fileSize'] as int? ?? 0;
          _senderUsername = senderUsername;
          _senderId = senderId;
          _receiverId = data['receiverId'] as String? ?? '';
          _encryptedAesKeyB64 = data['encryptedAESKey'] as String? ?? '';
          _ivB64 = data['iv'] as String? ?? '';
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

  Future<void> _decrypt() async {
    setState(() => _phase = _Phase.decrypting);

    try {
      // Step 1: Download encrypted file (100 MB max)
      final encryptedBytes = await FirebaseStorage.instance
          .ref('transfers/${widget.transferId}/encrypted_file')
          .getData(100 * 1024 * 1024);
      if (encryptedBytes == null) throw Exception('Failed to download file');

      // Step 2: Get private key from secure storage
      const secure = FlutterSecureStorage();
      final privateKeyJson = await secure.read(key: 'rsa_private_key');
      if (privateKeyJson == null) {
        throw Exception('Private key not found on this device');
      }

      // Step 3: RSA-OAEP decrypt the AES key
      final encryptedAesKeyBytes = base64Decode(_encryptedAesKeyB64);
      final aesKey = _rsaDecrypt(privateKeyJson, encryptedAesKeyBytes);

      // Step 4: AES-256-GCM decrypt via compute() isolate
      final iv = base64Decode(_ivB64);
      final plaintext = await compute(
        _runAesGcmDecrypt,
        [encryptedBytes, aesKey, iv],
      );

      if (mounted) {
        setState(() {
          _decryptedBytes = plaintext;
          _aesKey = aesKey;
          _phase = _Phase.done;
        });
      }
    } catch (e) {
      // Zero key bytes on failure
      _aesKey?.fillRange(0, _aesKey!.length, 0);
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _phase = _Phase.error;
        });
      }
    }
  }

  /// Decodes JSON private key and RSA-OAEP decrypts [ciphertext].
  Uint8List _rsaDecrypt(String privateKeyJson, Uint8List ciphertext) {
    final map = jsonDecode(privateKeyJson) as Map<String, dynamic>;
    final modulus = BigInt.parse(map['modulus'] as String, radix: 16);
    final privateExp = BigInt.parse(map['privateExponent'] as String, radix: 16);
    final p = BigInt.parse(map['p'] as String, radix: 16);
    final q = BigInt.parse(map['q'] as String, radix: 16);
    final privateKey = RSAPrivateKey(modulus, privateExp, p, q);

    final cipher = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return cipher.process(ciphertext);
  }

  Future<void> _saveFile() async {
    final bytes = _decryptedBytes;
    if (bytes == null) return;
    try {
      final String downloadsPath;
      if (Platform.isWindows) {
        downloadsPath =
            '${Platform.environment['USERPROFILE']}\\Downloads\\$_fileName';
      } else {
        downloadsPath =
            '${Platform.environment['HOME']}/Downloads/$_fileName';
      }
      await File(downloadsPath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $downloadsPath'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _goToEndSession() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EndSessionScreen(
          transferId: widget.transferId,
          fileName: _fileName,
          fileSize: _fileSize,
          senderUsername: _senderUsername,
          receiverUsername:
              FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown',
          senderId: _senderId,
          receiverId: _receiverId,
          transferredAt: DateTime.now(),
          aesKey: _aesKey,
        ),
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

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
                _fileName,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 15),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _fmtSize(_fileSize),
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
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 52, color: Colors.green.shade600),
              const SizedBox(height: 12),
              Text(
                'File Decrypted!',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Colors.green.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _fileName,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _fmtSize(_decryptedBytes?.length ?? _fileSize),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.save_alt_rounded),
          label: const Text('💾 Save to Downloads'),
          onPressed: _saveFile,
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('🗑️ Permanently Delete'),
          onPressed: _goToEndSession,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            minimumSize: const Size.fromHeight(50),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          icon: const Icon(Icons.check_rounded),
          label: const Text('✅ Done'),
          onPressed: _goToEndSession,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(46)),
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
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
