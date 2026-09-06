import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:roadsos/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_locale_controller.dart';
import '../services/camera_triage_service.dart';
import '../services/last_scene_photo_store.dart';
import '../services/roadsos_assistant_service.dart';

class IncidentReportingScreen extends ConsumerStatefulWidget {
  const IncidentReportingScreen({super.key});

  @override
  ConsumerState<IncidentReportingScreen> createState() =>
      _IncidentReportingScreenState();
}

class _IncidentReportingScreenState
    extends ConsumerState<IncidentReportingScreen> {
  final TextEditingController _voiceInputController = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _sceneImageBytes;
  bool _sceneCaptureBusy = false;

  @override
  Widget build(BuildContext context) {
    final assistantState = ref.watch(roadsosAssistantProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          l10n.sceneIntelligenceTitle,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('MULTIMODAL: DIGITAL TWIN'),
            const SizedBox(height: 12),
            _buildSceneCaptureCard(l10n),
            const SizedBox(height: 32),
            _buildSectionHeader('AI INTERVIEW: SITUATIONAL NUANCE'),
            const SizedBox(height: 12),
            _buildVoiceInterviewCard(assistantState, l10n),
            const SizedBox(height: 32),
            // Show guidance steps after interview is complete
            if (assistantState.showingGuidance &&
                assistantState.guidanceSteps.isNotEmpty) ...[
              _buildSectionHeader('ACTION GUIDANCE: NEXT STEPS'),
              const SizedBox(height: 12),
              _buildGuidanceCard(assistantState, l10n),
              const SizedBox(height: 32),
            ],
            if (assistantState.history.isNotEmpty) ...[
              _buildSectionHeader('SITUATION BRIEF (LIVE)'),
              const SizedBox(height: 12),
              _buildLiveBriefCard(assistantState),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        color: Colors.blue.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildSceneCaptureCard(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sceneImageBytes == null)
              Icon(
                Icons.camera_enhance,
                size: 40,
                color: Colors.white.withValues(alpha: 0.3),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _sceneImageBytes!,
                  width: 120,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sceneCaptureBusy ? null : _captureScene,
              icon: _sceneCaptureBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _sceneImageBytes != null
                          ? Icons.check
                          : Icons.add_a_photo,
                    ),
              label: Text(
                _sceneImageBytes != null
                    ? 'SCENE ATTACHED'
                    : 'CAPTURE / ATTACH PHOTO',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _sceneImageBytes != null
                    ? Colors.green
                    : Colors.blue,
              ),
            ),
            if (_sceneImageBytes != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: const Text(
                  'Photo armed — Gemma 4 27B vision will analyze it on the next SOS.',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureScene() async {
    setState(() => _sceneCaptureBusy = true);
    Uint8List? bytes;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 72,
        maxWidth: 1600,
      );
      if (file != null) bytes = await file.readAsBytes();
    } on Object catch (_) {
      // On emulators / devices without camera, silently fall back to gallery.
    }

    if (bytes == null) {
      try {
        final file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 72,
          maxWidth: 1600,
        );
        if (file != null) bytes = await file.readAsBytes();
      } on Object {
        if (!mounted) return;
        setState(() => _sceneCaptureBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not capture a scene photo on this device.'),
          ),
        );
        return;
      }
    }

    if (bytes == null) {
      if (!mounted) return;
      setState(() => _sceneCaptureBusy = false);
      return;
    }

    // Arm the photo for the next SOS — orchestrator will pull this through to
    // Gemma 4 27B vision. Drops automatically after 120s so a stale photo
    // never contaminates an unrelated emergency.
    ref
        .read(lastScenePhotoStoreProvider)
        .store(
          CapturedScenePhoto(
            base64Jpeg: base64Encode(bytes),
            sizeBytes: bytes.length,
            capturedAt: DateTime.now().toUtc(),
          ),
        );

    if (!mounted) return;
    setState(() {
      _sceneImageBytes = bytes;
      _sceneCaptureBusy = false;
    });

    if (!kIsWeb && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Scene photo armed for Gemma 4 vision (active for the next 2 minutes).',
          ),
        ),
      );
    }
  }

  Widget _buildVoiceInterviewCard(
    AssistantState assistant,
    AppLocalizations l10n,
  ) {
    final lang = ref.read(appLocaleProvider).languageCode;
    final totalQuestions = _getTotalQuestionsForScene(
      assistant.sceneContext,
      lang,
    );
    final progress = '${assistant.questionIndex} / $totalQuestions';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Scene context badge
          if (assistant.sceneContext != 'unknown')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'Scene: ${_getSceneLabel(assistant.sceneContext, lang)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // Interview progress
          if (assistant.questionIndex > 0 && !assistant.interviewComplete)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    lang == 'hi' ? 'प्रश्न प्रगति:' : 'Question Progress:',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      progress,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Main question text
          Text(
            assistant.lastResponse.isEmpty
                ? (lang == 'hi'
                      ? 'कृपया घटना का वर्णन करें'
                      : 'Please describe the incident')
                : assistant.lastResponse,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Input field and send button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _voiceInputController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: lang == 'hi'
                        ? 'बोलें या टाइप करें…'
                        : 'Speak or type…',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: Colors.black,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  enabled: !assistant.interviewComplete,
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: assistant.interviewComplete
                    ? null
                    : () {
                        if (_voiceInputController.text.isNotEmpty) {
                          ref
                              .read(roadsosAssistantProvider.notifier)
                              .getNextWitnessQuestion(
                                _voiceInputController.text,
                                languageCode: lang,
                              );
                          _voiceInputController.clear();
                        }
                      },
                icon: assistant.isThinking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        assistant.interviewComplete
                            ? Icons.done_all
                            : Icons.send,
                      ),
              ),
            ],
          ),
          // Interview completion message
          if (assistant.interviewComplete)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  lang == 'hi'
                      ? '✓ साक्षात्कार पूर्ण। सभी महत्वपूर्ण जानकारी एकत्र की गई।'
                      : '✓ Interview complete. All critical information collected.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getSceneLabel(String sceneContext, String lang) {
    if (lang == 'hi') {
      const labels = {
        'vehicle_collision': 'वाहन टक्कर',
        'pedestrian_hit': 'पैदल यात्री मारे गए',
        'rollover': 'वाहन पलटना',
        'fire_hazard': 'आग का खतरा',
      };
      return labels[sceneContext] ?? 'अज्ञात';
    } else {
      const labels = {
        'vehicle_collision': 'Vehicle Collision',
        'pedestrian_hit': 'Pedestrian Hit',
        'rollover': 'Rollover',
        'fire_hazard': 'Fire Hazard',
      };
      return labels[sceneContext] ?? 'Unknown';
    }
  }

  int _getTotalQuestionsForScene(String sceneContext, String lang) {
    // Return total questions for the scene (5 for all main scenes, 5 for unknown)
    return 5;
  }

  Widget _buildLiveBriefCard(AssistantState assistant) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        assistant.history.join('\n'),
        style: const TextStyle(color: Colors.white70, height: 1.5),
      ),
    );
  }

  Widget _buildGuidanceCard(AssistantState assistant, AppLocalizations l10n) {
    final lang = ref.read(appLocaleProvider).languageCode;
    final steps = assistant.guidanceSteps;
    final completedCount = steps.where((s) => s.completed).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with progress
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      lang == 'hi' ? '🎯 कार्रवाई चरण' : '🎯 Action Steps',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.green,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$completedCount/${steps.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: steps.isEmpty ? 0 : completedCount / steps.length,
                    minHeight: 6,
                    backgroundColor: Colors.green.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(
                      Colors.green.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Steps list
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: steps.asMap().entries.map((entry) {
                final index = entry.key;
                final step = entry.value;
                final isLast = index == steps.length - 1;

                return Column(
                  children: [
                    InkWell(
                      onTap: () {
                        ref
                            .read(roadsosAssistantProvider.notifier)
                            .completeGuidanceStep(step.stepNumber);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: step.completed
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: step.completed
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Step number / checkbox
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: step.completed
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : Colors.blue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: step.completed
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.green,
                                        size: 20,
                                      )
                                    : Text(
                                        step.stepNumber.toString(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.blue,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Step details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: step.completed
                                          ? Colors.green
                                          : Colors.white,
                                      decoration: step.completed
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    step.description,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(
                                        alpha: step.completed ? 0.5 : 0.7,
                                      ),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Icon
                            Text(
                              step.icon,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }).toList(),
            ),
          ),
          // Bottom action button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ref.read(roadsosAssistantProvider.notifier).resetInterview();
                  _voiceInputController.clear();
                },
                icon: const Icon(Icons.add_circle),
                label: Text(
                  lang == 'hi' ? 'नई घटना रिपोर्ट करें' : 'Report New Incident',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withValues(alpha: 0.3),
                  foregroundColor: Colors.green,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
