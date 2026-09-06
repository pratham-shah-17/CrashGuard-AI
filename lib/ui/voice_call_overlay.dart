import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/webrtc_voice_call_service.dart';

/// Full-screen overlay that surfaces whenever there is a live WebRTC voice
/// call (incoming ringing, outgoing, connecting, or connected).
///
/// Inserted once at the root of the app shell so any screen automatically
/// gets the ringer + in-call sheet without each route opting in.
class VoiceCallOverlay extends ConsumerWidget {
  const VoiceCallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(webRtcVoiceCallServiceProvider);
    final notifier = ref.read(webRtcVoiceCallServiceProvider.notifier);

    if (state.phase == VoiceCallPhase.idle) {
      return const SizedBox.shrink();
    }
    if (state.phase == VoiceCallPhase.ended) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Material(
        color: const Color(0xFF080A0D),
        child: SafeArea(
          child: _CallView(state: state, notifier: notifier),
        ),
      ),
    );
  }
}

class _CallView extends StatelessWidget {
  const _CallView({required this.state, required this.notifier});

  final VoiceCallState state;
  final WebRtcVoiceCallService notifier;

  @override
  Widget build(BuildContext context) {
    final isIncoming = state.phase == VoiceCallPhase.incoming;
    final connected = state.phase == VoiceCallPhase.connected;
    final phaseLabel = switch (state.phase) {
      VoiceCallPhase.incoming => 'INCOMING CALL',
      VoiceCallPhase.outgoing => 'CALLING…',
      VoiceCallPhase.connecting => 'CONNECTING…',
      VoiceCallPhase.connected => 'IN CALL',
      VoiceCallPhase.error => 'ERROR',
      _ => '',
    };
    final emergencyTint = state.isEmergency
        ? const Color(0xFFE8281A)
        : const Color(0xFF00B8A0);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: emergencyTint,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              state.isEmergency ? 'ROADSOS · EMERGENCY' : 'ROADSOS · CIRCLE',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 28),
          CircleAvatar(
            radius: 64,
            backgroundColor: emergencyTint.withValues(alpha: 0.18),
            child: Icon(
              connected ? Icons.headset_mic : Icons.call,
              color: emergencyTint,
              size: 56,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            state.peerName ?? 'Family member',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            phaseLabel,
            style: const TextStyle(
              color: Colors.white60,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF9494), fontSize: 13),
            ),
          ],
          const Spacer(),
          if (connected || state.phase == VoiceCallPhase.connecting) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _circleAction(
                  icon: state.muted ? Icons.mic_off : Icons.mic,
                  label: state.muted ? 'UNMUTE' : 'MUTE',
                  bg: state.muted
                      ? const Color(0xFFE8281A)
                      : const Color(0xFF1F2933),
                  onTap: () async {
                    await HapticFeedback.selectionClick();
                    await notifier.setMuted(!state.muted);
                  },
                ),
                _circleAction(
                  icon: state.speakerOn ? Icons.volume_up : Icons.volume_down,
                  label: state.speakerOn ? 'SPEAKER' : 'EARPIECE',
                  bg: state.speakerOn
                      ? const Color(0xFF00B8A0)
                      : const Color(0xFF1F2933),
                  onTap: () async {
                    await HapticFeedback.selectionClick();
                    await notifier.toggleSpeaker(!state.speakerOn);
                  },
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
          Row(
            mainAxisAlignment: isIncoming
                ? MainAxisAlignment.spaceEvenly
                : MainAxisAlignment.center,
            children: [
              if (isIncoming)
                _bigAction(
                  icon: Icons.call_end,
                  label: 'DECLINE',
                  color: const Color(0xFFE8281A),
                  onTap: () async {
                    await HapticFeedback.mediumImpact();
                    await notifier.hangup(reason: 'declined');
                  },
                ),
              if (isIncoming)
                _bigAction(
                  icon: Icons.call,
                  label: 'ANSWER',
                  color: const Color(0xFF00B8A0),
                  onTap: () async {
                    await HapticFeedback.heavyImpact();
                    await notifier.answer();
                  },
                )
              else
                _bigAction(
                  icon: Icons.call_end,
                  label: 'HANG UP',
                  color: const Color(0xFFE8281A),
                  onTap: () async {
                    await HapticFeedback.mediumImpact();
                    await notifier.hangup();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String label,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkResponse(
          onTap: onTap,
          radius: 44,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _bigAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          InkResponse(
            onTap: onTap,
            radius: 60,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
