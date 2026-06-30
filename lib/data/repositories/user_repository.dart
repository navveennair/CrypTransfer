import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';

class UserRepository {
  final FirebaseFirestore _db;

  UserRepository({
    FirebaseFirestore? db,
  }) : _db = db ?? FirebaseFirestore.instance;

  // ─── Update user document fields ───────────────────────────────────────────

  /// Update user document with provided fields (onboarding, preferences, etc.)
  Future<void> updateUser(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    try {
      await _db
          .collection(FirebaseConstants.users)
          .doc(userId)
          .update(fields);
    } on FirebaseException catch (e) {
      throw AuthException(
        'Failed to update user: ${e.message ?? e.code}',
        code: e.code,
      );
    }
  }

  // ─── Stream user document ─────────────────────────────────────────────────

  /// Stream a single user document by UID.
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUser(String userId) {
    return _db
        .collection(FirebaseConstants.users)
        .doc(userId)
        .snapshots();
  }

  /// Returns true if [partnerUid] is an accepted friend of [myUid].
  Future<bool> isFriend(String myUid, String partnerUid) async {
    final doc = await _db
        .collection(FirebaseConstants.users)
        .doc(myUid)
        .collection(FirebaseConstants.friendships)
        .doc(partnerUid)
        .get();
    return doc.exists && doc.data()?['status'] == 'accepted';
  }

  // ─── Stream user with friendships for connection map ─────────────────────

  /// Stream user document with their friendships (for connection node map visualization)
  Stream<Map<String, dynamic>?> streamUserWithFriendships(String userId) {
    return _db
        .collection(FirebaseConstants.users)
        .doc(userId)
        .snapshots()
        .asyncMap((userDoc) async {
          if (!userDoc.exists) return null;

          final userData = userDoc.data() ?? {};

          // Fetch user's friends
          final friendships = await _db
              .collection(FirebaseConstants.users)
              .doc(userId)
              .collection(FirebaseConstants.friendships)
              .where('status', isEqualTo: 'accepted')
              .get();

          userData['friendships'] = friendships.docs
              .map((doc) => doc.data())
              .toList();

          return userData;
        });
  }
}
