import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cryptransfer/core/utils/kill_switch_outbox.dart';

// Mirrors the private KillSwitchOutbox._kKey value — there is no public
// accessor, and adding one solely for tests would leak a test-only seam
// into production API surface.
const _kKey = 'pending_kill_switch_v1';

void main() {
  group('KILL SWITCH OUTBOX TESTS', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // ─── KSO-01 ──────────────────────────────────────────────────────────────

    test(
      'KSO-01: persist() writes uid, selectedSenderUid, and persistedAt',
      () async {
        await KillSwitchOutbox.persist('receiver_uid_1', 'sender_uid_1');

        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kKey);
        expect(raw, isNotNull,
            reason: 'persist() must write a record before any Firestore I/O');

        final data = jsonDecode(raw!) as Map<String, dynamic>;
        expect(data['uid'], 'receiver_uid_1');
        expect(data['selectedSenderUid'], 'sender_uid_1');
        expect(data['persistedAt'], isA<int>(),
            reason: 'persistedAt must be a millisecondsSinceEpoch int');

        // ignore: avoid_print
        print('✅ KSO-01 PASSED: persist() writes full record');
      },
    );

    // ─── KSO-02 ──────────────────────────────────────────────────────────────

    test(
      'KSO-02: persist() with null selectedSenderUid stores empty string',
      () async {
        await KillSwitchOutbox.persist('receiver_uid_1', null);

        final prefs = await SharedPreferences.getInstance();
        final data =
            jsonDecode(prefs.getString(_kKey)!) as Map<String, dynamic>;
        expect(data['selectedSenderUid'], '',
            reason: 'null selectedSenderUid must persist as empty string, '
                'not the literal null (resumeIfPending only reads uid, but '
                'a null value would still break naive JSON consumers)');

        // ignore: avoid_print
        print('✅ KSO-02 PASSED: null selectedSenderUid stored as empty string');
      },
    );

    // ─── KSO-03 ──────────────────────────────────────────────────────────────

    test(
      'KSO-03: clear() removes the pending record',
      () async {
        await KillSwitchOutbox.persist('receiver_uid_1', null);
        var prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_kKey), isNotNull);

        await KillSwitchOutbox.clear();
        prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_kKey), isNull,
            reason: 'clear() must fully remove the record, not just blank it');

        // ignore: avoid_print
        print('✅ KSO-03 PASSED: clear() removes the record');
      },
    );

    // ─── KSO-04 ──────────────────────────────────────────────────────────────

    test(
      'KSO-04: resumeIfPending() is a no-op when no record exists',
      () async {
        // No persist() call — SharedPreferences starts empty (setUp above).
        await KillSwitchOutbox.resumeIfPending(currentUid: 'receiver_uid_1');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_kKey), isNull,
            reason: 'resumeIfPending() must not write anything when there '
                'was nothing to resume');

        // ignore: avoid_print
        print('✅ KSO-04 PASSED: no-op with no pending record');
      },
    );

    // ─── KSO-05 ──────────────────────────────────────────────────────────────

    test(
      'KSO-05: resumeIfPending() discards a corrupt record',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kKey, 'not-valid-json{{{');

        await KillSwitchOutbox.resumeIfPending(currentUid: 'receiver_uid_1');

        expect(prefs.getString(_kKey), isNull,
            reason: 'corrupt JSON must be discarded via clear(), not left '
                'behind to fail again on every future launch');

        // ignore: avoid_print
        print('✅ KSO-05 PASSED: corrupt record discarded');
      },
    );

    // ─── KSO-06 ──────────────────────────────────────────────────────────────

    test(
      'KSO-06: resumeIfPending() discards a record left by a different user '
      'without attempting cleanup',
      () async {
        // Record belongs to a previous account (e.g. after account switch).
        await KillSwitchOutbox.persist('previous_account_uid', null);

        await KillSwitchOutbox.resumeIfPending(currentUid: 'current_account_uid');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_kKey), isNull,
            reason: 'a record from a different uid must be discarded — '
                'attempting closeReceiverSession(previous_account_uid) while '
                'signed in as a different user would be rejected by '
                'Firestore rules anyway, per the class-level doc comment');

        // ignore: avoid_print
        print('✅ KSO-06 PASSED: different-user record discarded, no resume attempted');
      },
    );

    // ─── KSO-07 ──────────────────────────────────────────────────────────────

    test(
      'KSO-07: resumeIfPending() with a matching uid leaves the record intact '
      'when the resume attempt fails (e.g. still offline)',
      () async {
        await KillSwitchOutbox.persist('receiver_uid_1', null);

        // EncryptionService.closeReceiverSession() requires a live Firebase
        // app, which this plain unit-test environment does not provide — it
        // throws, and resumeIfPending() must catch that internally (per its
        // own "Still offline — leave the record for the next launch" comment)
        // rather than letting the exception propagate and crash app startup.
        await expectLater(
          KillSwitchOutbox.resumeIfPending(currentUid: 'receiver_uid_1'),
          completes,
          reason: 'a failed resume attempt must not throw out of resumeIfPending()',
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_kKey), isNotNull,
            reason: 'the record must survive a failed resume attempt so the '
                'next launch can retry — only a successful '
                'closeReceiverSession() (which calls clear() itself) should '
                'remove it');

        // ignore: avoid_print
        print('✅ KSO-07 PASSED: record preserved across a failed resume attempt');
      },
    );
  });
}
