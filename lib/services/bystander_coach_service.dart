import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../logging/app_log.dart';
import '../ui/vehicle_rescue_data.dart';
import 'emergency_orchestrator.dart' show voiceAssistantServiceProvider;
import 'first_aid_repository.dart';
import 'gemma_local_service.dart';

/// State of the Bystander Coach session.
enum BystanderCoachPhase { idle, listening, thinking, speaking, error }

class BystanderCoachTurn {
  BystanderCoachTurn({required this.role, required this.text, DateTime? at})
    : at = at ?? DateTime.now();

  /// 'bystander' for the helper at the scene, 'coach' for the AI agent.
  final String role;
  final String text;
  final DateTime at;
}

class BystanderCoachState {
  const BystanderCoachState({
    this.phase = BystanderCoachPhase.idle,
    this.turns = const <BystanderCoachTurn>[],
    this.partial = '',
    this.errorMessage,
    this.languageCode = 'en',
  });

  final BystanderCoachPhase phase;
  final List<BystanderCoachTurn> turns;
  final String partial;
  final String? errorMessage;
  final String languageCode;

  BystanderCoachState copyWith({
    BystanderCoachPhase? phase,
    List<BystanderCoachTurn>? turns,
    String? partial,
    Object? errorMessage = _sentinel,
    String? languageCode,
  }) {
    return BystanderCoachState(
      phase: phase ?? this.phase,
      turns: turns ?? this.turns,
      partial: partial ?? this.partial,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  static const _sentinel = Object();
}

/// On-device Gemma 4 E4B "Bystander Coach" — talks a helper through CPR,
/// bleeding control, recovery position, etc. while EMS is en route.
///
/// Flow:
///   1. UI taps "Start listening" → STT captures bystander's situation.
///   2. Situation keywords are accumulated across turns to build a targeted
///      grounding query for the [FirstAidRepository] RAG corpus.
///   3. Full conversation history (up to [_maxHistoryTurns]) is injected into
///      the Gemma 4 E4B prompt so the model understands what has already been
///      said and gives the NEXT step — not the first step again.
///   4. Gemma 4 E4B streams a short, calm, step-by-step reply in the user's
///      locale (Hindi/Eng/Tamil/etc).
///   5. TTS speaks the reply; UI shows transcript.
///   6. Loop — bystander can interrupt and ask follow-up.
///
/// Fail-open behaviour: when Gemma is not downloaded yet, we serve a
/// deterministic templated reply that quotes the matched corpus row directly,
/// taking the current transcript into account. Model-missing is never fatal.
class BystanderCoachService extends StateNotifier<BystanderCoachState> {
  BystanderCoachService(this._ref) : super(const BystanderCoachState());

  final Ref _ref;
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;

  /// Accumulated situation keywords from all user turns in this session.
  /// Used to enrich the grounding query so the RAG retrieval stays on-topic.
  final Set<String> _situationKeywords = {};

  /// Maximum number of prior turns to include in each Gemma prompt.
  /// Keeps the prompt within the E4B token budget (~2 048 tokens).
  static const int _maxHistoryTurns = 6;

  // ─── System prompt ────────────────────────────────────────────────────────

  static const String _systemPrompt = '''
You are RoadSOS Bystander Coach — a calm, practical AI assistant helping someone at a road accident scene in India.

You can answer ANY question about the current emergency, including:
- Medical first aid (CPR, bleeding, fractures, burns, shock)
- Vehicle rescue (how to extract a trapped person, EV hazards, fuel fires)
- Finding help (nearest hospital, ambulance, towing, police)
- Emergency numbers (108 ambulance, 112 ERSS, 101 fire, 100 police)
- Legal questions (Good Samaritan law, what to do after an accident)
- Insurance/documentation (FIR, accident report, insurance claim steps)
- Road safety (scene safety, warning traffic, hazards)
- Reassurance and what to do while waiting for help

Response rules:
- Give ONE clear, actionable step per reply, under 35 words.
- Read the full conversation history — give the NEXT relevant action, never repeat.
- Plain simple words. No jargon. Anyone can understand.
- For life-threatening situations (not breathing, heavy bleeding, unconscious): first step = "Call 108 now."
- For hospital/towing questions: give the number to call AND what to say.
- End EVERY reply with: "Tell me what you see now." (or locale equivalent)
- Use GROUNDING TEXT facts. Do not invent information.
- Never give medication doses.
''';

  // ─── Session lifecycle ────────────────────────────────────────────────────

  Future<void> startSession({String languageCode = 'en'}) async {
    _situationKeywords.clear();
    state = const BystanderCoachState().copyWith(
      phase: BystanderCoachPhase.idle,
      languageCode: languageCode,
      turns: <BystanderCoachTurn>[],
      partial: '',
      errorMessage: null,
    );
    final greeting = _greetingFor(languageCode);
    _appendTurn('coach', greeting);
    await _ref.read(voiceAssistantServiceProvider).speak(greeting);
  }

  Future<void> endSession() async {
    await _stopListeningSafely();
    await _ref.read(voiceAssistantServiceProvider).stopSpeaking();
    _situationKeywords.clear();
    state = const BystanderCoachState();
  }

  // ─── STT capture ──────────────────────────────────────────────────────────

  /// Start a single STT capture turn.
  Future<void> startListening() async {
    if (state.phase == BystanderCoachPhase.listening) return;
    if (!_sttReady) {
      try {
        _sttReady = await _stt.initialize(
          onError: (e) => appLog.w('[BystanderCoach] STT error: ${e.errorMsg}'),
        );
      } on Object catch (e, st) {
        appLog.w('[BystanderCoach] STT init failed', error: e, stackTrace: st);
        _sttReady = false;
      }
    }
    if (!_sttReady) {
      state = state.copyWith(
        phase: BystanderCoachPhase.error,
        errorMessage:
            'Microphone unavailable — tap the typed input instead and describe the scene.',
      );
      return;
    }

    state = state.copyWith(
      phase: BystanderCoachPhase.listening,
      partial: '',
      errorMessage: null,
    );

    var heard = '';
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
      ),
      onResult: (r) {
        heard = r.recognizedWords;
        if (mounted) {
          state = state.copyWith(partial: heard);
        }
      },
    );

    await Future<void>.delayed(const Duration(seconds: 12));
    await _stopListeningSafely();

    final transcript = heard.trim();
    state = state.copyWith(partial: '');
    if (transcript.isEmpty) {
      state = state.copyWith(
        phase: BystanderCoachPhase.idle,
        errorMessage: 'Did not catch that — try again or type the description.',
      );
      return;
    }
    await submitTurn(transcript);
  }

  Future<void> _stopListeningSafely() async {
    try {
      if (_stt.isListening) await _stt.stop();
    } on Object catch (_) {}
  }

  // ─── Core response loop ───────────────────────────────────────────────────

  /// Accept typed or STT input as a turn.
  Future<void> submitTurn(String transcript) async {
    // Extract keywords from this turn and accumulate across session.
    _extractKeywords(transcript);

    _appendTurn('bystander', transcript);
    state = state.copyWith(phase: BystanderCoachPhase.thinking);

    // Build an enriched grounding query from accumulated situation context.
    final groundingQuery = _buildGroundingQuery(transcript);
    final grounding = await _retrieveGrounding(groundingQuery);

    final reply = await _generateReply(
      latestTranscript: transcript,
      grounding: grounding,
      languageCode: state.languageCode,
    );

    _appendTurn('coach', reply);
    state = state.copyWith(phase: BystanderCoachPhase.speaking);

    try {
      await _ref.read(voiceAssistantServiceProvider).speak(reply);
    } on Object catch (e, st) {
      appLog.d('[BystanderCoach] TTS speak failed', stackTrace: st);
    }
    state = state.copyWith(phase: BystanderCoachPhase.idle);
  }

  // ─── Keyword accumulation ─────────────────────────────────────────────────────

  /// Accumulate situation-relevant keywords from every bystander message.
  void _extractKeywords(String text) {
    final lower = text.toLowerCase();
    const allKeywords = <String>[
      // Medical
      'bleeding', 'blood', 'unconscious', 'breathing', 'pulse', 'cpr',
      'fracture', 'broken', 'burn', 'head injury', 'spine', 'neck',
      'chest', 'heart', 'choking', 'trapped', 'fire', 'smoke',
      'not moving', 'not breathing', 'not responding', 'pain',
      'swelling', 'wound', 'cut', 'scratch', 'bruise', 'dislocation',
      'sprain', 'seizure', 'stroke', 'diabetic', 'allergic', 'shock',
      'pregnant', 'elderly', 'child',
      // Vehicle
      'motorbike', 'bike', 'scooter', 'truck', 'lorry', 'bus', 'car',
      'auto', 'rickshaw', 'electric', 'ev', 'petrol', 'diesel', 'cng',
      'helmet', 'airbag', 'battery', 'fuel', 'orange cable',
      'tyre', 'tire', 'engine', 'overheating', 'breakdown',
      // Scene
      'pedestrian', 'cyclist', 'road', 'highway', 'collision', 'hit',
      'accident', 'crash', 'overturn', 'rolled', 'skid',
      // Help-seeking
      'hospital', 'ambulance', 'doctor', 'police', 'towing', 'tow',
      'mechanic', 'insurance', 'fir', 'report', 'helpline', 'number',
      // Legal
      'good samaritan', 'legal', 'law', 'arrested', 'fined', 'liability',
    ];
    for (final kw in allKeywords) {
      if (lower.contains(kw)) _situationKeywords.add(kw);
    }
  }

  /// Intent categories for routing grounding sources.
  _CoachIntent _detectIntent(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('hospital') ||
        lower.contains('ambulance') ||
        lower.contains('doctor') ||
        lower.contains('where') && lower.contains('help')) {
      return _CoachIntent.findHelp;
    }
    if (lower.contains('tow') ||
        lower.contains('mechanic') ||
        lower.contains('breakdown') ||
        lower.contains('tyre') ||
        lower.contains('tire') ||
        lower.contains('puncture') ||
        lower.contains('engine') ||
        lower.contains('repair')) {
      return _CoachIntent.vehicleAssistance;
    }
    if (lower.contains('extract') ||
        lower.contains('stuck') ||
        lower.contains('trapped') ||
        lower.contains('helmet') ||
        lower.contains('orange cable') ||
        lower.contains('electric') ||
        lower.contains('ev') ||
        lower.contains('bike') ||
        lower.contains('scooter') ||
        lower.contains('truck') ||
        lower.contains('bus') ||
        lower.contains('auto')) {
      return _CoachIntent.vehicleRescue;
    }
    if (lower.contains('legal') ||
        lower.contains('law') ||
        lower.contains('samaritan') ||
        lower.contains('arrested') ||
        lower.contains('fir') ||
        lower.contains('insurance') ||
        lower.contains('report') ||
        lower.contains('liability')) {
      return _CoachIntent.legalOrInsurance;
    }
    return _CoachIntent.medicalFirstAid;
  }

  /// Build a grounding query combining the transcript with accumulated keywords.
  String _buildGroundingQuery(String latestTranscript) {
    final buf = StringBuffer(latestTranscript.trim());
    if (_situationKeywords.isNotEmpty) {
      buf.write(' ');
      buf.write(_situationKeywords.take(8).join(' '));
    }
    return buf.toString();
  }

  // ─── Multi-source RAG grounding ───────────────────────────────────────────────

  Future<String> _retrieveGrounding(String query) async {
    final intent = _detectIntent(query);
    final parts = <String>[_emergencyNumbersText()];

    switch (intent) {
      case _CoachIntent.vehicleRescue:
        parts.add(_vehicleRescueGrounding(query));
        parts.add(await _firstAidGrounding(query));
      case _CoachIntent.vehicleAssistance:
        parts.add(_vehicleAssistanceText());
      case _CoachIntent.findHelp:
        parts.add(_findHelpText());
      case _CoachIntent.legalOrInsurance:
        parts.add(_legalText());
      case _CoachIntent.medicalFirstAid:
        parts.add(await _firstAidGrounding(query));
    }

    final combined = parts
        .where((p) => p.trim().isNotEmpty)
        .join('\n\n---\n\n');
    return combined.length > 1600 ? combined.substring(0, 1600) : combined;
  }

  Future<String> _firstAidGrounding(String query) async {
    try {
      return await FirstAidRepository.instance.lookup(query);
    } on Object catch (e, st) {
      appLog.d('[BystanderCoach] first-aid lookup failed', stackTrace: st);
      return '';
    }
  }

  String _vehicleRescueGrounding(String query) {
    final lower = query.toLowerCase();
    var vehicleKey = 'car';
    if (lower.contains('bike') ||
        lower.contains('scooter') ||
        lower.contains('motorbike')) {
      vehicleKey = 'bike';
    } else if (lower.contains('truck') || lower.contains('lorry')) {
      vehicleKey = 'truck';
    } else if (lower.contains('bus')) {
      vehicleKey = 'bus';
    } else if (lower.contains('auto') || lower.contains('rickshaw')) {
      vehicleKey = 'auto';
    } else if (lower.contains('electric') || lower.contains('ev')) {
      vehicleKey = 'ev_car';
    } else {
      for (final kw in _situationKeywords) {
        if (kw == 'bike' || kw == 'scooter' || kw == 'motorbike') {
          vehicleKey = 'bike';
          break;
        }
        if (kw == 'truck' || kw == 'lorry') {
          vehicleKey = 'truck';
          break;
        }
        if (kw == 'bus') {
          vehicleKey = 'bus';
          break;
        }
        if (kw == 'auto' || kw == 'rickshaw') {
          vehicleKey = 'auto';
          break;
        }
        if (kw == 'electric' || kw == 'ev') {
          vehicleKey = 'ev_car';
          break;
        }
      }
    }
    final data = kVehicleRescueDatabase[vehicleKey];
    if (data == null) return '';
    final buf = StringBuffer()
      ..writeln('VEHICLE RESCUE — ${data.vehicleType} (${data.fuelType}):')
      ..writeln('DANGERS: ${data.dangers.join(' | ')}')
      ..writeln('STEPS:');
    for (final s in data.extractionSteps) {
      buf.writeln('${s.stepNumber}. ${s.title}: ${s.detail}');
    }
    buf.writeln('FIRST AID TIPS: ${data.firstAidTips.join(' | ')}');
    return buf.toString();
  }

  static String _emergencyNumbersText() =>
      'INDIA EMERGENCY NUMBERS:\n'
      '108 — Ambulance (call first for medical emergencies)\n'
      '112 — National ERSS (all emergencies)\n'
      '101 — Fire brigade\n'
      '100 — Police\n'
      '1033 — NHAI highway helpline (highway breakdowns)\n'
      '14567 — Motor Accident Claims helpline';

  static String _findHelpText() =>
      'FINDING NEARBY HELP:\n'
      '1. Call 108 — they dispatch ambulance AND locate nearest hospital.\n'
      '2. Call 112 ERSS — coordinates police, fire, and medical.\n'
      '3. Ask a bystander to search Google Maps for "hospital near me".\n'
      '4. On national highways call 1033 (NHAI) — they know nearest facilities.\n'
      '5. Any government hospital MUST treat accident victims free of cost.';

  static String _vehicleAssistanceText() =>
      'VEHICLE BREAKDOWN / TOWING:\n'
      '1. Call 1033 (NHAI helpline) for highway breakdowns — free towing on many NHs.\n'
      '2. Call your car insurance company — most have 24x7 roadside assistance.\n'
      '3. Common helplines: Maruti 1800-102-1800 | Hyundai 1800-11-4645 | Tata 1800-209-7979.\n'
      '4. Turn on hazard lights and place objects 50m behind to warn traffic.\n'
      '5. For flat tyre: change only if road is safe and you know how.';

  static String _legalText() =>
      'GOOD SAMARITAN LAW (India — Motor Vehicles Act 2019):\n'
      '- You CANNOT be arrested or harassed for helping an accident victim.\n'
      '- You are NOT liable if the victim dies despite your help.\n'
      '- You may give your name voluntarily but are NOT required to.\n'
      '- Hospitals CANNOT demand payment before treating an accident victim.\n\n'
      'ACCIDENT DOCUMENTATION:\n'
      '1. Note registration numbers of vehicles involved.\n'
      '2. Photograph the scene if safe.\n'
      '3. File an FIR at nearest police station or call 100.\n'
      '4. Notify your insurer within 24-48 hours. Keep all bills.';

  // ─── Prompt construction ──────────────────────────────────────────────────

  /// Build a Gemma 4–compatible prompt that includes:
  ///   • System instructions
  ///   • Grounding text from the first-aid corpus
  ///   • Full conversation history (last [_maxHistoryTurns] turns)
  ///   • The latest bystander message as the current query
  String _buildPrompt({
    required String latestTranscript,
    required String grounding,
    required String languageCode,
  }) {
    final localisedDirective = _localeDirective(languageCode);
    final history = state.turns;

    // Collect only turns that are *before* the latest (already appended) bystander turn.
    // The last turn in state.turns is the bystander's latest message.
    // We include up to [_maxHistoryTurns] prior turns for context.
    final priorTurns = history.length > 1
        ? history.sublist(0, history.length - 1)
        : <BystanderCoachTurn>[];
    final historySlice = priorTurns.length > _maxHistoryTurns
        ? priorTurns.sublist(priorTurns.length - _maxHistoryTurns)
        : priorTurns;

    final buf = StringBuffer();
    buf.writeln(_systemPrompt);
    buf.writeln(localisedDirective);
    buf.writeln();
    buf.writeln('GROUNDING TEXT (from RoadSOS first-aid corpus — use this):');
    buf.writeln('"""');
    buf.writeln(grounding.trim());
    buf.writeln('"""');
    buf.writeln();

    if (historySlice.isNotEmpty) {
      buf.writeln('CONVERSATION SO FAR (most recent last):');
      for (final turn in historySlice) {
        final label = turn.role == 'coach' ? 'COACH' : 'BYSTANDER';
        buf.writeln('$label: ${turn.text.trim()}');
      }
      buf.writeln();
    }

    buf.writeln('BYSTANDER (current message):');
    buf.writeln(latestTranscript.trim());
    buf.writeln();
    buf.writeln(
      'COACH (give the NEXT step, one numbered item, ≤30 words, end with "Tell me what you see now."):',
    );

    return buf.toString();
  }

  // ─── Generation ───────────────────────────────────────────────────────────

  Future<String> _generateReply({
    required String latestTranscript,
    required String grounding,
    required String languageCode,
  }) async {
    final prompt = _buildPrompt(
      latestTranscript: latestTranscript,
      grounding: grounding,
      languageCode: languageCode,
    );

    String? out;
    try {
      final gemma = _ref.read(gemmaLocalServiceProvider);
      if (gemma.isAvailable) {
        out = await gemma.generate(prompt).timeout(const Duration(seconds: 20));
      }
    } on Object catch (e, st) {
      appLog.d('[BystanderCoach] gemma generate failed', stackTrace: st);
    }

    out = out?.trim();
    if (out == null || out.isEmpty) {
      return _deterministicReply(latestTranscript, grounding, languageCode);
    }
    return _postProcess(out);
  }

  // ─── Deterministic fallback ───────────────────────────────────────────────

  /// Smarter offline fallback: uses accumulated situation keywords to pick a
  /// relevant step from the grounding text, rather than always returning step 1.
  String _deterministicReply(String transcript, String grounding, String lang) {
    // Determine which step we should be on based on conversation depth.
    final bystanderTurnCount = state.turns
        .where((t) => t.role == 'bystander')
        .length;

    // Try to find a numbered step matching the current situation.
    final lines = grounding.split('\n');
    String step = '';

    // Look for the most relevant numbered step in the grounding.
    if (bystanderTurnCount <= 1) {
      // First turn — life-threatening check or first grounding step.
      final lower = transcript.toLowerCase();
      final isLifeThreatening =
          lower.contains('not breathing') ||
          lower.contains('unconscious') ||
          lower.contains('not responding') ||
          lower.contains('bleeding heavily') ||
          lower.contains('no pulse');
      if (isLifeThreatening) {
        step =
            'Call 108 immediately. Tell them the location and that the person is not responding.';
      } else {
        step = _extractStepN(lines, 1);
      }
    } else {
      // Subsequent turns — advance to the next logical step.
      final nextStep = (bystanderTurnCount).clamp(1, 6);
      step = _extractStepN(lines, nextStep);
      if (step.isEmpty) {
        step = _extractStepN(lines, 1);
      }
    }

    if (step.isEmpty) {
      step =
          'Call 108 now and stay with the person. Keep them still and reassure them.';
    }

    final tail = switch (lang) {
      'hi' => 'अभी क्या दिख रहा है मुझे बताइए।',
      'ta' => 'இப்போது என்ன தெரிகிறது என்று சொல்லுங்கள்.',
      'te' => 'ఇప్పుడు ఏమి కనిపిస్తుందో చెప్పండి.',
      'bn' => 'এখন কী দেখছেন বলুন।',
      'mr' => 'आत्ता काय दिसतेय ते सांगा.',
      _ => 'Tell me what you see now.',
    };
    return '$step $tail';
  }

  /// Extract the Nth numbered step from grounding lines. Returns '' if not found.
  String _extractStepN(List<String> lines, int n) {
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('$n)') || trimmed.startsWith('$n.')) {
        final content = trimmed.replaceFirst(RegExp('^$n[).]\\s*'), '').trim();
        if (content.isNotEmpty) return content;
      }
    }
    return '';
  }

  // ─── Post-processing ──────────────────────────────────────────────────────

  String _postProcess(String raw) {
    // Strip code fences / leading "Coach:" labels Gemma sometimes emits.
    var t = raw.replaceAll(RegExp(r'^```[a-z]*'), '').replaceAll('```', '');
    t = t.replaceAll(
      RegExp(r'^\s*(coach|assistant|response)\s*:\s*', caseSensitive: false),
      '',
    );
    // Strip any "COACH:" prefix the model may prepend.
    t = t.replaceAll(RegExp(r'^COACH:\s*', caseSensitive: false), '');
    // Hard cap to keep TTS short and readable on small screens.
    if (t.length > 400) t = '${t.substring(0, 400)}…';
    return t.trim();
  }

  // ─── Locale helpers ───────────────────────────────────────────────────────

  String _greetingFor(String lang) {
    switch (lang) {
      case 'hi':
        return 'मैं RoadSOS कोच हूँ। एक काम एक बार में करेंगे। पहले बताइए — व्यक्ति होश में है क्या?';
      case 'ta':
        return 'நான் RoadSOS கோச். ஒரே நேரத்தில் ஒரு படி. முதலில் சொல்லுங்கள் — நபர் நினைவில் இருக்கிறாரா?';
      case 'te':
        return 'నేను RoadSOS కోచ్. ఒక్క మెట్టు ఒక్క సారి. మొదట చెప్పండి — వ్యక్తి స్పృహలో ఉన్నారా?';
      case 'bn':
        return 'আমি RoadSOS কোচ। এক বার এক পদক্ষেপ। প্রথমে বলুন — ব্যক্তি জ্ঞান আছে কি?';
      case 'mr':
        return 'मी RoadSOS कोच. एक वेळी एक पाऊल. आधी सांगा — व्यक्ती शुद्धीत आहे का?';
      default:
        return 'I am RoadSOS Coach. One step at a time. First — is the person responding?';
    }
  }

  String _localeDirective(String lang) {
    switch (lang) {
      case 'hi':
        return 'IMPORTANT: Respond entirely in Hindi (Devanagari script). Use Arabic numerals for step numbers.';
      case 'ta':
        return 'IMPORTANT: Respond entirely in Tamil. Use Arabic numerals for step numbers.';
      case 'te':
        return 'IMPORTANT: Respond entirely in Telugu. Use Arabic numerals for step numbers.';
      case 'bn':
        return 'IMPORTANT: Respond entirely in Bengali. Use Arabic numerals for step numbers.';
      case 'mr':
        return 'IMPORTANT: Respond entirely in Marathi (Devanagari script). Use Arabic numerals for step numbers.';
      default:
        return 'IMPORTANT: Respond in plain English only.';
    }
  }

  // ─── State helpers ────────────────────────────────────────────────────────

  void _appendTurn(String role, String text) {
    final turns = List<BystanderCoachTurn>.from(state.turns)
      ..add(BystanderCoachTurn(role: role, text: text));
    state = state.copyWith(turns: turns);
  }

  @visibleForTesting
  bool get sttReady => _sttReady;

  @visibleForTesting
  Set<String> get situationKeywords => Set.unmodifiable(_situationKeywords);
}

final bystanderCoachServiceProvider =
    StateNotifierProvider<BystanderCoachService, BystanderCoachState>((ref) {
      return BystanderCoachService(ref);
    });

/// Intent categories used by [BystanderCoachService._detectIntent].
enum _CoachIntent {
  medicalFirstAid,
  vehicleRescue,
  vehicleAssistance,
  findHelp,
  legalOrInsurance,
}
