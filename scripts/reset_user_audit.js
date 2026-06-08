/**
 * reset_user_audit.js
 *
 * Deletes all audit log documents for a given user UID from Firestore.
 * Use this to reset a user's history during development/testing.
 *
 * SETUP (one-time):
 *   1. Go to Firebase Console → Project Settings → Service Accounts
 *   2. Generate a new private key → save as scripts/serviceAccountKey.json
 *   3. npm install firebase-admin   (run once from the scripts/ directory)
 *
 * USAGE:
 *   node scripts/reset_user_audit.js <USER_UID>
 *
 * COLLECTIONS CLEARED:
 *   - users/{uid}/audit_logs        (personal transfer audit records)
 *   - users/{uid}/rsa_key_manager   (RSA key rotation audit)
 *   - transfer_logs                 (global log — docs where participants contains uid)
 */

const admin = require('firebase-admin');
const path = require('path');

const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'serviceAccountKey.json');
const PROJECT_ID = 'cryptransfer-96e9f';

// ── Init ──────────────────────────────────────────────────────────────────────

const uid = process.argv[2];
if (!uid) {
  console.error('Usage: node scripts/reset_user_audit.js <USER_UID>');
  process.exit(1);
}

let serviceAccount;
try {
  serviceAccount = require(SERVICE_ACCOUNT_PATH);
} catch {
  console.error(`Service account key not found at: ${SERVICE_ACCOUNT_PATH}`);
  console.error('Generate one from Firebase Console → Project Settings → Service Accounts');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: PROJECT_ID,
});

const db = admin.firestore();

// ── Helpers ───────────────────────────────────────────────────────────────────

async function deleteCollection(ref, label) {
  const snapshot = await ref.get();
  if (snapshot.empty) {
    console.log(`  ${label}: 0 docs (already empty)`);
    return 0;
  }
  const batch = db.batch();
  snapshot.docs.forEach(doc => batch.delete(doc.ref));
  await batch.commit();
  console.log(`  ${label}: deleted ${snapshot.size} doc(s)`);
  return snapshot.size;
}

async function deleteByParticipant(collectionName, uid) {
  const snapshot = await db
    .collection(collectionName)
    .where('participants', 'array-contains', uid)
    .get();

  if (snapshot.empty) {
    console.log(`  ${collectionName} (participant): 0 docs`);
    return 0;
  }

  // Firestore batches are capped at 500 writes
  let deleted = 0;
  const chunks = [];
  for (let i = 0; i < snapshot.docs.length; i += 500) {
    chunks.push(snapshot.docs.slice(i, i + 500));
  }
  for (const chunk of chunks) {
    const batch = db.batch();
    chunk.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    deleted += chunk.length;
  }
  console.log(`  ${collectionName} (participant): deleted ${deleted} doc(s)`);
  return deleted;
}

// ── Main ──────────────────────────────────────────────────────────────────────

(async () => {
  console.log(`\nResetting audit logs for UID: ${uid}\n`);

  const userRef = db.collection('users').doc(uid);

  // Check user exists
  const userDoc = await userRef.get();
  if (!userDoc.exists) {
    console.warn(`Warning: No user document found for UID ${uid}. Proceeding anyway.`);
  } else {
    console.log(`User found: ${userDoc.data().username || userDoc.data().email || uid}\n`);
  }

  console.log('Deleting audit data...');

  let total = 0;
  total += await deleteCollection(userRef.collection('audit_logs'), 'users/{uid}/audit_logs');
  total += await deleteCollection(userRef.collection('rsa_key_manager'), 'users/{uid}/rsa_key_manager');
  total += await deleteByParticipant('transfer_logs', uid);

  console.log(`\nDone. ${total} document(s) deleted.`);
  console.log('The user can now start fresh.\n');

  process.exit(0);
})().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
