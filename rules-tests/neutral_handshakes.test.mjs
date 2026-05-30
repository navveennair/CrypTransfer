import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { setDoc, updateDoc, getDoc, deleteDoc, doc } from 'firebase/firestore';
import { after, before, describe, it } from 'mocha';

const PROJECT_ID = 'cryptransfer-96e9f';
const USER_A = 'user-a-uid';
const USER_B = 'user-b-uid';
const USER_C = 'user-c-uid';
const DOC_PATH = 'neutral_handshakes/userA_userB';

const PENDING_DOC = {
  proposerId: USER_A,
  partnerId: USER_B,
  status: 'pending',
  proposerUsername: 'alice',
  partnerUsername: 'bob',
  updatedAt: new Date(),
};

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

describe('HAND-09 — neutral_handshakes Firestore rules', () => {
  beforeEach(async () => {
    // Seed the doc as admin (bypasses rules) for update/read tests.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), DOC_PATH), PENDING_DOC);
    });
  });

  afterEach(async () => {
    await testEnv.clearFirestore();
  });

  it('HAND-09-1: Create with proposerId ≠ auth.uid → DENY', async () => {
    const userA = testEnv.authenticatedContext(USER_A);
    await assertFails(
      setDoc(doc(userA.firestore(), 'neutral_handshakes/bad_doc'), {
        proposerId: USER_B, // wrong — auth is A but proposerId is B
        partnerId: USER_A,
        status: 'pending',
        proposerUsername: 'bob',
        partnerUsername: 'alice',
        updatedAt: new Date(),
      })
    );
  });

  it('HAND-09-2: Proposer sets status=rejected on own proposal → DENY', async () => {
    const userA = testEnv.authenticatedContext(USER_A);
    await assertFails(
      updateDoc(doc(userA.firestore(), DOC_PATH), {
        status: 'rejected',
        updatedAt: new Date(),
      })
    );
  });

  it('HAND-09-3: Partner sets status=connected → ALLOW', async () => {
    const userB = testEnv.authenticatedContext(USER_B);
    await assertSucceeds(
      updateDoc(doc(userB.firestore(), DOC_PATH), {
        status: 'connected',
        updatedAt: new Date(),
      })
    );
  });

  it('HAND-09-4: Third party reads the doc → DENY', async () => {
    const userC = testEnv.authenticatedContext(USER_C);
    await assertFails(
      getDoc(doc(userC.firestore(), DOC_PATH))
    );
  });
});
