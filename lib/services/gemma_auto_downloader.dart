import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_log.dart';
import 'gemma_model_manager.dart';

/// State of the on-device Gemma 4 download as seen by the rest of the app.
enum GemmaAutoState {
  /// Model file present + size sane.
  ready,

  /// Waiting for WiFi / unmetered network before kicking off a 2.4 GB pull.
  waitingForWifi,

  /// Downloading right now — [received] / [total] are progress bytes.
  downloading,

  /// Last download attempt failed; will retry on next WiFi connectivity event.
  failed,

  /// User explicitly opted out of auto-download in Settings.
  optedOut,

  /// First-launch bootstrap not yet finished.
  idle,
}

class GemmaAutoStatus {
  const GemmaAutoStatus({
    required this.state,
    this.received = 0,
    this.total = GemmaModelManager.approximateFullBytes,
    this.errorMessage,
  });

  final GemmaAutoState state;
  final int received;
  final int total;
  final String? errorMessage;

  double get fraction => total <= 0 ? 0.0 : (received / total).clamp(0.0, 1.0);

  GemmaAutoStatus copyWith({
    GemmaAutoState? state,
    int? received,
    int? total,
    Object? errorMessage = _sentinel,
  }) {
    return GemmaAutoStatus(
      state: state ?? this.state,
      received: received ?? this.received,
      total: total ?? this.total,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  static const _sentinel = Object();
}

/// Watches connectivity; whenever WiFi (or ethernet) appears and the Gemma 4
/// E4B model is missing, kicks off an anonymous resumable download in the
/// background. Cellular is intentionally skipped to avoid burning the user's
/// data plan on a 2.4 GB pull — they can override via [forceDownload].
///
/// Why a separate service from [GemmaModelDownloadScreen]:
///   * Screen is opt-in friction (used to demand an HF token before this fix).
///   * This service runs **without user interaction** as soon as the user
///     reaches the dashboard for the first time.
///   * Persists "in flight" state across app restarts so a partial download
///     resumes after a kill / crash.
class GemmaAutoDownloader extends StateNotifier<GemmaAutoStatus> {
  GemmaAutoDownloader()
    : super(const GemmaAutoStatus(state: GemmaAutoState.idle)) {
    _bootstrap();
  }

  final Connectivity _connectivity = Connectivity();
  CancelToken? _cancelToken;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _kicked = false;

  Future<void> _bootstrap() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(GemmaModelManager.prefAutoDownloadOptOut) ?? false) {
        state = state.copyWith(state: GemmaAutoState.optedOut);
        return;
      }
      if (await GemmaModelManager.isModelReady()) {
        state = state.copyWith(state: GemmaAutoState.ready);
        return;
      }
      state = state.copyWith(state: GemmaAutoState.waitingForWifi);
      final initial = await _connectivity.checkConnectivity();
      if (_isWifi(initial)) {
        unawaited(_kick());
      }
      _connSub = _connectivity.onConnectivityChanged.listen((conn) {
        if (_isWifi(conn) && state.state == GemmaAutoState.waitingForWifi) {
          unawaited(_kick());
        }
      });
    } on Object catch (e, st) {
      appLog.w('[GemmaAuto] bootstrap failed', error: e, stackTrace: st);
      state = state.copyWith(
        state: GemmaAutoState.failed,
        errorMessage: 'Bootstrap failed: $e',
      );
    }
  }

  bool _isWifi(List<ConnectivityResult> conn) {
    return conn.contains(ConnectivityResult.wifi) ||
        conn.contains(ConnectivityResult.ethernet);
  }

  /// Force a download regardless of network type (e.g. user tapped
  /// "Download now over cellular").
  Future<void> forceDownload({String? hfToken}) async {
    await _kick(forceCellular: true, hfToken: hfToken);
  }

  /// User opt-out — stops any in-flight download and prevents auto-retry.
  Future<void> optOut() async {
    _cancelToken?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(GemmaModelManager.prefAutoDownloadOptOut, true);
    state = state.copyWith(state: GemmaAutoState.optedOut);
  }

  /// Cancel an in-flight download but leave auto-retry on the next WiFi.
  Future<void> pause() async {
    _cancelToken?.cancel();
    if (state.state == GemmaAutoState.downloading) {
      state = state.copyWith(state: GemmaAutoState.waitingForWifi);
    }
  }

  Future<void> _kick({bool forceCellular = false, String? hfToken}) async {
    if (_kicked) return;
    _kicked = true;
    try {
      if (!forceCellular) {
        final conn = await _connectivity.checkConnectivity();
        if (!_isWifi(conn)) {
          state = state.copyWith(state: GemmaAutoState.waitingForWifi);
          return;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(GemmaModelManager.prefAutoDownloadInFlight, true);

      _cancelToken = CancelToken();
      state = state.copyWith(
        state: GemmaAutoState.downloading,
        errorMessage: null,
        received: await GemmaModelManager.downloadedSoFar(),
      );

      await GemmaModelManager.downloadModel(
        hfToken: hfToken,
        cancelToken: _cancelToken,
        onProgress: (rcv, tot) {
          state = state.copyWith(
            state: GemmaAutoState.downloading,
            received: rcv,
            total: tot,
          );
        },
      );

      if (_cancelToken?.isCancelled ?? false) {
        state = state.copyWith(state: GemmaAutoState.waitingForWifi);
        return;
      }
      if (await GemmaModelManager.isModelReady()) {
        state = state.copyWith(state: GemmaAutoState.ready);
      } else {
        state = state.copyWith(
          state: GemmaAutoState.failed,
          errorMessage: 'Downloaded file too small — will retry on next WiFi.',
        );
      }
    } on GemmaDownloadException catch (e) {
      state = state.copyWith(
        state: GemmaAutoState.failed,
        errorMessage: e.message,
      );
    } on Object catch (e, st) {
      appLog.w('[GemmaAuto] download failed', error: e, stackTrace: st);
      state = state.copyWith(
        state: GemmaAutoState.failed,
        errorMessage: 'Download failed: $e',
      );
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(GemmaModelManager.prefAutoDownloadInFlight, false);
      _kicked = false;
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

final gemmaAutoDownloaderProvider =
    StateNotifierProvider<GemmaAutoDownloader, GemmaAutoStatus>((ref) {
      return GemmaAutoDownloader();
    });
