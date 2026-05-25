import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';

class CleanupRepository {
  final FirebaseFirestore _db;

  CleanupRepository({
    FirebaseFirestore? db,
  }) : _db = db ?? FirebaseFirestore.instance;

  /// Turn 1: Receiver initiates cleanup by writing cleanup_initiated flag and audit log
  Future<void> initiateReceiverCleanup({
    required String transferId,
    required String receiverId,
    required String senderId,
    required String senderUsername,
    required String fileName,
    required int fileSize,
  }) async {
    try {
      final batch = _db.batch();

      // Write cleanup_initiated flag to transfer doc
      batch.update(
        _db.collection(FirebaseConstants.transfers).doc(transferId),
        {'cleanup_initiated': true},
      );

      // Write receiver's personal audit record
      batch.set(
        _db
            .collection(FirebaseConstants.users)
            .doc(receiverId)
            .collection(FirebaseConstants.auditLogs)
            .doc(),
        {
          'senderId': senderId,
          'receiverId': receiverId,
          'senderUsername': senderUsername,
          'fileName': fileName,
          'fileSize': fileSize,
          'status': 'completed',
          'timestamp': FieldValue.serverTimestamp(),
          'loggedAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
    } on FirebaseException catch (e) {
      throw TransferException(
        'Cleanup initiation failed: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }

  /// Watch transfer doc for deletion (Turn 4 trigger)
  Stream<DocumentSnapshot> watchTransferForDeletion(String transferId) {
    return _db
        .collection(FirebaseConstants.transfers)
        .doc(transferId)
        .snapshots();
  }

  /// Turn 3: Complete full cleanup sequence with audit logs and batch deletes
  Future<void> completeReceiverCleanup({
    required String transferId,
    required String receiverId,
    required String senderId,
    required String senderUsername,
    required String fileName,
    required int fileSize,
  }) async {
    try {
      final batch = _db.batch();

      // Write final audit logs for both parties FIRST
      final auditPayload = {
        'senderId': senderId,
        'receiverId': receiverId,
        'senderUsername': senderUsername,
        'fileName': fileName,
        'fileSize': fileSize,
        'status': 'completed',
        'timestamp': FieldValue.serverTimestamp(),
        'loggedAt': FieldValue.serverTimestamp(),
      };

      // Sender's personal audit record
      batch.set(
        _db
            .collection(FirebaseConstants.users)
            .doc(senderId)
            .collection(FirebaseConstants.auditLogs)
            .doc(),
        auditPayload,
      );

      // Receiver's personal audit record
      batch.set(
        _db
            .collection(FirebaseConstants.users)
            .doc(receiverId)
            .collection(FirebaseConstants.auditLogs)
            .doc(),
        auditPayload,
      );

      // Delete transfer doc
      batch.delete(_db.collection(FirebaseConstants.transfers).doc(transferId));

      await batch.commit();
    } on FirebaseException catch (e) {
      throw TransferException(
        'Cleanup completion failed: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }
}
