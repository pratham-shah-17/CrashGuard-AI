// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:torch_light/torch_light.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logging/app_log.dart';

/// Hardware SOS Beacon — no AI involved.
///
/// Pure platform driver. When the orchestrator transitions to SOSPhase.active
/// it asks this service to:
///   1. Flashlight: pulse international Morse SOS (... --- ...)
///   2. Audio: play a synthesised high-frequency locator tone at max volume.
///
/// Earlier doc comment misleadingly described this as "the Gemma 4 agent
/// takes over" — there is no ML on this code path. Beacon = strobe + siren.
class EmergencyBeaconService {
  EmergencyBeaconService._();
  static final EmergencyBeaconService instance = EmergencyBeaconService._();

  bool _isActive = false;
  Timer? _flashTimer;
  final AudioPlayer _player = AudioPlayer();

  bool get isActive => _isActive;

  /// Starts the hardware SOS beacon.
  /// This should be called by the EmergencyOrchestrator when SOSPhase becomes active.
  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;
    appLog.i(
      '🚨 [BEACON] Hardware takeover initiated: SOS strobe + Siren active.',
    );

    _startFlashlightStrobe();
    _startSiren();
  }

  /// Stops all hardware SOS signals.
  Future<void> stop() async {
    if (!_isActive) return;
    _isActive = false;
    _flashTimer?.cancel();
    _flashTimer = null;

    try {
      await TorchLight.disableTorch();
    } on Object catch (_) {}

    try {
      await _player.stop();
    } on Object catch (_) {}

    appLog.i('✅ [BEACON] Hardware SOS signals disabled.');
  }

  // ── Flashlight Morse Code Logic ──────────────────────────────────────────

  void _startFlashlightStrobe() {
    _flashTimer?.cancel();

    // SOS Morse Pattern: ... --- ...
    // Dot = 200ms, Dash = 600ms, Gap = 200ms
    final pattern = [
      200, 200, 200, 200, 200, 400, // S (...)
      600, 200, 600, 200, 600, 400, // O (---)
      200, 200, 200, 200, 200, 2000, // S (...) + 2s rest
    ];

    int index = 0;

    void nextStep() {
      if (!_isActive) return;

      final duration = pattern[index];
      final isLightOn = index % 2 == 0;

      if (isLightOn) {
        _enableTorch();
      } else {
        _disableTorch();
      }

      index = (index + 1) % pattern.length;
      _flashTimer = Timer(Duration(milliseconds: duration), nextStep);
    }

    nextStep();
  }

  Future<void> _enableTorch() async {
    if (kIsWeb) return;
    try {
      await TorchLight.enableTorch();
    } on Object catch (e) {
      appLog.w('[BEACON] Failed to enable torch', error: e);
    }
  }

  Future<void> _disableTorch() async {
    if (kIsWeb) return;
    try {
      await TorchLight.disableTorch();
    } on Object catch (e) {
      appLog.w('[BEACON] Failed to disable torch', error: e);
    }
  }

  // ── Siren Locator Logic ──────────────────────────────────────────────────

  Future<void> _startSiren() async {
    try {
      final source = _SirenAudioSource();
      await _player.setAudioSource(source);
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(1.0);
      await _player.play();
    } on Object catch (e) {
      appLog.d('[BEACON] Siren failed to play: $e');
    }
  }

  void dispose() {
    stop();
    _player.dispose();
  }
}

final emergencyBeaconServiceProvider = Provider(
  (ref) => EmergencyBeaconService.instance,
);

/// Generates a two-tone siren WAV (880Hz / 660Hz alternating) entirely in memory.
/// No external asset file required.
class _SirenAudioSource extends StreamAudioSource {
  static const int _sampleRate = 44100;
  static const int _channels = 1;
  static const int _bitsPerSample = 16;
  static const double _durationSec = 2.0;
  static const double _freqHigh = 880.0;
  static const double _freqLow = 660.0;

  late final Uint8List _bytes;

  _SirenAudioSource() {
    _bytes = _generateSirenWav();
  }

  Uint8List _generateSirenWav() {
    final numSamples = (_sampleRate * _durationSec).toInt();
    final dataSize = numSamples * _channels * (_bitsPerSample ~/ 8);
    final fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);
    var offset = 0;

    void writeString(String s) {
      for (var i = 0; i < s.length; i++) {
        buffer.setUint8(offset++, s.codeUnitAt(i));
      }
    }

    // WAV header
    writeString('RIFF');
    buffer.setUint32(offset, fileSize - 8, Endian.little);
    offset += 4;
    writeString('WAVE');
    writeString('fmt ');
    buffer.setUint32(offset, 16, Endian.little);
    offset += 4;
    buffer.setUint16(offset, 1, Endian.little);
    offset += 2; // PCM
    buffer.setUint16(offset, _channels, Endian.little);
    offset += 2;
    buffer.setUint32(offset, _sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(
      offset,
      _sampleRate * _channels * (_bitsPerSample ~/ 8),
      Endian.little,
    );
    offset += 4;
    buffer.setUint16(offset, _channels * (_bitsPerSample ~/ 8), Endian.little);
    offset += 2;
    buffer.setUint16(offset, _bitsPerSample, Endian.little);
    offset += 2;
    writeString('data');
    buffer.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    // Alternating tone: first half high, second half low
    final halfSamples = numSamples ~/ 2;
    for (var i = 0; i < numSamples; i++) {
      final freq = i < halfSamples ? _freqHigh : _freqLow;
      final sample = (sin(2 * pi * freq * i / _sampleRate) * 32000).toInt();
      buffer.setInt16(offset, sample, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}
