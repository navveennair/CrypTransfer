import 'dart:io';
import 'dart:typed_data';

/// Memory-stable file I/O for the transfer pipeline.
///
/// Reading [PlatformFile.bytes] directly loads the entire file into a single
/// contiguous Dart heap allocation — on Android a 200 MB file competes with
/// AES-GCM crypto buffers and triggers aggressive GC.  [readFile] reads in
/// [kChunkSize] pages instead, keeping peak resident memory bounded.
///
/// Typical usage in the sender pipeline:
/// ```dart
/// final plaintext = await TransferService.resolve(
///   filePath: file.path,    // non-null on Android / iOS / desktop
///   fallbackBytes: file.bytes, // web fallback
/// );
/// final encrypted = await compute(_runAesGcm, [plaintext, key, iv]);
/// ```
class TransferService {
  const TransferService._();

  /// 64 KB — matches Flutter's default file I/O page size and Android's
  /// typical block alignment for large-file reads.
  static const int kChunkSize = 64 * 1024; // 65 536 bytes

  // ─── Read ─────────────────────────────────────────────────────────────────

  /// Reads the file at [filePath] into a single [Uint8List] using
  /// [kChunkSize]-byte reads.
  ///
  /// Allocates [file.length()] bytes once upfront (unavoidable — the
  /// downstream AES-GCM call needs contiguous input) but avoids the extra
  /// copy that [File.readAsBytes] makes internally.
  static Future<Uint8List> readFile(String filePath) async {
    final file = File(filePath);
    final length = await file.length();
    final result = Uint8List(length);

    int offset = 0;
    await for (final chunk in file.openRead()) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  /// Reads [filePath] in guaranteed [kChunkSize]-byte pages via
  /// [RandomAccessFile.read], calling [onProgress] with a 0.0–1.0 fraction
  /// after each chunk so callers can drive a real-time progress indicator.
  ///
  /// Unlike [readFile] (which uses [File.openRead] and may deliver all bytes
  /// in one event on Android), this method forces an explicit async yield
  /// between every 64 KB page — keeping the UI event loop free throughout.
  static Future<Uint8List> readFileWithProgress(
    String filePath,
    void Function(double) onProgress,
  ) async {
    final file = File(filePath);
    final length = await file.length();
    final result = Uint8List(length);
    final raf = await file.open(mode: FileMode.read);
    int offset = 0;
    try {
      while (offset < length) {
        final chunk = await raf.read(kChunkSize); // explicit 64 KB read
        if (chunk.isEmpty) break;
        result.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
        onProgress(offset / length);
      }
    } finally {
      await raf.close();
    }
    return result;
  }

  /// Streams the file at [filePath] in [kChunkSize]-byte chunks.
  ///
  /// Use when you need to inspect or hash raw bytes before encryption without
  /// assembling the full file into memory first.
  static Stream<Uint8List> readChunked(String filePath) async* {
    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      while (true) {
        final chunk = await raf.read(kChunkSize);
        if (chunk.isEmpty) break;
        yield Uint8List.fromList(chunk);
      }
    } finally {
      await raf.close();
    }
  }

  // ─── Resolve ──────────────────────────────────────────────────────────────

  /// Returns file bytes from [filePath] when available, otherwise [fallbackBytes].
  ///
  /// Pass both values from a [PlatformFile]; the method picks the
  /// memory-stable path automatically:
  /// - Mobile / desktop: path is available → chunked read
  /// - Web: path is null → [fallbackBytes] used directly
  ///
  /// Throws [StateError] if both are absent or empty.
  static Future<Uint8List> resolve({
    String? filePath,
    Uint8List? fallbackBytes,
  }) async {
    if (filePath != null && filePath.isNotEmpty) return readFile(filePath);
    if (fallbackBytes != null) return fallbackBytes;
    throw StateError('TransferService.resolve: no file path or bytes provided');
  }
}
