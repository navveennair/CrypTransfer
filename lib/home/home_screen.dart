import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withReadStream: false);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.first);
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;
    setState(() => _isUploading = true);

    // TODO: encrypt with recipient's RSA public key, then upload to Firebase Storage
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
