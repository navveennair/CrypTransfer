import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../models/transfer_model.dart';
import '../models/notification_model.dart';

class TransferRepository {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  TransferRepository({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
  })  : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ─── Generate a new transfer ID ────────────────────────────────────────────

  String generateId() =>
      _db.collection(FirebaseConstants.transfers).doc().id;

  // ─── Upload encrypted file and create transfer document ───────────────────

  /// Uploads [encryptedBytes] to Storage then writes the transfer document.
  /// Returns a stream of upload progress (0.0 → 1.0) and completes when done.
  Stream<double> uploadAndCreate({
    required String transferId,
    required Uint8List encryptedBytes,
    required String fileName,
    required int fileSize,
    required String senderId,
    required String receiverId,
    required String encryptedAESKeyB64,
    required String ivB64,
  }) async* {
    try {
      final ref = _storage.ref(
          '${FirebaseConstants.transfersStorageRoot}/$transferId/${FirebaseConstants.encryptedFileName}');

      final metadata = SettableMetadata(
        contentType: 'application/octet-stream',
        customMetadata: {'fileName': fileName},
      );

      final task = ref.putData(encryptedBytes, metadata);

      await for (final snapshot in task.snapshotEvents) {
        if (snapshot.totalBytes > 0) {
          yield snapshot.bytesTransferred / snapshot.totalBytes;
        }
      }

      final snapshot = await task;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .set({
        'senderId': senderId,
        'receiverId': receiverId,
        'encryptedAESKey': encryptedAESKeyB64,
        'encryptedFileUrl': downloadUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'iv': ivB64,
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      yield 1.0;
    } on FirebaseException catch (e) {
      throw TransferException(
          'Upload failed: ${e.message ?? e.code}', code: e.code);
    }
  }

  // ─── Notify receiver ───────────────────────────────────────────────────────

  Future<void> notifyReceiver({
    required String receiverId,
    required String senderUsername,
    required String transferId,
  }) async {
    try {
      final notif = NotificationModel(
        id: '',
        toUserId: receiverId,
        fromUsername: senderUsername,
        message: '📁 $senderUsername sent you an encrypted file',
        type: NotificationType.fileReceived,
        transferId: transferId,
        read: false,
      );
      await _db
          .collection(FirebaseConstants.users)
          .doc(receiverId)
          .collection(FirebaseConstants.notifications)
          .add(notif.toCreateMap());
    } catch (_) {
      // Non-critical — notification failure must not break the transfer
    }
  }

  // ─── Fetch transfer document ───────────────────────────────────────────────

  Future<TransferModel> getTransfer(String transferId) async {
    try {
      final doc = await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .get();
      if (!doc.exists) {
        throw TransferException('Transfer not found', code: 'not-found');
      }
      return TransferModel.fromDoc(doc);
    } on TransferException {
      rethrow;
    } on FirebaseException catch (e) {
      throw TransferException(
          'Failed to load transfer: ${e.message ?? e.code}', code: e.code);
    }
  }

  // ─── Mark transfer as received ─────────────────────────────────────────────

  Future<void> markReceived(String transferId) async {
    try {
      await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .update({
        'status': 'received',
        'receivedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw TransferException(
          'Failed to update transfer status: ${e.message ?? e.code}',
          code: e.code);
    }
  }

  // ─── Download encrypted file ───────────────────────────────────────────────

  Future<Uint8List> downloadEncryptedFile(String transferId) async {
    try {
      final ref = _storage.ref(
          '${FirebaseConstants.transfersStorageRoot}/$transferId/${FirebaseConstants.encryptedFileName}');
      final bytes = await ref.getData(FirebaseConstants.maxDownloadBytes);
      if (bytes == null) {
        throw TransferException('File download returned no data');
      }
      return bytes;
    } on TransferException {
      rethrow;
    } on FirebaseException catch (e) {
      throw TransferException(
          'File download failed: ${e.message ?? e.code}', code: e.code);
    }
  }

  // ─── Delete encrypted file from Storage ───────────────────────────────────

  Future<void> deleteStorageFile(String transferId) async {
    try {
      await _storage
          .ref(
              '${FirebaseConstants.transfersStorageRoot}/$transferId/${FirebaseConstants.encryptedFileName}')
          .delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  // ─── Write audit log ───────────────────────────────────────────────────────

  /// Write final immutable audit log to both users' collections in a batch (D-03).
  Future<void> writeFinalAuditLog({
    required String senderId,
    required String receiverId,
    required String senderUsername,
    required String receiverUsername,
    required String fileName,
    required int fileSize,
  }) async {
    final auditPayload = <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'senderUsername': senderUsername,
      'receiverUsername': receiverUsername,
      'participants': [senderId, receiverId],
      'fileName': fileName,
      'fileSize': fileSize,
      'status': 'completed',
      'timestamp': FieldValue.serverTimestamp(),
      'loggedAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(senderId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      auditPayload,
    );
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(receiverId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      auditPayload,
    );
    _addTransferNotifications(
      batch: batch,
      senderId: senderId,
      receiverId: receiverId,
      senderMessage: "Transfer of '$fileName' to @$receiverUsername completed",
      receiverMessage: "Transfer of '$fileName' from @$senderUsername completed",
      type: 'transfer_completed',
    );
    await batch.commit();
  }

  /// Write an aborted-session entry to both users' auditLogs sub-collections.
  /// Called when the sender detects a stale RSA key before encryption begins —
  /// no transfer doc exists at this point so there is nothing else to clean up.
  Future<void> writeAbortAuditLog({
    required String senderId,
    required String receiverId,
    required String senderUsername,
    required String receiverUsername,
    required String fileName,
    required int fileSize,
  }) async {
    final payload = <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'senderUsername': senderUsername,
      'receiverUsername': receiverUsername,
      'participants': [senderId, receiverId],
      'fileName': fileName,
      'fileSize': fileSize,
      'status': 'aborted',
      'timestamp': FieldValue.serverTimestamp(),
      'loggedAt': FieldValue.serverTimestamp(),
    };
    final batch = _db.batch();
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(senderId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      payload,
    );
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(receiverId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      payload,
    );
    _addTransferNotifications(
      batch: batch,
      senderId: senderId,
      receiverId: receiverId,
      senderMessage: "Transfer of '$fileName' to @$receiverUsername failed",
      receiverMessage: "Transfer of '$fileName' from @$senderUsername failed",
      type: 'transfer_aborted',
    );
    await batch.commit();
  }

  void _addTransferNotifications({
    required WriteBatch batch,
    required String senderId,
    required String receiverId,
    required String senderMessage,
    required String receiverMessage,
    required String type,
  }) {
    final now = FieldValue.serverTimestamp();
    // toUserId is required by the Firestore notifications create rule:
    //   allow create: if request.resource.data.toUserId == userId
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(senderId)
          .collection(FirebaseConstants.notifications)
          .doc(),
      {'toUserId': senderId, 'type': type, 'message': senderMessage, 'read': false, 'createdAt': now},
    );
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(receiverId)
          .collection(FirebaseConstants.notifications)
          .doc(),
      {'toUserId': receiverId, 'type': type, 'message': receiverMessage, 'read': false, 'createdAt': now},
    );
  }

  /// Atomically reset a transfer doc after a connection-lost interruption.
  /// Always sets status=failed and receiverReady=false.
  /// [wipeAesKey] additionally deletes encryptedAESKey (sender side only — rules
  /// restrict receiver from touching that field).
  Future<void> markTransferInterrupted(
    String transferId, {
    bool wipeAesKey = false,
  }) async {
    final fields = <String, dynamic>{
      'status': 'failed',
      'receiverReady': false,
    };
    if (wipeAesKey) fields['encryptedAESKey'] = FieldValue.delete();
    await _db
        .collection(FirebaseConstants.transfers)
        .doc(transferId)
        .update(fields);
  }

  /// Write a connection-lost audit log to both participants' auditLogs in one batch.
  Future<void> writeConnectionLostAuditLog({
    required String senderId,
    required String receiverId,
    String senderUsername = '',
    String receiverUsername = '',
    String fileName = '',
    int fileSize = 0,
  }) async {
    final payload = <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'senderUsername': senderUsername,
      'receiverUsername': receiverUsername,
      'participants': [senderId, receiverId],
      'fileName': fileName,
      'fileSize': fileSize,
      'status': 'connection_lost',
      'timestamp': FieldValue.serverTimestamp(),
      'loggedAt': FieldValue.serverTimestamp(),
    };
    final batch = _db.batch();
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(senderId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      payload,
    );
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(receiverId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      payload,
    );
    await batch.commit();
  }

  /// Write a kill-switch audit log to both participants' auditLogs in one
  /// batch. Called from [EncryptionService.closeReceiverSession] when the
  /// receiver's mailbox closes while a sender was actively paired
  /// (`selectedSenderUid` was set) — i.e. the session was torn down abruptly
  /// rather than via the normal end-of-transfer cleanup. Lands in the same
  /// `audit_logs` collection as every other transfer-lifecycle entry so it
  /// shows up in "Recent Transfers" and the admin dashboard's transfer-logs
  /// tab, instead of the now-removed write-only `transfer_logs` collection
  /// that nothing ever displayed.
  Future<void> writeKillSwitchAuditLog({
    required String senderId,
    required String receiverId,
  }) async {
    final payload = <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      'participants': [senderId, receiverId],
      'status': 'kill_switch',
      'timestamp': FieldValue.serverTimestamp(),
      'loggedAt': FieldValue.serverTimestamp(),
    };
    final batch = _db.batch();
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(senderId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      payload,
    );
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(receiverId)
          .collection(FirebaseConstants.auditLogs)
          .doc(),
      payload,
    );
    await batch.commit();
  }

  // ─── Delete transfer document ──────────────────────────────────────────────

  Future<void> deleteTransfer(String transferId) async {
    await _db
        .collection(FirebaseConstants.transfers)
        .doc(transferId)
        .delete();
  }

  // ─── Update receiver status ────────────────────────────────────────────────

  Future<void> updateReceiverStatus(
    String transferId,
    String status,
  ) async {
    await _db
        .collection(FirebaseConstants.transfers)
        .doc(transferId)
        .update({
      'receiverStatus': status,
      'receiverStatusUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Synchronized cleanup protocol ────────────────────────────────────────

  /// Turn 1 (Receiver): Signal that receiver has initiated the cleanup sequence.
  Future<void> initiateCleanup(String transferId) async {
    await _db.collection(FirebaseConstants.transfers).doc(transferId).update({
      'status': 'cleanup_initiated',
      'cleanupInitiatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Turn 2 (Sender): Wipe the AES key from Firestore and mark sender as cleaned up.
  Future<void> senderWipeAESKey(String transferId) async {
    await _db.collection(FirebaseConstants.transfers).doc(transferId).update({
      'encryptedAESKey': FieldValue.delete(),
      'senderCleanedUp': true,
      'senderCleanedUpAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Real-time listener for pending transfers ──────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingTransfers(
      String receiverId) {
    return _db
        .collection(FirebaseConstants.transfers)
        .where('receiverId', isEqualTo: receiverId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  /// Watch pending transfers from a specific sender to a specific receiver.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingTransfersFromSender(
    String receiverId,
    String senderId,
  ) {
    return _db
        .collection(FirebaseConstants.transfers)
        .where('receiverId', isEqualTo: receiverId)
        .where('senderId', isEqualTo: senderId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // ─── Watch transfer doc for reactive updates ───────────────────────────────

  /// Stream the transfer document for reactive UI updates
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchTransferStatus(String transferId) {
    return _db
        .collection(FirebaseConstants.transfers)
        .doc(transferId)
        .snapshots();
  }

  // ─── Stream recent transfers for HomeScreen ───────────────────────────────

  /// Stream user's 3 most recent transfers for the HomeScreen preview
  Stream<QuerySnapshot<Map<String, dynamic>>> streamRecentTransfers(
      String userId) {
    return _db
        .collection(FirebaseConstants.users)
        .doc(userId)
        .collection(FirebaseConstants.auditLogs)
        .orderBy('loggedAt', descending: true)
        .limit(3)
        .snapshots();
  }

  /// Stream all transfers for TransferSummaryScreen (no limit)
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAllTransfers(
      String userId) {
    return _db
        .collection(FirebaseConstants.users)
        .doc(userId)
        .collection(FirebaseConstants.auditLogs)
        .orderBy('loggedAt', descending: true)
        .snapshots();
  }

  // ─── Generic field update ───────────────────────────────────────────────────

  /// Update a single field on a transfer document (replaces scattered .update() calls)
  Future<void> updateTransferField(
    String transferId,
    String field,
    dynamic value,
  ) async {
    try {
      await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .update({field: value});
    } on FirebaseException catch (e) {
      throw TransferException(
        'Failed to update transfer field $field: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }

  // ─── Update transfer status with validation ────────────────────────────────

  /// Update transfer status with validation (encapsulates valid status values)
  Future<void> updateTransferStatus(
    String transferId,
    String status,
  ) async {
    try {
      // Validate status values
      const validStatuses = [
        'pending',
        'in-progress',
        'completed',
        'cancelled',
        'rejected'
      ];
      if (!validStatuses.contains(status)) {
        throw TransferException('Invalid status: $status', code: 'invalid-status');
      }

      await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .update({'status': status});
    } on TransferException {
      rethrow;
    } on FirebaseException catch (e) {
      throw TransferException(
        'Failed to update transfer status: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }

  // ─── Cancel transfer ───────────────────────────────────────────────────────

  /// Cancel a transfer (set status to cancelled and optionally delete from Storage)
  Future<void> cancelTransfer(String transferId) async {
    try {
      await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .update({'status': 'cancelled'});
    } on FirebaseException catch (e) {
      throw TransferException(
        'Failed to cancel transfer: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }

  // ─── Fetch transfer document ───────────────────────────────────────────────

  /// Check if a transfer document exists (for cleanup verification)
  Future<bool> getTransferDoc(String transferId) async {
    try {
      final doc = await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .get();
      return doc.exists;
    } on FirebaseException catch (e) {
      throw TransferException(
        'Failed to fetch transfer: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }
}
