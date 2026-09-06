import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../logging/app_log.dart';

/// Manages the Gemma 4 E4B on-device model lifecycle:
///   • Check if model is present and valid
///   • Download from HuggingFace with resumable streaming progress
///   • Cancel in-progress download
///   • Delete to reclaim space
///
/// Model: gemma-4-E4B-it-Q4_K_M.gguf (~2.4 GB)
/// Source: https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF
///
/// **NO TOKEN REQUIRED.** Gemma 4 weights are Apache 2.0, but Google's
/// **official** repo `google/gemma-4-E4B-it-GGUF` still gates the resolve
/// endpoint behind a click-through terms screen + HF login (returns HTTP
/// 401 to anonymous fetches as of May 2026). The Unsloth, ggml-org, and
/// bartowski mirrors redistribute the **identical model bytes** under the
/// same Apache 2.0 license with no gating — verified 302→CDN on anonymous
/// `curl` from a clean IP. We point at Unsloth (most-downloaded GGUF
/// publisher, maintained by the same team behind unsloth.ai's training
/// stack) so the auto-installer just works without any HF account.
class GemmaModelManager {
  /// Filename — matches Unsloth's casing for the Q4_K_M quant.
  static const _modelFileName = 'gemma-4-E4B-it-Q4_K_M.gguf';

  /// Minimum sane file size: anything under 800 MB is definitely truncated.
  static const int expectedMinBytes = 800 * 1024 * 1024;

  /// Approximate full model size — used for progress UI when Content-Length is missing.
  static const int approximateFullBytes = 2_400_000_000;

  /// Primary download URL — Unsloth mirror (no auth required, identical bytes
  /// to Google's official repo, Apache 2.0).
  static const String modelDownloadUrl =
      'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/$_modelFileName';

  /// Fallback mirrors in case the primary is rate-limited or in maintenance.
  /// Tried in order; all hold the same Apache 2.0 weights.
  static const List<String> modelDownloadFallbackUrls = [
    'https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/$_modelFileName',
    'https://huggingface.co/bartowski/google_gemma-4-E4B-it-GGUF/resolve/main/google_gemma-4-E4B-it-Q4_K_M.gguf',
  ];

  /// Model card — opens in browser if the user wants to read the license /
  /// model card before downloading. Not required to proceed.
  static const String hfModelCardUrl =
      'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF';

  /// Optional HF token override page (only needed for very-high-volume IPs).
  static const String hfTokenUrl = 'https://huggingface.co/settings/tokens';

  /// SharedPreferences keys.
  static const String prefAutoDownloadOptOut = 'gemma_auto_download_opt_out_v1';
  static const String prefAutoDownloadInFlight =
      'gemma_auto_download_in_flight_v1';

  // ── Path ──────────────────────────────────────────────────────────────────

  /// Full path to the model file (may or may not exist).
  static Future<String> localModelPath() async {
    if (kIsWeb) return '';
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_modelFileName';
  }

  // ── Status queries ────────────────────────────────────────────────────────

  /// Returns true if model file exists and passes size sanity check.
  static Future<bool> isModelReady() async {
    if (kIsWeb) return false;
    try {
      final file = File(await localModelPath());
      if (!file.existsSync()) return false;
      return file.lengthSync() >= expectedMinBytes;
    } on Object catch (_) {
      return false;
    }
  }

  /// Returns bytes of local model file (0 if not present).
  static Future<int> localModelBytes() async {
    try {
      final file = File(await localModelPath());
      return file.existsSync() ? file.lengthSync() : 0;
    } on Object catch (_) {
      return 0;
    }
  }

  /// Returns bytes of in-progress download temp file (for resume display).
  static Future<int> downloadedSoFar() async {
    try {
      final tmp = File('${await localModelPath()}.download');
      return tmp.existsSync() ? tmp.lengthSync() : 0;
    } on Object catch (_) {
      return 0;
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────

  /// Downloads the Gemma 4 E4B model from HuggingFace.
  ///
  /// [hfToken] — **optional** HuggingFace read token. Gemma 4 is Apache 2.0
  /// and ungated, so the anonymous request works for nearly every user; the
  /// token is only useful when sharing an IP that hit HF's anon rate limit.
  /// [onProgress] — called with (bytesReceived, totalBytes) — totalBytes may
  /// be [approximateFullBytes] if the server omits Content-Length.
  /// [cancelToken] — call [CancelToken.cancel] to abort; partial file is kept
  /// so the next call resumes from where it left off.
  ///
  /// Throws [GemmaDownloadException] on auth failure or unexpected HTTP error.
  static Future<void> downloadModel({
    String? hfToken,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final candidateUrls = <String>[
      modelDownloadUrl,
      ...modelDownloadFallbackUrls,
    ];
    GemmaDownloadException? lastErr;
    for (final url in candidateUrls) {
      if (cancelToken?.isCancelled ?? false) return;
      try {
        await _downloadFromUrl(
          url: url,
          hfToken: hfToken,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        return; // success
      } on GemmaDownloadException catch (e) {
        lastErr = e;
        // Only fail-over on auth-ish / rate-limit responses; bubble unknown
        // errors so the caller can show a clean message.
        if (e.statusCode != 401 &&
            e.statusCode != 403 &&
            e.statusCode != 404 &&
            e.statusCode != 429) {
          rethrow;
        }
        appLog.w(
          '[GemmaModel] $url failed (${e.statusCode}); trying next mirror',
        );
      }
    }
    throw lastErr ??
        const GemmaDownloadException('All Gemma 4 mirrors are unreachable.');
  }

  static Future<void> _downloadFromUrl({
    required String url,
    String? hfToken,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final path = await localModelPath();
    final tmpPath = '$path.download';
    final tmpFile = File(tmpPath);

    // Resume: check how much is already on disk.
    int alreadyHave = 0;
    if (tmpFile.existsSync()) {
      alreadyHave = tmpFile.lengthSync();
      appLog.i(
        '[GemmaModel] Resuming download from ${(alreadyHave / 1e6).round()} MB ($url)',
      );
    }

    final headers = <String, String>{
      'User-Agent': 'RoadSOS/1.0 (Gemma 4 Good Hackathon)',
      if (alreadyHave > 0) 'Range': 'bytes=$alreadyHave-',
      if (hfToken != null && hfToken.trim().isNotEmpty)
        'Authorization': 'Bearer ${hfToken.trim()}',
    };

    final client = http.Client();

    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);
      final response = await client.send(request);

      final ok = response.statusCode == 200 || response.statusCode == 206;
      if (!ok) {
        final body = await response.stream.bytesToString();
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw GemmaDownloadException(
            'Hugging Face mirror $url refused the request (HTTP '
            '${response.statusCode}). Trying the next mirror — if all fail, '
            'paste an HF read token in Settings → Advanced as a workaround.',
            statusCode: response.statusCode,
          );
        }
        if (response.statusCode == 429) {
          throw GemmaDownloadException(
            'Hugging Face rate-limited mirror $url (HTTP 429). Will retry on '
            'the next Wi-Fi event, or paste an HF read token in Settings → '
            'Advanced to override.',
            statusCode: response.statusCode,
          );
        }
        if (response.statusCode == 404) {
          throw GemmaDownloadException(
            'Mirror $url is missing the expected GGUF file (HTTP 404). Trying '
            'the next mirror.',
            statusCode: 404,
          );
        }
        throw GemmaDownloadException(
          'Server returned HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}',
          statusCode: response.statusCode,
        );
      }

      // Content-Length is relative to range start; add already-downloaded bytes.
      final contentLength = response.contentLength ?? -1;
      final totalBytes = contentLength > 0
          ? alreadyHave + contentLength
          : approximateFullBytes; // fallback for progress UI

      final sink = tmpFile.openWrite(
        mode: alreadyHave > 0 ? FileMode.append : FileMode.write,
      );
      int received = alreadyHave;

      try {
        await for (final chunk in response.stream) {
          if (cancelToken?.isCancelled ?? false) {
            appLog.i(
              '[GemmaModel] Download cancelled — partial file kept for resume',
            );
            await sink.flush();
            await sink.close();
            return;
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, totalBytes);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (cancelToken?.isCancelled ?? false) return;

      // Sanity check before promoting.
      final finalSize = tmpFile.lengthSync();
      if (finalSize < expectedMinBytes) {
        throw GemmaDownloadException(
          'Downloaded file too small (${(finalSize / 1e6).round()} MB — expected ≥ '
          '${(expectedMinBytes / 1e6).round()} MB). The download may be incomplete.',
        );
      }

      // Atomic rename: .download → final path.
      await tmpFile.rename(path);
      appLog.i(
        '[GemmaModel] ✓ Download complete — ${(finalSize / 1e6).round()} MB at $path',
      );
    } finally {
      client.close();
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Deletes model and any partial download to reclaim storage.
  static Future<void> deleteModel() async {
    final path = await localModelPath();
    for (final p in [path, '$path.download']) {
      final f = File(p);
      if (f.existsSync()) {
        await f.delete();
        appLog.i('[GemmaModel] Deleted $p');
      }
    }
  }
}

/// Pass to [GemmaModelManager.downloadModel] to cancel an in-progress download.
/// The partial file is preserved for resuming on the next attempt.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Thrown when [GemmaModelManager.downloadModel] encounters a fatal error.
class GemmaDownloadException implements Exception {
  final String message;
  final int? statusCode;

  const GemmaDownloadException(this.message, {this.statusCode});

  @override
  String toString() => 'GemmaDownloadException: $message';
}
