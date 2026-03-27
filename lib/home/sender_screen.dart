import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import '../utils/biometric_helper.dart';
import 'connection_service.dart';
import 'transfer_progress_screen.dart';

// ─── Isolate-safe AES-256-GCM encrypt ────────────────────────────────────────
// Must be a top-level function for Flutter compute().

Uint8List _runAesGcm(List<Uint8List> args) {
  final plaintext = args[0];
  final key = args[1];
  final iv = args[2];
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return cipher.process(plaintext);
}

// ─── Widget ──────────────────────────────────────────────────────────────────

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  final _connService = ConnectionService();

  // File
  PlatformFile? _file;

  // Crypto
  Uint8List? _encryptedBytes;
  Uint8List? _aesKey;
  Uint8List? _iv;

  // Receiver + RSA
  String? _receiverId;
  String? _receiverUsername;
  Uint8List? _encryptedAesKey;

  // UI
  bool _encrypting = false;
  bool _loadingKeys = false;

  bool get _fileSelected => _file != null;
  bool get _fileEncrypted => _encryptedBytes != null;
  bool get _readyToSend => _encryptedAesKey != null;

  // ─── File picker ─────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      setState(() {
        _file = result.files.first;
        // Reset downstream state when a new file is picked
        _encryptedBytes = null;
        _aesKey = null;
        _iv = null;
        _receiverId = null;
        _receiverUsername = null;
        _encryptedAesKey = null;
      });
    } catch (e) {
      if (mounted) _showError('Could not open file picker: $e');
    }
  }

  // ─── AES-256-GCM encrypt ─────────────────────────────────────────────────

  Future<void> _encryptFile() async {
    final file = _file;
    if (file == null || file.bytes == null) return;
    setState(() => _encrypting = true);

    try {
      final key = _secureBytes(32); // 256-bit AES key
      final iv = _secureBytes(12);  // 96-bit GCM nonce

      final encrypted = await compute(_runAesGcm, [file.bytes!, key, iv]);

      if (mounted) {
        setState(() {
          _aesKey = key;
          _iv = iv;
          _encryptedBytes = encrypted;
          // Reset receiver selection — file changed
          _receiverId = null;
          _receiverUsername = null;
          _encryptedAesKey = null;
          _encrypting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _encrypting = false);
        _showError('Encryption failed: $e');
      }
    }
  }

  Uint8List _secureBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  // ─── RSA Key Manager (biometric gated) ───────────────────────────────────

  Future<void> _openRsaKeyManager() async {
    final aesKey = _aesKey;
    if (aesKey == null) {
      _showError('Encrypt the file first (Step 2).');
      return;
    }

    // 1. Face ID gate
    final ok = await BiometricHelper.authenticate(
        'Authenticate to access the RSA Key Manager');
    if (!ok || !mounted) return;

    // 2. Load keys in parent context — errors are visible here
    setState(() => _loadingKeys = true);
    List<Map<String, dynamic>> keys;
    try {
      keys = await _connService.getReceivedKeys();
    } catch (e) {
      if (mounted) {
        setState(() => _loadingKeys = false);
        _showError('Failed to load keys: $e');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loadingKeys = false);

    // 3. Show sheet with pre-loaded data (no async in initState)
    final result = await showModalBottomSheet<_ReceiverSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReceiverKeySheet(
        receiverKeys: keys,
        aesKey: aesKey,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _receiverId = result.uid;
        _receiverUsername = result.username;
        _encryptedAesKey = result.encryptedAesKey;
      });
    }
  }

  // ─── Send ─────────────────────────────────────────────────────────────────

  void _send() {
    final file = _file;
    final encryptedBytes = _encryptedBytes;
    final encryptedAesKey = _encryptedAesKey;
    final iv = _iv;
    final receiverId = _receiverId;
    final receiverUsername = _receiverUsername;
    final senderId = FirebaseAuth.instance.currentUser?.uid;

    if (file == null ||
        encryptedBytes == null ||
        encryptedAesKey == null ||
        iv == null ||
        receiverId == null ||
        receiverUsername == null ||
        senderId == null) { return; }

    final transferId =
        FirebaseFirestore.instance.collection('transfers').doc().id;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => TransferProgressScreen(
          transferId: transferId,
          encryptedBytes: encryptedBytes,
          fileName: file.name,
          fileSize: file.size,
          receiverUsername: receiverUsername,
          receiverId: receiverId,
          senderId: senderId,
          encryptedAesKeyB64: base64Encode(encryptedAesKey),
          ivB64: base64Encode(iv),
          aesKey: _aesKey,
        ),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Send File',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── RSA Keys Received ────────────────────────────────────────
            _RsaKeyPreviewSection(connService: _connService),
            const SizedBox(height: 16),

            // ── Step 1: Select File ─────────────────────────────────────
            _StepCard(
              step: 1,
              title: 'Select File',
              done: _fileSelected,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(
                        _file == null ? 'Browse Files' : 'Change File'),
                    onPressed: _pickFile,
                  ),
                  if (_file != null) ...[
                    const SizedBox(height: 12),
                    _FileCard(file: _file!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 2: Encrypt ─────────────────────────────────────────
            AnimatedOpacity(
              opacity: _fileSelected ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: _StepCard(
                step: 2,
                title: 'Encrypt File (AES-256-GCM)',
                done: _fileEncrypted,
                child: _fileEncrypted
                    ? _EncryptedBadge(
                        keyBits: _aesKey!.length * 8,
                        ivBytes: _iv!.length,
                        ciphertextBytes: _encryptedBytes!.length,
                      )
                    : FilledButton.icon(
                        icon: _encrypting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.lock_rounded),
                        label: Text(_encrypting
                            ? 'Encrypting…'
                            : 'Generate AES Key & Encrypt'),
                        onPressed:
                            _fileSelected && !_encrypting ? _encryptFile : null,
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.secondary),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 3: RSA Key Manager ─────────────────────────────────
            AnimatedOpacity(
              opacity: _fileEncrypted ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: _StepCard(
                step: 3,
                title: 'RSA Key Manager',
                done: _readyToSend,
                child: _readyToSend
                    ? _ReceiverBadge(username: _receiverUsername!)
                    : FilledButton.icon(
                        icon: _loadingKeys
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.manage_accounts_rounded),
                        label: Text(_loadingKeys
                            ? 'Loading keys…'
                            : 'Select Receiver & Encrypt Key'),
                        onPressed: _fileEncrypted && !_loadingKeys
                            ? _openRsaKeyManager
                            : null,
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.tertiary),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Step 4: Send ────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _readyToSend
                  ? FilledButton.icon(
                      key: const ValueKey('send-btn'),
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Send Encrypted File'),
                      onPressed: _send,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        minimumSize: const Size.fromHeight(50),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('send-empty')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step card ────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final int step;
  final String title;
  final bool done;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.title,
    required this.done,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? Colors.green.shade400 : cs.outlineVariant,
          width: done ? 1.5 : 1.0,
        ),
        color: done
            ? Colors.green.withValues(alpha: 0.05)
            : cs.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? Colors.green.shade600 : cs.primary,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text('$step',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─── File card ────────────────────────────────────────────────────────────────

class _FileCard extends StatelessWidget {
  final PlatformFile file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = (file.extension ?? '').toLowerCase();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _extColor(ext).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_extIcon(ext), color: _extColor(ext), size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtSize(file.size),
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _extIcon(String ext) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
      return Icons.video_file_rounded;
    }
    if (['mp3', 'wav', 'flac', 'aac', 'm4a'].contains(ext)) {
      return Icons.audio_file_rounded;
    }
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['doc', 'docx'].contains(ext)) return Icons.description_rounded;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart_rounded;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _extColor(String ext) {
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return Colors.blue;
    }
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Colors.purple;
    if (['mp3', 'wav', 'flac'].contains(ext)) return Colors.orange;
    if (ext == 'pdf') return Colors.red;
    if (['doc', 'docx'].contains(ext)) return Colors.blue.shade700;
    if (['xls', 'xlsx'].contains(ext)) return Colors.green;
    if (['zip', 'rar', '7z'].contains(ext)) return Colors.brown;
    return Colors.grey;
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ─── Encrypted badge ──────────────────────────────────────────────────────────

class _EncryptedBadge extends StatelessWidget {
  final int keyBits;
  final int ivBytes;
  final int ciphertextBytes;

  const _EncryptedBadge({
    required this.keyBits,
    required this.ivBytes,
    required this.ciphertextBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.shade700, size: 18),
              const SizedBox(width: 8),
              Text('AES-256-GCM encrypted',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800)),
            ],
          ),
          const SizedBox(height: 8),
          _Row('Key', '$keyBits bits'),
          _Row('IV (nonce)', '$ivBytes bytes'),
          _Row('Ciphertext', '${_fmtSize(ciphertextBytes)} + 16 B auth tag'),
        ],
      ),
    );
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Receiver badge ───────────────────────────────────────────────────────────

class _ReceiverBadge extends StatelessWidget {
  final String username;

  const _ReceiverBadge({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.person_rounded,
              color: Colors.deepPurple.shade700, size: 18),
          const SizedBox(width: 8),
          Text('Encrypting for ',
              style: TextStyle(
                  fontSize: 13, color: Colors.deepPurple.shade700)),
          Text('@$username',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.deepPurple.shade700)),
          const Spacer(),
          Icon(Icons.check_circle_rounded,
              color: Colors.deepPurple.shade600, size: 18),
        ],
      ),
    );
  }
}

// ─── RSA Keys Received preview (top of Sender screen) ────────────────────────

class _RsaKeyPreviewSection extends StatefulWidget {
  final ConnectionService connService;
  const _RsaKeyPreviewSection({required this.connService});

  @override
  State<_RsaKeyPreviewSection> createState() => _RsaKeyPreviewSectionState();
}

class _RsaKeyPreviewSectionState extends State<_RsaKeyPreviewSection> {
  bool _expanded = false;
  bool _loading = false;
  List<Map<String, dynamic>> _keys = [];

  Future<void> _expand() async {
    final ok = await BiometricHelper.authenticate(
        'Authenticate to view received RSA keys');
    if (!ok || !mounted) return;
    setState(() {
      _loading = true;
      _expanded = true;
    });
    try {
      final keys = await widget.connService.getReceivedKeys();
      if (mounted) setState(() { _keys = keys; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _expanded = false; _loading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load keys: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _expanded ? null : _expand,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Icon(Icons.vpn_key_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'RSA Keys Received',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                if (!_expanded)
                  Row(
                    children: [
                      const Icon(Icons.face_retouching_natural_rounded,
                          size: 14),
                      const SizedBox(width: 4),
                      Text('Tap to view',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            if (_loading)
              const LinearProgressIndicator()
            else if (_keys.isEmpty)
              Text('No RSA keys received yet.',
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
            else
              ..._keys.map((k) {
                final name = (k['fromUsername'] ?? 'Unknown') as String;
                final ts = k['sentAt'] as Timestamp?;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('@$name',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            if (ts != null)
                              Text(
                                _fmtTs(ts.toDate()),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      Chip(
                        label: const Text('Key Received ✅'),
                        backgroundColor:
                            Colors.green.withValues(alpha: 0.1),
                        labelStyle: const TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.w600),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  String _fmtTs(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ─── Receiver selection result ────────────────────────────────────────────────

class _ReceiverSelection {
  final String uid;
  final String username;
  final Uint8List encryptedAesKey;

  const _ReceiverSelection({
    required this.uid,
    required this.username,
    required this.encryptedAesKey,
  });
}

// ─── Receiver Key Sheet (pre-loaded data, no async in initState) ──────────────

class _ReceiverKeySheet extends StatefulWidget {
  final List<Map<String, dynamic>> receiverKeys;
  final Uint8List aesKey;

  const _ReceiverKeySheet({
    required this.receiverKeys,
    required this.aesKey,
  });

  @override
  State<_ReceiverKeySheet> createState() => _ReceiverKeySheetState();
}

class _ReceiverKeySheetState extends State<_ReceiverKeySheet> {
  String? _encryptingFor;

  Future<void> _select(Map<String, dynamic> entry) async {
    final uid = entry['fromUserId'] as String;
    final username = (entry['fromUsername'] ?? 'Unknown') as String;
    final publicKeyJson = entry['publicKey'] as String?;

    if (publicKeyJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public key not available for this user.')),
      );
      return;
    }

    setState(() => _encryptingFor = uid);
    try {
      final rsaKey = _decodePublicKey(publicKeyJson);
      final encryptedAesKey = _rsaOaepEncrypt(widget.aesKey, rsaKey);
      if (mounted) {
        Navigator.pop(
          context,
          _ReceiverSelection(
            uid: uid,
            username: username,
            encryptedAesKey: encryptedAesKey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _encryptingFor = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSA encryption failed: $e')),
        );
      }
    }
  }

  RSAPublicKey _decodePublicKey(String encoded) {
    final map = jsonDecode(encoded) as Map<String, dynamic>;
    return RSAPublicKey(
      BigInt.parse(map['modulus'] as String, radix: 16),
      BigInt.parse(map['exponent'] as String, radix: 16),
    );
  }

  Uint8List _rsaOaepEncrypt(Uint8List data, RSAPublicKey publicKey) {
    final cipher = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return cipher.process(data);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Icon(Icons.manage_accounts_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Text('Select Receiver',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 18)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select a receiver — their public key will RSA-OAEP encrypt your AES key.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: widget.receiverKeys.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.key_off_outlined,
                              size: 48, color: cs.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            'No RSA keys received yet.\n'
                            'Ask the receiver to send their public key first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.receiverKeys.length,
                    itemBuilder: (_, i) {
                      final entry = widget.receiverKeys[i];
                      final uid = entry['fromUserId'] as String;
                      final username =
                          (entry['fromUsername'] ?? 'Unknown') as String;
                      final busy = _encryptingFor == uid;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              username.isNotEmpty
                                  ? username[0].toUpperCase()
                                  : '?',
                              style:
                                  TextStyle(color: cs.onPrimaryContainer),
                            ),
                          ),
                          title: Text(username,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Row(
                            children: [
                              Icon(Icons.key_rounded,
                                  size: 13,
                                  color: Colors.green.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'RSA public key available',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade600),
                              ),
                            ],
                          ),
                          trailing: busy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : FilledButton(
                                  onPressed: () => _select(entry),
                                  child: const Text('Select'),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
