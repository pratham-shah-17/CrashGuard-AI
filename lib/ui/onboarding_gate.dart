import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'permission_onboarding_screen.dart';

const _kPermsDone = 'permissions_onboarding_v1_done';
const _kModelPromptDone = 'model_download_prompt_v1_done';

/// Two-phase onboarding gate:
///
/// Phase 1 — Permissions (location, bluetooth, camera, microphone, SMS, notifications)
/// Phase 2 — Gemma 4 E4B model download (~2.4 GB, skippable)
///   • Skipped automatically if the model is already downloaded
///   • Skipped if the user chooses "Skip — use cloud AI only"
///
/// After both phases (or skip), shows the main app.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  _GatePhase _phase = _GatePhase.loading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final permsDone = prefs.getBool(_kPermsDone) ?? false;

    if (!mounted) return;
    setState(() {
      _phase = permsDone ? _GatePhase.app : _GatePhase.permissions;
    });
  }

  Future<void> _onPermsDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPermsDone, true);
    // Mark the legacy "model download screen" as done so users on existing
    // installs skip the obsolete HF-token wall. The new
    // GemmaAutoDownloader takes over silently in the background.
    await prefs.setBool(_kModelPromptDone, true);
    if (!mounted) return;
    setState(() => _phase = _GatePhase.app);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _GatePhase.loading:
        return const Scaffold(
          backgroundColor: Color(0xFF080b12),
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF4a90d9)),
          ),
        );
      case _GatePhase.permissions:
        return PermissionOnboardingScreen(onComplete: _onPermsDone);
      case _GatePhase.app:
        return widget.child;
    }
  }
}

enum _GatePhase { loading, permissions, app }
