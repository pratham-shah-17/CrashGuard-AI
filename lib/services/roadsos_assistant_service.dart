import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_log.dart';

/// Cloud-first assistant powered by Gemma 4 27B via Supabase Edge Function.
/// Falls back to structured question scripts when cloud is unavailable.
class AssistantState {
  final String lastResponse;
  final bool isThinking;
  final List<String> history;
  final String sceneContext;
  final Set<String> askedQuestions;
  final int questionIndex;
  final bool interviewComplete;
  final List<GuidanceStep> guidanceSteps;
  final bool showingGuidance;

  AssistantState({
    this.lastResponse = '',
    this.isThinking = false,
    this.history = const [],
    this.sceneContext = 'unknown',
    this.askedQuestions = const {},
    this.questionIndex = 0,
    this.interviewComplete = false,
    this.guidanceSteps = const [],
    this.showingGuidance = false,
  });

  AssistantState copyWith({
    String? lastResponse,
    bool? isThinking,
    List<String>? history,
    String? sceneContext,
    Set<String>? askedQuestions,
    int? questionIndex,
    bool? interviewComplete,
    List<GuidanceStep>? guidanceSteps,
    bool? showingGuidance,
  }) {
    return AssistantState(
      lastResponse: lastResponse ?? this.lastResponse,
      isThinking: isThinking ?? this.isThinking,
      history: history ?? this.history,
      sceneContext: sceneContext ?? this.sceneContext,
      askedQuestions: askedQuestions ?? this.askedQuestions,
      questionIndex: questionIndex ?? this.questionIndex,
      interviewComplete: interviewComplete ?? this.interviewComplete,
      guidanceSteps: guidanceSteps ?? this.guidanceSteps,
      showingGuidance: showingGuidance ?? this.showingGuidance,
    );
  }
}

class GuidanceStep {
  final int stepNumber;
  final String title;
  final String description;
  final String icon;
  final bool completed;

  GuidanceStep({
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.icon,
    this.completed = false,
  });

  GuidanceStep copyWith({bool? completed}) {
    return GuidanceStep(
      stepNumber: stepNumber,
      title: title,
      description: description,
      icon: icon,
      completed: completed ?? this.completed,
    );
  }
}

class RoadSosAssistantService extends StateNotifier<AssistantState> {
  RoadSosAssistantService() : super(AssistantState());

  static const Map<String, List<String>> _sceneQuestionsEn = {
    'vehicle_collision': [
      'How many vehicles are involved in this collision?',
      'Are there any trapped or injured occupants in the vehicles?',
      'Are there any leaked fluids or smoke visible near the vehicles?',
      'Is the scene safe for responders? Are traffic/pedestrians at risk?',
      'Can you describe the impact damage and vehicle positions?',
    ],
    'pedestrian_hit': [
      'Is the pedestrian conscious and responsive?',
      'Are there any visible injuries or bleeding?',
      'Was the pedestrian hit by a vehicle? Describe the incident.',
      'Is the pedestrian able to move or complaining of pain?',
      'What is the pedestrian\'s approximate age and current location?',
    ],
    'rollover': [
      'How many occupants are in the vehicle?',
      'Are any occupants trapped inside the vehicle?',
      'Is the fuel leaking or is there smoke/fire risk?',
      'Are occupants conscious and can they move?',
      'What is the vehicle\'s current stable position?',
    ],
    'fire_hazard': [
      'Is there active fire or heavy smoke from the vehicle?',
      'Are occupants still inside the vehicle?',
      'Is the fire spreading to nearby vehicles or structures?',
      'Have you alerted nearby people to evacuate?',
      'What is the estimated size and intensity of the fire?',
    ],
    'unknown': [
      'What type of incident is this? (collision, medical, fire, etc.)',
      'How many people are affected?',
      'Are there any visible injuries or emergencies?',
      'Is the scene safe for responders to approach?',
      'What is the current status and any immediate dangers?',
    ],
  };

  static const Map<String, List<String>> _sceneQuestionsHi = {
    'vehicle_collision': [
      'इस टक्कर में कितने वाहन शामिल हैं?',
      'क्या कोई फंसे हुए या घायल लोग हैं?',
      'क्या वाहनों के पास तरल रिसाव या धुआँ दिखाई दे रहा है?',
      'क्या दृश्य प्रथमदर्शकों के लिए सुरक्षित है?',
      'टक्कर के नुकसान और वाहन की स्थिति बताइए।',
    ],
    'pedestrian_hit': [
      'क्या पैदल यात्री होश में है?',
      'कोई दिखाई देने वाली चोट या खून तो नहीं?',
      'पैदल यात्री को वाहन ने मारा? घटना बताइए।',
      'क्या पैदल यात्री हिल-डुल सकता है?',
      'पीड़ित की उम्र और स्थिति क्या है?',
    ],
    'rollover': [
      'वाहन में कितने लोग हैं?',
      'क्या कोई फंसा हुआ है?',
      'क्या ईंधन रिस रहा है या आग का खतरा है?',
      'क्या लोग होश में हैं?',
      'वाहन की स्थिति कैसी है?',
    ],
    'fire_hazard': [
      'क्या आग या भारी धुआँ दिखाई दे रहा है?',
      'क्या कोई वाहन में है?',
      'क्या आग फैल रही है?',
      'क्या लोगों को खाली करने की चेतावनी दी?',
      'आग कितनी बड़ी और तीव्र है?',
    ],
    'unknown': [
      'यह किस प्रकार की घटना है?',
      'कितने लोग प्रभावित हैं?',
      'कोई दिखाई देने वाली चोट तो नहीं?',
      'क्या दृश्य सुरक्षित है?',
      'वर्तमान स्थिति और खतरे क्या हैं?',
    ],
  };

  /// Call Gemma 4 27B via Supabase Edge Function for dynamic question generation.
  Future<String?> _gemma4Generate(String prompt) async {
    if (kIsWeb) return null;
    try {
      final client = Supabase.instance.client;
      // Edge function slug: 'gemini-generate' (legacy name kept for Supabase deploy compatibility).
      // Internally uses Gemma 4 27B (gemma-4-27b-it). See supabase/functions/gemini-generate/index.ts.
      final res = await client.functions.invoke(
        'gemini-generate',
        body: <String, dynamic>{
          'prompt': prompt,
          'model': 'gemma-4-27b-it',
          'temperature': 0.4,
          'max_output_tokens': 150,
        },
      );
      final data = res.data;
      if (data is Map && data['text'] is String) {
        return (data['text'] as String).trim();
      }
      return null;
    } on Object catch (e, st) {
      appLog.d(
        '[Assistant] Gemma 4 cloud generate failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Local keyword fallback — used only when Gemma 4 cloud is unreachable.
  /// Intentionally conservative: defaults to `unknown` so a fresh scene falls
  /// into the generic five-question script when offline.
  String _detectSceneContextLocal(String input) {
    final lower = input.toLowerCase();
    if (lower.contains('pedestrian') || lower.contains('पैदल')) {
      return 'pedestrian_hit';
    }
    if (lower.contains('rollover') ||
        lower.contains('पलटा') ||
        lower.contains('overturned')) {
      return 'rollover';
    }
    if (lower.contains('fire') ||
        lower.contains('आग') ||
        lower.contains('smoke') ||
        lower.contains('धुआँ')) {
      return 'fire_hazard';
    }
    if (lower.contains('collision') ||
        lower.contains('टक्कर') ||
        lower.contains('crash')) {
      return 'vehicle_collision';
    }
    return 'unknown';
  }

  /// Use Gemma 4 27B (cloud) to bucket the bystander's first description into
  /// one of: vehicle_collision | pedestrian_hit | rollover | fire_hazard |
  /// unknown. Falls back to the local keyword classifier if the cloud is
  /// unreachable, the model misbehaves, or web demo mode is active.
  Future<String> _detectSceneContext(String input) async {
    if (kIsWeb || input.trim().isEmpty) {
      return _detectSceneContextLocal(input);
    }
    const allowed = <String>{
      'vehicle_collision',
      'pedestrian_hit',
      'rollover',
      'fire_hazard',
      'unknown',
    };
    final prompt =
        'You are a triage scene classifier for a road-accident app in India.\n'
        'Bystander first description (any Indian language allowed):\n"""$input"""\n\n'
        'Pick the SINGLE best label from: vehicle_collision, pedestrian_hit, '
        'rollover, fire_hazard, unknown.\n'
        'Respond with ONLY that one word, no punctuation, no quotes, no '
        'explanation. If genuinely ambiguous, respond unknown.';
    try {
      final out = (await _gemma4Generate(prompt))?.toLowerCase().trim();
      if (out == null || out.isEmpty) return _detectSceneContextLocal(input);
      // Find the first allowed label appearing anywhere in the model output.
      for (final label in allowed) {
        if (out == label || out.startsWith(label) || out.contains(label)) {
          return label;
        }
      }
      return _detectSceneContextLocal(input);
    } on Object catch (_) {
      return _detectSceneContextLocal(input);
    }
  }

  /// Use Gemma 4 27B (cloud) to compose the FIRST adaptive triage question
  /// instead of reading the canned scripted first question. Falls back to the
  /// scripted question only when the cloud is unreachable.
  Future<String?> _composeFirstQuestionWithGemma({
    required String sceneContext,
    required String previousAnswer,
    required String languageCode,
  }) async {
    if (kIsWeb || previousAnswer.trim().isEmpty) return null;
    final langLabel = switch (languageCode) {
      'hi' => 'Hindi',
      'ta' => 'Tamil',
      'te' => 'Telugu',
      'bn' => 'Bengali',
      'mr' => 'Marathi',
      _ => 'English',
    };
    final prompt =
        'You are an emergency triage assistant for RoadSOS (India). Scene '
        'classified as: $sceneContext. The bystander just said:\n'
        '"""$previousAnswer"""\n\n'
        'Ask the SINGLE most critical follow-up question to gather the next '
        'piece of dispatch-relevant information. Constraints:\n'
        '- One question, under 18 words.\n'
        '- $langLabel. Plain words. No prefix, no quotes, no markdown.\n'
        '- If unresponsive victim suspected, ask about breathing/consciousness '
        'first.\n';
    try {
      final raw = (await _gemma4Generate(prompt))?.trim();
      if (raw == null || raw.isEmpty) return null;
      // Take the first line, strip leading "Q:" / "1)" etc.
      var line = raw
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
          .trim();
      line = line.replaceFirst(
        RegExp(r'^(\d+[\.\)]\s*|q[:\-]\s*)', caseSensitive: false),
        '',
      );
      if (line.length > 240) line = '${line.substring(0, 240)}…';
      return line.isEmpty ? null : line;
    } on Object catch (_) {
      return null;
    }
  }

  void setSceneContext(String context) {
    state = state.copyWith(sceneContext: context);
  }

  void completeGuidanceStep(int stepNumber) {
    final updated = state.guidanceSteps.map((s) {
      return s.stepNumber == stepNumber ? s.copyWith(completed: true) : s;
    }).toList();
    state = state.copyWith(guidanceSteps: updated);
  }

  void resetInterview() {
    state = AssistantState();
  }

  Future<String> getNextWitnessQuestion(
    String previousAnswer, {
    String languageCode = 'en',
  }) async {
    if (state.history.isEmpty) {
      state = state.copyWith(isThinking: true);

      // Gemma 4 27B classifies the scene from the bystander's free-form first
      // line. Falls back to keyword classifier when cloud is unreachable.
      final detectedContext = await _detectSceneContext(previousAnswer);

      final questions = languageCode == 'hi'
          ? _sceneQuestionsHi
          : _sceneQuestionsEn;
      final sceneQuestions =
          questions[detectedContext] ?? questions['unknown']!;

      // First question is also Gemma-composed for true adaptive follow-up.
      // Falls back to the scripted first scene question only when cloud fails.
      final gemmaFirst = await _composeFirstQuestionWithGemma(
        sceneContext: detectedContext,
        previousAnswer: previousAnswer,
        languageCode: languageCode,
      );
      final firstQuestion = gemmaFirst ?? sceneQuestions.first;

      state = state.copyWith(
        isThinking: false,
        lastResponse: firstQuestion,
        history: [...state.history, previousAnswer, firstQuestion],
        sceneContext: detectedContext,
        askedQuestions: {firstQuestion},
        questionIndex: 1,
        interviewComplete: false,
      );
      return firstQuestion;
    }

    if (state.interviewComplete) {
      final endMessage = languageCode == 'hi'
          ? 'साक्षात्कार पूर्ण। सभी महत्वपूर्ण जानकारी एकत्र की जा चुकी है। धन्यवाद।'
          : 'Interview complete. All critical information has been gathered. Thank you.';
      return endMessage;
    }

    state = state.copyWith(isThinking: true);

    // Try Gemma 4 for adaptive follow-up questions based on conversation so far.
    final conversationContext = state.history.take(6).join('\n');
    final gemmaPrompt =
        'Emergency scene type: ${state.sceneContext}. Conversation so far:\n$conversationContext\n'
        'Responder answer: "$previousAnswer"\n'
        'Ask ONE short follow-up question in ${languageCode == "hi" ? "Hindi" : "English"} '
        'to gather the most critical missing information for emergency dispatch. '
        'Just the question, no prefix.';

    String? gemmaQuestion = await _gemma4Generate(gemmaPrompt);

    final questions = languageCode == 'hi'
        ? _sceneQuestionsHi
        : _sceneQuestionsEn;
    final sceneQuestions =
        questions[state.sceneContext] ?? questions['unknown']!;
    final nextIndex = state.questionIndex % sceneQuestions.length;

    var fallbackQuestion = sceneQuestions[nextIndex];
    var searchIndex = nextIndex;
    var attempts = 0;
    while (state.askedQuestions.contains(fallbackQuestion) &&
        attempts < sceneQuestions.length) {
      searchIndex = (searchIndex + 1) % sceneQuestions.length;
      fallbackQuestion = sceneQuestions[searchIndex];
      attempts++;
    }

    final bool newInterviewComplete =
        state.askedQuestions.length >= sceneQuestions.length &&
        gemmaQuestion == null;

    final response = newInterviewComplete
        ? (languageCode == 'hi'
              ? 'साक्षात्कार पूर्ण। धन्यवाद।'
              : 'Interview complete. Thank you.')
        : (gemmaQuestion ?? fallbackQuestion);

    final newGuidanceSteps = newInterviewComplete
        ? _generateGuidanceSteps(state.sceneContext, languageCode)
        : <GuidanceStep>[];

    state = state.copyWith(
      isThinking: false,
      lastResponse: response,
      history: [...state.history, previousAnswer, response],
      askedQuestions: {...state.askedQuestions, response},
      questionIndex: nextIndex + 1,
      interviewComplete: newInterviewComplete,
      guidanceSteps: newGuidanceSteps,
      showingGuidance: newInterviewComplete,
    );

    return response;
  }

  List<GuidanceStep> _generateGuidanceSteps(String sceneContext, String lang) {
    if (lang == 'hi') {
      switch (sceneContext) {
        case 'vehicle_collision':
          return [
            GuidanceStep(
              stepNumber: 1,
              title: 'सुरक्षा सुनिश्चित करें',
              description: 'घायलों को सड़क से हटाएं। ट्रैफिक की चेतावनी दें।',
              icon: '🚨',
            ),
            GuidanceStep(
              stepNumber: 2,
              title: 'आपातकालीन सेवाएं बुलाएं',
              description: '112 डायल करें।',
              icon: '📞',
            ),
            GuidanceStep(
              stepNumber: 3,
              title: 'प्राथमिक चिकित्सा करें',
              description: 'रक्तस्राव नियंत्रित करें। एयरवे खुला रखें।',
              icon: '🏥',
            ),
            GuidanceStep(
              stepNumber: 4,
              title: 'साक्ष्य संरक्षित करें',
              description: 'तस्वीरें लें। चश्मदीद खोजें।',
              icon: '📸',
            ),
            GuidanceStep(
              stepNumber: 5,
              title: 'पुलिस को सूचित करें',
              description: 'FIR दर्ज करें।',
              icon: '👮',
            ),
          ];
        default:
          return [
            GuidanceStep(
              stepNumber: 1,
              title: '112 डायल करें',
              description: 'तुरंत आपातकालीन सेवा बुलाएं।',
              icon: '📞',
            ),
            GuidanceStep(
              stepNumber: 2,
              title: 'घायलों को स्थिर करें',
              description: 'हिलाएं नहीं। सहारा दें।',
              icon: '🤝',
            ),
            GuidanceStep(
              stepNumber: 3,
              title: 'क्षेत्र सुरक्षित करें',
              description: 'ट्रैफिक को चेतावनी दें।',
              icon: '🚧',
            ),
          ];
      }
    } else {
      switch (sceneContext) {
        case 'vehicle_collision':
          return [
            GuidanceStep(
              stepNumber: 1,
              title: 'Ensure Scene Safety',
              description: 'Move injured to safety if possible. Warn traffic.',
              icon: '🚨',
            ),
            GuidanceStep(
              stepNumber: 2,
              title: 'Call Emergency Services',
              description: 'Dial 112 or 911.',
              icon: '📞',
            ),
            GuidanceStep(
              stepNumber: 3,
              title: 'Provide First Aid',
              description: 'Control bleeding. Keep airway open.',
              icon: '🏥',
            ),
            GuidanceStep(
              stepNumber: 4,
              title: 'Preserve Evidence',
              description: 'Take photos. Note vehicle numbers.',
              icon: '📸',
            ),
            GuidanceStep(
              stepNumber: 5,
              title: 'Notify Police',
              description: 'File incident report.',
              icon: '👮',
            ),
          ];
        case 'fire_hazard':
          return [
            GuidanceStep(
              stepNumber: 1,
              title: 'Evacuate Immediately',
              description: 'Move everyone away from fire.',
              icon: '🏃',
            ),
            GuidanceStep(
              stepNumber: 2,
              title: 'Call Fire Brigade',
              description: 'Dial 101 (India) or 112.',
              icon: '🚒',
            ),
            GuidanceStep(
              stepNumber: 3,
              title: 'Call Ambulance',
              description: 'Dial 102 (India) for burn injuries.',
              icon: '🚑',
            ),
          ];
        default:
          return [
            GuidanceStep(
              stepNumber: 1,
              title: 'Call Emergency Services',
              description: 'Dial 112. Describe situation clearly.',
              icon: '📞',
            ),
            GuidanceStep(
              stepNumber: 2,
              title: 'Stabilize Victims',
              description: 'Do not move injured unless in danger.',
              icon: '🤝',
            ),
            GuidanceStep(
              stepNumber: 3,
              title: 'Secure the Scene',
              description: 'Warn traffic. Keep crowd back.',
              icon: '🚧',
            ),
          ];
      }
    }
  }
}

final roadSosAssistantServiceProvider =
    StateNotifierProvider<RoadSosAssistantService, AssistantState>((ref) {
      return RoadSosAssistantService();
    });

/// Alias used by UI files.
final roadsosAssistantProvider = roadSosAssistantServiceProvider;
