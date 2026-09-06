import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_locale_controller.dart';
import '../services/bystander_coach_service.dart';
import '../services/first_aid_repository.dart';

/// Bystander Coach UI — large mic button, live transcript, scrollable chat.
///
/// Designed for stress: thumb-friendly mic, full-bleed colors, no chrome to
/// read. Locale comes from [appLocaleProvider] so a Hindi/Marathi/Tamil user
/// hears Gemma 4 reply in the same language.
class BystanderCoachScreen extends ConsumerStatefulWidget {
  const BystanderCoachScreen({super.key});

  @override
  ConsumerState<BystanderCoachScreen> createState() =>
      _BystanderCoachScreenState();
}

class _BystanderCoachScreenState extends ConsumerState<BystanderCoachScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locale = ref.read(appLocaleProvider);
      ref
          .read(bystanderCoachServiceProvider.notifier)
          .startSession(languageCode: locale.languageCode);
    });
  }

  @override
  void dispose() {
    ref.read(bystanderCoachServiceProvider.notifier).endSession();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bystanderCoachServiceProvider);
    final notifier = ref.read(bystanderCoachServiceProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF080A0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080A0D),
        elevation: 0,
        title: const Text(
          'BYSTANDER COACH',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            fontSize: 14,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'About',
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _phaseBanner(state.phase),
            Expanded(child: _chat(state)),
            if (state.errorMessage != null) _errorRow(state.errorMessage!),
            _bottomControls(state, notifier),
          ],
        ),
      ),
    );
  }

  Widget _phaseBanner(BystanderCoachPhase phase) {
    final (color, label) = switch (phase) {
      BystanderCoachPhase.idle => (const Color(0xFF1F2933), 'READY'),
      BystanderCoachPhase.listening => (const Color(0xFF00B8A0), 'LISTENING'),
      BystanderCoachPhase.thinking => (
        const Color(0xFFFFB400),
        'THINKING (Gemma 4)',
      ),
      BystanderCoachPhase.speaking => (const Color(0xFFE8281A), 'COACHING'),
      BystanderCoachPhase.error => (const Color(0xFFE8281A), 'ERROR'),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: color,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  Widget _chat(BystanderCoachState state) {
    if (state.turns.isEmpty && state.partial.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tap the mic and describe what you see.\n\nExample: "person on road, not moving, bleeding from leg".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: state.turns.length + (state.partial.isEmpty ? 0 : 1),
      itemBuilder: (context, i) {
        if (state.partial.isNotEmpty && i == 0) {
          return _bubble(text: state.partial, isCoach: false, isPartial: true);
        }
        final reverseIndex = state.partial.isNotEmpty ? i - 1 : i;
        final turn = state.turns[state.turns.length - 1 - reverseIndex];
        return _bubble(text: turn.text, isCoach: turn.role == 'coach');
      },
    );
  }

  Widget _bubble({
    required String text,
    required bool isCoach,
    bool isPartial = false,
  }) {
    final bg = isCoach ? const Color(0xFF1F2933) : const Color(0xFF00322B);
    final align = isCoach ? Alignment.centerLeft : Alignment.centerRight;
    final tag = isPartial
        ? 'YOU · LIVE'
        : isCoach
        ? 'COACH'
        : 'YOU';
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tag,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(
                color: isPartial ? Colors.white70 : Colors.white,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorRow(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0x33E8281A),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFE8281A), fontSize: 12),
      ),
    );
  }

  Widget _bottomControls(
    BystanderCoachState state,
    BystanderCoachService notifier,
  ) {
    final busy =
        state.phase == BystanderCoachPhase.thinking ||
        state.phase == BystanderCoachPhase.speaking;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      color: const Color(0xFF080A0D),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  enabled: !busy,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Type what you see…',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Color(0xFF11151B),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  onSubmitted: (v) async {
                    final txt = v.trim();
                    if (txt.isEmpty || busy) return;
                    _textController.clear();
                    await notifier.submitTurn(txt);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Send',
                onPressed: busy
                    ? null
                    : () async {
                        final txt = _textController.text.trim();
                        if (txt.isEmpty) return;
                        _textController.clear();
                        await notifier.submitTurn(txt);
                      },
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 220,
            height: 64,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: state.phase == BystanderCoachPhase.listening
                    ? const Color(0xFFE8281A)
                    : const Color(0xFF00B8A0),
                shape: const StadiumBorder(),
              ),
              onPressed: busy
                  ? null
                  : () async {
                      await HapticFeedback.mediumImpact();
                      await notifier.startListening();
                    },
              icon: Icon(
                state.phase == BystanderCoachPhase.listening
                    ? Icons.graphic_eq
                    : Icons.mic,
                size: 28,
              ),
              label: Text(
                state.phase == BystanderCoachPhase.listening
                    ? 'LISTENING…'
                    : 'TAP TO SPEAK',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAbout(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bystander Coach'),
        content: const SingleChildScrollView(
          child: Text(
            'On-device Gemma 4 E4B guides you through evidence-based first aid '
            'until paramedics arrive. Runs offline.\n\n'
            'Speak or type what you see — the coach replies one step at a time '
            'in your selected language.\n\n'
            'This is not medical advice. Always dial 108 / 112 ERSS.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Medical disclaimer'),
                  content: Text(FirstAidRepository.medicalDisclaimer),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('CLOSE'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('DISCLAIMER'),
          ),
        ],
      ),
    );
  }
}
