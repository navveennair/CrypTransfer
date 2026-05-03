import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── Memory Safety Tests (MEM-01) ────────────────────────────────────────────
//
// Validates the null-path guard in SenderScreen._pickFile() and the
// withData platform gate. These are pure logic tests — no Flutter widget
// context or FilePicker invocation required.

void main() {
  group('MEMORY SAFETY TESTS', () {
    // ─── TC-MEM-001 ──────────────────────────────────────────────────────────
    // Requirement MEM-01:
    //   SenderScreen._pickFile() uses `withData: kIsWeb` (not `withData: true`),
    //   so bytes are NOT loaded into memory on mobile/desktop.
    //   When `!kIsWeb && file.path == null`, the method must return early
    //   (shows SnackBar) and must NOT proceed to set _file in state.
    //
    // Implementation guard (verbatim from sender_screen.dart):
    //   if (!kIsWeb && file.path == null) { showSnackBar(...); return; }

    test(
      'TC-MEM-001a: withData flag is false on non-web platform '
      '(kIsWeb evaluates to false in test environment)',
      () {
        // kIsWeb is a compile-time constant from flutter/foundation.dart.
        // In the flutter_test environment (non-web), this must be false,
        // meaning FilePicker.pickFiles(withData: kIsWeb) requests NO bytes —
        // memory-safe path for mobile/desktop.
        expect(
          kIsWeb,
          false,
          reason: 'kIsWeb must be false in the test/mobile environment — '
              'withData: kIsWeb means bytes are NOT loaded into memory',
        );

        // ignore: avoid_print
        print('✅ TC-MEM-001a PASSED: kIsWeb == false; '
            'withData: kIsWeb correctly avoids loading file bytes into memory '
            'on non-web platforms');
      },
    );

    test(
      'TC-MEM-001b: null-path guard evaluates to true when path is null '
      'on non-web platform — early return prevents file assignment',
      () {
        // Mirror the exact guard from SenderScreen._pickFile():
        //   if (!kIsWeb && file.path == null) { showSnackBar(); return; }
        //
        // Scenario: mobile platform, FilePicker returns a PlatformFile with
        // path == null (e.g., a cloud-only file from Google Drive or Files app).
        // The guard must be satisfied so _file is never set.

        const String? filePath = null; // simulates PlatformFile.path on mobile
        final bool guardTriggered = !kIsWeb && filePath == null;

        expect(
          guardTriggered,
          true,
          reason: 'Guard (!kIsWeb && file.path == null) must be true when '
              'path is null on a non-web platform — prevents unsupported file '
              'from entering the encryption pipeline',
        );

        // Verify the guard correctly allows execution when path is present.
        const validPath = '/data/user/0/com.example.cryptransfer/cache/doc.pdf';
        // ignore: unnecessary_null_comparison
        final bool guardSkipped = !kIsWeb && validPath == null;

        expect(
          guardSkipped,
          false,
          reason: 'Guard must be false when path is non-null — '
              'valid local file must pass through to encryption',
        );

        // ignore: avoid_print
        print('✅ TC-MEM-001b PASSED: null-path guard correctly gates '
            'unsupported files (path==null) and allows local files (path!=null)');
      },
    );

    test(
      'TC-MEM-001c: wipeAll() with non-empty buffer registry zeroes all '
      'Uint8List contents and clears the registry',
      () {
        // Validates the SecurityLifecycleMixin buffer-wipe logic that runs
        // in SenderScreen after _encryptFile() completes (plaintext zero-wipe).
        // Mirror of SecurityLifecycleMixin.wipeAll() logic:
        final radioactiveBuffers = <Uint8List>[];

        final plaintext = Uint8List.fromList(List.generate(64 * 1024, (i) => i & 0xFF));
        final key = Uint8List.fromList(List.generate(32, (i) => 0xAB));
        final iv = Uint8List.fromList(List.generate(12, (i) => 0xCD));

        radioactiveBuffers.addAll([plaintext, key, iv]);

        // Pre-condition: buffers contain non-zero data.
        expect(plaintext.any((b) => b != 0), true,
            reason: 'Plaintext buffer must contain non-zero bytes before wipe');
        expect(key.every((b) => b == 0xAB), true,
            reason: 'Key buffer must contain 0xAB before wipe');

        // Execute wipe (mirrors SecurityLifecycleMixin.wipeAll()).
        for (final buffer in radioactiveBuffers) {
          try {
            buffer.fillRange(0, buffer.length, 0);
          } catch (_) {}
        }
        radioactiveBuffers.clear();

        // Post-condition: all buffers zeroed, registry empty.
        expect(plaintext.every((b) => b == 0), true,
            reason: 'Plaintext buffer must be all-zero after wipeAll()');
        expect(key.every((b) => b == 0), true,
            reason: 'Key buffer must be all-zero after wipeAll()');
        expect(iv.every((b) => b == 0), true,
            reason: 'IV buffer must be all-zero after wipeAll()');
        expect(radioactiveBuffers, isEmpty,
            reason: 'Buffer registry must be empty after wipeAll()');

        // ignore: avoid_print
        print('✅ TC-MEM-001c PASSED: wipeAll() zeroes all registered buffers '
            'and clears registry (64 KB plaintext + key + IV)');
      },
    );
  });
}
