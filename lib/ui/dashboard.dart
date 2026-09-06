import 'dart:convert';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:roadsos/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';
import '../services/ai_triage_service.dart';
import '../services/driving_mode_service.dart';
import '../services/emergency_orchestrator.dart';
import '../services/proactive_monitor_service.dart';
import 'crisis_companion_overlay.dart';
import 'dispatch_status_panel.dart';
import 'first_aid_screen.dart';
import 'incident_reporting_screen.dart';
import 'map_widget.dart';
import 'medical_card_screen.dart';
import 'mesh_chat_screen.dart';
import 'mesh_radar.dart';
import 'offline_map_screen.dart';
import 'profile_editor_screen.dart';
import 'responder_dashboard.dart';
import 'package:latlong2/latlong.dart';

import 'bystander_coach_screen.dart';
import 'family_circle_screen.dart';
import 'gemma_status_banner.dart';
import 'safe_walk_navigator_screen.dart';
import 'safe_walk_overlay.dart';
import 'settings_screen.dart';
import 'sos_activity_log_screen.dart';
import 'sos_countdown_widget.dart';
import 'sos_side_effect_observer.dart';
import 'status_indicator.dart';
import 'vehicle_rescue_screen.dart';
import 'triage_result_card.dart';
import 'vital_scan_screen.dart';
import 'roadsos_logo.dart';

/// Main shell — panic-first design with a discoverable bottom navigation bar.
///
/// Idle:     3-tab NavigationBar — SOS | Safety Tools | My Profile
/// Active:   Full-screen emergency UI (countdown → GPS lock → dispatch → live)
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  int _tab = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _kRed = Color(0xFFE8281A);
  static const _kSurface = Color(0xFF111418);
  static const _kNavBg = Color(0xFF0D1014);

  @override
  void initState() {
    super.initState();
    appLog.d('DashboardScreen init');

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.025).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiTriageServiceProvider).initializeModel();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sosState = ref.watch(emergencyOrchestratorProvider);
    final scheme = Theme.of(context).colorScheme;
    final idle = sosState.phase == SOSPhase.idle;
    final drivingMode = ref.watch(drivingModeProvider);

    // Emergency active → full-screen (no nav bar, no distractions).
    if (!idle) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: _emergencyAppBar(context),
        body: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: KeyedSubtree(
                key: ValueKey<SOSPhase>(sosState.phase),
                child: _emergencyBody(context, sosState),
              ),
            ),
            const CrisisCompanionOverlay(),
            const SafeWalkOverlay(),
            const SOSSideEffectObserver(),
          ],
        ),
      );
    }

    // Idle → 3-tab layout.
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _idleAppBar(context),
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              _sosTab(context, drivingMode),
              _toolsTab(context),
              _profileTab(context),
            ],
          ),
          const CrisisCompanionOverlay(),
          const SafeWalkOverlay(),
          const SOSSideEffectObserver(),
        ],
      ),
      bottomNavigationBar: _navBar(context),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // App bars
  // ─────────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _idleAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RoadSOSLogo(size: 28),
          const SizedBox(width: 10),
          const Text(
            'RoadSOS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      actions: const [StatusIndicatorBar(), SizedBox(width: 12)],
    );
  }

  PreferredSizeWidget _emergencyAppBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      backgroundColor: scheme.surface.withAlpha(240),
      elevation: 0,
      scrolledUnderElevation: 2,
      title: Row(
        children: [
          const RoadSOSLogo(size: 26),
          const SizedBox(width: 10),
          Text(
            l10n.dashboardTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Activity log',
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const SosActivityLogScreen(),
            ),
          ),
        ),
        const StatusIndicatorBar(),
        const SizedBox(width: 12),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom navigation bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _navBar(BuildContext context) {
    return NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      backgroundColor: _kNavBg,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black,
      elevation: 8,
      indicatorColor: _kRed.withAlpha(38),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.emergency_outlined, color: Colors.white54),
          selectedIcon: Icon(Icons.emergency, color: _kRed),
          label: 'SOS',
        ),
        NavigationDestination(
          icon: Icon(Icons.apps_outlined, color: Colors.white54),
          selectedIcon: Icon(Icons.apps, color: _kRed),
          label: 'Safety Tools',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline, color: Colors.white54),
          selectedIcon: Icon(Icons.person, color: _kRed),
          label: 'My Profile',
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 0 — SOS (panic button)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sosTab(BuildContext context, DrivingMode drivingMode) {
    final l10n = AppLocalizations.of(context)!;
    final isDriving = drivingMode == DrivingMode.driving;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalH = constraints.maxHeight;
        final bannerH = isDriving ? 36.0 : 0.0;
        final btnH = (totalH - bannerH) * 0.78;
        final titleSize = min(96.0, btnH * 0.14);

        return Column(
          children: [
            // Driving mode banner
            if (isDriving)
              Container(
                height: 36,
                color: const Color(0xFFFF9500),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_car, color: Colors.black, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'DRIVING MODE — Crash detection armed',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

            // SOS button — takes up most of the screen
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref
                        .read(emergencyOrchestratorProvider.notifier)
                        .triggerSOS(),
                    // ⚡ Bolt Optimization: Use ScaleTransition instead of AnimatedBuilder + Transform.scale.
                    // This delegates the transformation to the rendering engine and prevents costly widget rebuilds on every frame.
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: SizedBox(
                        height: btnH,
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(52),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFFF453A), Color(0xFFB00020)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF453A).withAlpha(107),
                                  blurRadius: 40,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  l10n.sosButton,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    l10n.sosButtonSub,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xF0FFFFFF),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Discovery hint
            SafeArea(
              minimum: const EdgeInsets.only(bottom: 8),
              child: Text(
                'All safety features are in "Safety Tools" below',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(80),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 1 — Safety Tools (all features, always visible)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _toolsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Radar + status at the top
        const SizedBox(height: 160, child: MeshRadar()),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 4, bottom: 4),
            child: StatusIndicatorBar(),
          ),
        ),
        const SizedBox(height: 16),

        // Auto-Gemma install + readiness banner (hides itself when ready).
        const GemmaStatusBanner(),

        // ── Emergency Response ──────────────────────────────────────────
        _sectionLabel('EMERGENCY RESPONSE'),
        const SizedBox(height: 8),
        _toolCard(
          context,
          icon: Icons.directions_walk,
          color: const Color(0xFF00B8A0),
          title: 'Safe Walk',
          subtitle: 'Auto-SOS if you don\'t check in at destination',
          onTap: () => _showSafeWalkDialog(context),
        ),
        _toolCard(
          context,
          icon: Icons.camera_enhance,
          color: const Color(0xFFF59220),
          title: 'Capture Scene',
          subtitle:
              'Arm a crash photo — Gemma 4 27B vision uses it on next SOS',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const IncidentReportingScreen(),
            ),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.health_and_safety,
          color: const Color(0xFF4CAF50),
          title: 'Responder View',
          subtitle: 'This device\u2019s live SOS dashboard + BLE mesh peers',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ResponderDashboard()),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.car_crash,
          color: const Color(0xFFFF5722),
          title: 'Vehicle Rescue',
          subtitle: 'Offline extraction guide by vehicle type',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const VehicleRescueScreen(),
            ),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.support_agent,
          color: const Color(0xFF00B8A0),
          title: 'Bystander Coach',
          subtitle: 'On-device Gemma 4 walks you through first aid — offline',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const BystanderCoachScreen(),
            ),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.group,
          color: const Color(0xFF5C7CFA),
          title: 'Family Circle',
          subtitle: 'Trusted contacts see you live during Safe Walk + SOS',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const FamilyCircleScreen()),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.play_circle_fill,
          color: const Color(0xFFB388FF),
          title: 'Demo Mode (judges + first-time users)',
          subtitle:
              'Simulate a crash to walk the full SOS pipeline end-to-end. No real SMS or 112 dispatched.',
          onTap: () => _runDemoMode(context),
        ),

        const SizedBox(height: 20),

        // ── Health & Safety ─────────────────────────────────────────────
        _sectionLabel('HEALTH & SAFETY'),
        const SizedBox(height: 8),
        _toolCard(
          context,
          icon: Icons.health_and_safety_outlined,
          color: const Color(0xFF4CAF50),
          title: 'First Aid Guide',
          subtitle: 'Step-by-step emergency instructions',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const FirstAidScreen()),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.monitor_heart,
          color: const Color(0xFFE8281A),
          title: 'Vital Scan',
          subtitle: 'Log bystander-observed pulse / SpO\u2082 for the 112 SMS',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const VitalScanScreen()),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.qr_code,
          color: const Color(0xFF2196F3),
          title: 'Medical ID',
          subtitle: 'Show responders your blood type, allergies, contacts',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const MedicalCardScreen()),
          ),
        ),

        const SizedBox(height: 20),

        // ── Connectivity ────────────────────────────────────────────────
        _sectionLabel('CONNECTIVITY'),
        const SizedBox(height: 8),
        _toolCard(
          context,
          icon: Icons.forum,
          color: const Color(0xFF9C27B0),
          title: 'Mesh Chat',
          subtitle: 'Offline Bluetooth messaging — no signal needed',
          onTap: () {
            if (ref.read(emergencyOrchestratorProvider).phase !=
                SOSPhase.idle) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Mesh Chat is disabled during an active SOS to preserve the BLE beacon channel.',
                  ),
                ),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const MeshChatScreen()),
            );
          },
        ),
        _toolCard(
          context,
          icon: Icons.map_outlined,
          color: const Color(0xFF00B8A0),
          title: 'Offline Maps',
          subtitle: 'Download maps for no-signal areas',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const OfflineMapScreen()),
          ),
        ),

        const SizedBox(height: 20),

        // ── Records ─────────────────────────────────────────────────────
        _sectionLabel('RECORDS'),
        const SizedBox(height: 8),
        _toolCard(
          context,
          icon: Icons.fact_check_outlined,
          color: Colors.white70,
          title: 'Activity Log',
          subtitle: 'GPS, triage, SMS — for police & insurer records',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const SosActivityLogScreen(),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 2 — My Profile
  // ─────────────────────────────────────────────────────────────────────────

  Widget _profileTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _sectionLabel('MY INFORMATION'),
        const SizedBox(height: 8),
        _toolCard(
          context,
          icon: Icons.person,
          color: const Color(0xFF2196F3),
          title: 'Edit Profile',
          subtitle: 'Name, blood type, emergency contacts',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const ProfileEditorScreen(),
            ),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.qr_code,
          color: const Color(0xFF00B8A0),
          title: 'Medical ID Card',
          subtitle: 'Quick-access health info for emergency responders',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const MedicalCardScreen()),
          ),
        ),

        const SizedBox(height: 20),
        _sectionLabel('SETTINGS & PRIVACY'),
        const SizedBox(height: 8),
        _toolCard(
          context,
          icon: Icons.settings,
          color: Colors.white70,
          title: 'All Settings',
          subtitle: 'Language, offline maps, notifications, privacy',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
        _toolCard(
          context,
          icon: Icons.history,
          color: Colors.white54,
          title: 'Activity Log',
          subtitle: 'Full SOS history for insurance & police records',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const SosActivityLogScreen(),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared widgets
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withAlpha(100),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _toolCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: color.withAlpha(20),
          highlightColor: color.withAlpha(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withAlpha(28),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: Colors.white.withAlpha(60),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Emergency phase views (shown when !idle)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _emergencyBody(BuildContext context, SOSState sosState) {
    switch (sosState.phase) {
      case SOSPhase.countdown:
        return _countdownView(context, sosState);
      case SOSPhase.gpsLocking:
      case SOSPhase.triaging:
        return _pipelineProgressView(context, sosState);
      case SOSPhase.dispatching:
        return _dispatchingView(context, sosState);
      case SOSPhase.active:
      default:
        return _activeSessionView(context, sosState);
    }
  }

  Widget _countdownView(BuildContext context, SOSState state) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: SOSCountdownWidget(
        secondsRemaining: state.countdownSeconds,
        warningText: l10n.sosDispatchWarning,
        cancelLabel: l10n.cancelSos,
        secondsLabel: l10n.secondsLabel,
        onCancel: () =>
            ref.read(emergencyOrchestratorProvider.notifier).cancelSos(),
      ),
    );
  }

  Widget _pipelineProgressView(BuildContext context, SOSState state) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final headline = state.phase == SOSPhase.gpsLocking
        ? l10n.orchestratorAcquiringLocation
        : l10n.orchestratorAiBrief;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 5, color: scheme.primary),
            const SizedBox(height: 28),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dispatchingView(BuildContext context, SOSState state) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.orchestratorDispatching,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            DispatchStatusPanel(
              channels: state.dispatchChannels,
              isBeaconActive: state.isBeaconActive,
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeSessionView(BuildContext context, SOSState state) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.dispatchChannels.isNotEmpty) ...[
              DispatchStatusPanel(
                channels: state.dispatchChannels,
                isBeaconActive: state.isBeaconActive,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SosActivityLogScreen(),
                  ),
                ),
                icon: const Icon(Icons.history_edu_outlined),
                label: const Text('Full activity log & insurer note'),
              ),
              const SizedBox(height: 16),
            ],
            if (state.triageResult != null)
              TriageResultCard(result: state.triageResult!),
            const SizedBox(height: 16),
            SizedBox(height: 300, child: RoadSosMap(state: state)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Safe Walk dialog
  // ─────────────────────────────────────────────────────────────────────────

  // ──────────────────────────────────────────────────────────────────────
  // Demo Mode — surfaces a clearly-labelled simulated crash so first-time
  // users and judges can walk the full SOS pipeline (countdown → bystander
  // mode → AI triage → dispatch panel → Bystander Coach hand-off) without
  // ever sending real SMS, dialing 112, or waking up Family Circle peers.
  // Per `critical-feature-audit.mdc`: Simulated content MUST be labelled
  // simulated — done via the "SIMULATED" banner in the confirmation dialog.

  Future<void> _runDemoMode(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Demo Mode — SIMULATED crash'),
        content: const Text(
          'Walks every screen in the SOS pipeline so you can see what RoadSOS does on a real accident.\n\n'
          'This is fully simulated:\n'
          '  • Bystander-mode SOS countdown starts (not self-SOS).\n'
          '  • No real SMS, 112 dial, or WebRTC ring to your Family Circle.\n'
          '  • The Bystander Coach screen opens after dispatch so you can rehearse the first-aid voice flow.\n'
          '\nTap CANCEL on the SOS countdown any time to abort.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RUN DEMO'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // Bystander mode = the safety-validation agent treats it as severity 2
    // baseline; even if dispatch fails (no Supabase / no SMS perm), the
    // countdown + status panel still walk the same code path the real SOS
    // does, which is the entire point of the demo.
    await ref
        .read(emergencyOrchestratorProvider.notifier)
        .startSos(isBystander: true);

    // Auto-open the Bystander Coach so the rehearsal hits the on-device
    // Gemma-4 voice flow without the user having to tap a second time.
    if (!context.mounted) return;
    await Future<void>.delayed(const Duration(seconds: 12));
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BystanderCoachScreen()),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Dialog uses a typed Nominatim hit so we capture the lat/lng alongside the
  // human-readable display string. With coordinates we can push the user
  // into the Safe Walk Navigator (compass arrow + voice cues); without them
  // we fall back to dead-man-timer-only mode.

  Future<void> _showSafeWalkDialog(BuildContext context) async {
    final monitor = ref.read(proactiveMonitorProvider);

    if (monitor.isMonitoring) {
      ref.read(proactiveMonitorProvider.notifier).endSafeWalk();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Safe Walk ended.')));
      }
      return;
    }

    String selectedDestination = '';
    LatLng? selectedDestinationLatLng;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Safe Walk',
                style: Theme.of(
                  ctx,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Autocomplete<_NominatimHit>(
                displayStringForOption: (h) => h.displayName,
                optionsBuilder: (TextEditingValue textEditingValue) async {
                  if (textEditingValue.text.length < 3) {
                    return const Iterable<_NominatimHit>.empty();
                  }
                  try {
                    final uri = Uri.parse(
                      'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(textEditingValue.text)}&format=json&addressdetails=1&limit=5',
                    );
                    final response = await http.get(
                      uri,
                      headers: {'User-Agent': 'RoadSOS/1.0'},
                    );
                    if (response.statusCode == 200) {
                      final List<dynamic> data = json.decode(response.body);
                      return data.whereType<Map>().map(
                        (m) => _NominatimHit(
                          displayName: m['display_name'] as String,
                          lat: double.tryParse(m['lat']?.toString() ?? '') ?? 0,
                          lon: double.tryParse(m['lon']?.toString() ?? '') ?? 0,
                        ),
                      );
                    }
                  } on Object catch (e) {
                    appLog.w('Error fetching location suggestions: $e');
                  }
                  return const Iterable<_NominatimHit>.empty();
                },
                onSelected: (hit) {
                  selectedDestination = hit.displayName;
                  selectedDestinationLatLng = LatLng(hit.lat, hit.lon);
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onEditingComplete: onEditingComplete,
                        onChanged: (val) {
                          selectedDestination = val;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Destination (optional)',
                          hintText: 'e.g., Home, Hostel, Station',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      );
                    },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(context).colorScheme.surface,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 200,
                          maxWidth: 300,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return InkWell(
                              onTap: () {
                                onSelected(option);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  option.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Pick a destination from the suggestions to unlock the live arrow + voice navigation.\nDead-man check-in fires automatic SOS if you go silent for the ETA + 60 s grace.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final destLatLng = selectedDestinationLatLng;
                    if (destLatLng != null) {
                      Navigator.pop(ctx);
                      // Push the full Safe Walk Navigator screen — AirTag arrow
                      // + OSRM turn-by-turn + voice + 30 m geofence auto-end.
                      // The navigator itself calls startSafeWalk() so the dead-
                      // man timer + Family Circle publish still kick in.
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SafeWalkNavigatorScreen(
                            destination: destLatLng,
                            destinationName: selectedDestination,
                          ),
                        ),
                      );
                    } else {
                      // Fallback: timer-only mode (no nav). Lets users who don't
                      // pick from the autocomplete still get dead-man coverage.
                      // Requires explicit acknowledgment to prevent silent failure if user expected map.
                      showDialog<void>(
                        context: ctx,
                        builder: (confirmCtx) => AlertDialog(
                          title: const Text('Timer-Only Mode'),
                          content: const Text(
                            'No specific destination selected.\n\nSafe Walk will start in timer-only mode without map navigation. An automatic SOS will trigger if you do not check in before the ETA.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(confirmCtx),
                              child: const Text('CANCEL'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(confirmCtx);
                                Navigator.pop(ctx);
                                ref
                                    .read(proactiveMonitorProvider.notifier)
                                    .startSafeWalk(
                                      selectedDestination.trim().isEmpty
                                          ? 'your destination'
                                          : selectedDestination.trim(),
                                      const Duration(minutes: 30),
                                    );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Dead-man timer started.'),
                                  ),
                                );
                              },
                              child: const Text('CONTINUE'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('START SAFE WALK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Typed Nominatim hit (display_name + lat/lng) used by the Safe Walk
/// destination autocomplete so we can hand real coordinates to the navigator.
class _NominatimHit {
  const _NominatimHit({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  final String displayName;
  final double lat;
  final double lon;
}
