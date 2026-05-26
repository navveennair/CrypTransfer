import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firebase_constants.dart';

/// Writes transfer metadata to [transfer_logs] at the start of every transfer.
/// The completion entry is written by [EndSessionScreen] via [TransferRepository.writeAuditLog].
class TransferLogService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Logs the start of a transfer. Called immediately after the upload task begins.
  static Future<void> logTransferStart({
    required String transferId,
    required String senderId,
    required String receiverId,
    required String fileName,
    required int fileSize,
  }) async {
    try {
      await _db
          .collection(FirebaseConstants.transferLogs)
          .add({
        'transferId': transferId,
        'senderId': senderId,
        'receiverId': receiverId,
        'participants': [senderId, receiverId],
        'fileName': fileName,
        'fileSize': fileSize,
        'status': 'started',
        'startedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-critical — logging failure must not abort the transfer.
    }
  }
}
