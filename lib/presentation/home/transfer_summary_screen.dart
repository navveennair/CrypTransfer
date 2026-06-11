import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/utils/transfer_status_utils.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/transfer_repository.dart';
import '../widgets/shared_widgets.dart';

class TransferSummaryScreen extends StatefulWidget {
  const TransferSummaryScreen({super.key});

  @override
  State<TransferSummaryScreen> createState() => _TransferSummaryScreenState();
}

class _TransferSummaryScreenState extends State<TransferSummaryScreen> {
  final _transferRepo = TransferRepository();
  final _authRepo = AuthRepository();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    final uid = _authRepo.currentUid ?? '';
    _stream = _transferRepo.streamAllTransfers(uid);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Transfer Summary',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load transfers',
                style: TextStyle(color: cs.error),
              ),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'No transfers yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
          final uid = _authRepo.currentUid ?? '';
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              return _TransferRow(data: data, uid: uid);
            },
          );
        },
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.data, required this.uid});

  final Map<String, dynamic> data;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSender = data['senderId'] == uid;
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
    final status = data['status'] as String? ?? '';
    final isAborted = isFailedTransferStatus(status);

    final iconColor = isAborted
        ? cs.error
        : isSender
            ? cs.primary
            : cs.tertiary;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isAborted
                  ? Icons.cancel_outlined
                  : isSender
                      ? Icons.upload_rounded
                      : Icons.download_rounded,
              size: 20,
              color: iconColor,
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
          _statusBadge(context, status, isSender, cs),
        ],
      ),
    );
  }

  Widget _statusBadge(
      BuildContext context, String status, bool isSender, ColorScheme cs) {
    if (isFailedTransferStatus(status)) {
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
}
