import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsos/l10n/app_localizations.dart';

import 'database/app_database.dart';
import 'services/first_aid_repository.dart';
import 'services/hardware_trigger_service.dart';
import 'services/ios_lifecycle_service.dart';
import 'services/emergency_orchestrator.dart';
import 'services/map_tile_cache.dart';
import 'services/mesh_network_service.dart';
import 'services/app_locale_controller.dart';
import 'services/connectivity_service.dart';
import 'services/driving_mode_service.dart';
import 'services/emergency_background_service.dart';
import 'services/agent_health_service.dart';
import 'services/bluetooth_vehicle_monitor.dart';
import 'services/inactivity_crash_detector.dart';
import 'services/predictive_sos_preloader.dart';
import 'services/sos_location_tracker.dart';
import 'ui/dashboard.dart';
import 'ui/consent_screen.dart';
import 'ui/onboarding_gate.dart';
import 'ui/voice_call_overlay.dart';
import 'services/gemma_auto_downloader.dart';
import 'services/webrtc_voice_call_service.dart';
import 'ui/roadsos_logo.dart';
import 'services/privacy_consent_service.dart';
import 'services/nearby_sos_push_service.dart';
import 'app_navigator.dart';
import 'theme/roadsos_theme.dart';
import 'config/runtime_config.dart';
import 'services/remote_crash_config.dart';
import 'logging/app_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// main() — the only work done here is loading runtime config (fast asset read,
// ~50-100 ms, no network).  runApp() is called immediately so the first
// Flutter frame renders before any heavy I/O begins.
//
// All heavy work (Supabase auth, SQLite/PowerSync, ObjectBox, FTS5 seeding,
// notification channels) moves to _RoadSOSAppState._bootstrapServices() and
// runs concurrently with the first paint — never blocking the UI thread.
// ─────────────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers — ensure crashes show visible UI, never black screen ──
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    appLog.e('[flutter-error] ${details.exception}', stackTrace: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appLog.e('[platform-error] $error', stackTrace: stack);
    return true; // mark handled — prevents crash-to-black-screen
  };

  // ── ErrorWidget: show a red-banner instead of a blank screen on build errors ──
  if (!kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Build error:\n${details.exception}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      );
    };
  }

  // RuntimeConfig reads --dart-define values and, in dev, loads a local .env
  // file.  It also loads cached crash-thresholds from SharedPreferences.
  // This is fast (~50-100 ms, no network) and must complete before any service
  // reads its configuration keys.
  try {
    await RuntimeConfig.bootstrap();
  } on Object catch (e, st) {
    // Non-fatal: all services check for missing config and degrade gracefully.
    appLog.w(
      '[boot] RuntimeConfig.bootstrap() failed — proceeding without config',
      error: e,
      stackTrace: st,
    );
  }

  // ← First frame renders here.  The loading spinner in _RoadSOSAppState is
  //   visible within 16 ms.  No user ever sees a black screen again.
  runApp(const ProviderScope(child: RoadSOSApp()));
}

// ─────────────────────────────────────────────────────────────────────────────
// Root application widget
// ─────────────────────────────────────────────────────────────────────────────
class RoadSOSApp extends ConsumerStatefulWidget {
  const RoadSOSApp({super.key});

  @override
  ConsumerState<RoadSOSApp> createState() => _RoadSOSAppState();
}

class _RoadSOSAppState extends ConsumerState<RoadSOSApp>
    with WidgetsBindingObserver {
  bool _privacyReady = false;
  bool _privacyConsent = false;

  // Whether heavy services have finished bootstrapping.
  // Used to ensure post-consent hooks (crash monitor, push) only fire after
  // EmergencyBackgroundService.initialize() has completed.
  bool _servicesReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Run privacy check and heavy service bootstrap concurrently.
    // Privacy check resolves in ~50 ms (SharedPreferences); services take
    // 1–3 seconds.  Both are non-blocking from the UI's perspective.
    _checkPrivacy();
    _bootstrapServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(RemoteCrashConfig.instance.onAppForeground());
    }
  }

  // ── Privacy check (~50 ms) ────────────────────────────────────────────────

  Future<void> _checkPrivacy() async {
    try {
      final accepted = await PrivacyConsentService.hasConsent();
      if (!mounted) return;
      setState(() {
        _privacyConsent = accepted;
        _privacyReady = true;
      });
      // Post-consent hooks depend on services being ready too; if services
      // finished first, call hooks now; otherwise _onServicesReady() handles it.
      if (_servicesReady && accepted) {
        _runPostConsentHooks();
      }
    } on Object catch (e, st) {
      appLog.e('[boot] Privacy check failed', error: e, stackTrace: st);
      if (mounted) setState(() => _privacyReady = true); // unblock UI
    }
  }

  // ── Heavy service bootstrap (1–3 s, runs post-frame) ─────────────────────

  Future<void> _bootstrapServices() async {
    try {
      // Phase 1: Auth — must complete before database (PowerSync needs a JWT).
      await bootstrapSupabaseAuth();

      // Phase 2: Database — must complete before first-aid FTS seeding.
      await initializeDatabase();

      // Phase 3: Parallel independent init (saves ~400–700 ms vs serial).
      await Future.wait<void>([
        initializeFirstAidRepository(),
        initializeFmtcMapCache(),
        EmergencyBackgroundService.initialize().then(
          (_) => EmergencyBackgroundService.ensureNotificationChannel(),
        ),
      ]);

      // Phase 4: Kick off remote crash-config fetch (non-blocking).
      unawaited(
        RemoteCrashConfig.instance.refresh().then((_) {
          RemoteCrashConfig.instance.startPeriodicRefresh();
        }),
      );

      appLog.i('[boot] All services bootstrapped successfully.');
    } on Object catch (e, st) {
      // Non-fatal: app runs in offline/degraded mode.
      appLog.e(
        '[boot] Service bootstrap error — running in degraded mode',
        error: e,
        stackTrace: st,
      );
    } finally {
      if (mounted) {
        setState(() => _servicesReady = true);
        _onServicesReady();
      }
    }
  }

  void _onServicesReady() {
    // Only fire post-consent hooks after BOTH privacy consent is obtained
    // AND EmergencyBackgroundService.initialize() has completed.
    if (_privacyConsent) {
      _runPostConsentHooks();
    }
  }

  void _runPostConsentHooks() {
    NearbySosPushService.instance.configureAfterConsentIfNeeded();
    EmergencyBackgroundService.startCrashMonitor();
    EmergencyBackgroundService.requestBatteryOptimizationExemption();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(hardwareTriggerServiceProvider);
    ref.watch(iosLifecycleServiceProvider);
    ref.watch(meshListeningBootstrapProvider);
    ref.watch(connectivityServiceProvider);
    ref.watch(drivingModeProvider);

    ref.watch(agentHealthServiceProvider).startPolling();
    ref.watch(bluetoothVehicleMonitorProvider);
    ref.watch(inactivityCrashDetectorProvider);
    ref.watch(sosLocationTrackerProvider);
    // Keeps the WebRTC ringer subscribed for incoming Family Circle calls.
    ref.watch(webRtcVoiceCallServiceProvider);
    // Kicks off the Gemma-4 background download on first WiFi (silent, no
    // token, ungated). Without this watch the provider is lazy and the
    // 2.4 GB download never starts until the user opens Bystander Coach.
    ref.watch(gemmaAutoDownloaderProvider);

    final sosPhase = ref.watch(
      emergencyOrchestratorProvider.select((s) => s.phase),
    );
    final appLocale = ref.watch(appLocaleProvider);

    ref.listen(appLocaleProvider, (_, next) {
      ref.read(voiceAssistantServiceProvider).syncLocale(next);
    });

    ref.listen(drivingModeProvider, (prev, mode) {
      EmergencyBackgroundService.notifyDrivingMode(
        active: mode == DrivingMode.driving,
      );
      if (mode == DrivingMode.driving && prev != DrivingMode.driving) {
        unawaited(PredictiveSosPreloader.onDrivingModeActivated());
      }
    });

    final theme = sosPhase == SOSPhase.idle
        ? RoadSosTheme.buildOperationalDark()
        : RoadSosTheme.buildEmergencyDark();

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      locale: appLocale,
      supportedLocales: kSupportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      // Wraps every route with a Stack so the WebRTC call overlay can render
      // above whatever screen the user is on without each route opting in.
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const VoiceCallOverlay(),
          ],
        );
      },
      home: _home(),
    );
  }

  Widget _home() {
    // Show a branded splash while the privacy-check future resolves (~50 ms).
    // This is what the user sees instead of a black screen.
    if (!_privacyReady) {
      return const _SplashScreen();
    }
    if (!_privacyConsent) {
      return ConsentScreen(
        onAccepted: () {
          setState(() => _privacyConsent = true);
          // Services are almost certainly ready by the time consent is granted
          // (the consent screen requires reading and scrolling); call hooks directly.
          if (_servicesReady) {
            _runPostConsentHooks();
          }
        },
      );
    }
    return const OnboardingGate(
      child: _InitialTtsSync(child: DashboardScreen()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen shown for the ~50 ms before the privacy-check resolves.
// Replaces the black screen / Flutter-logo period completely.
// ─────────────────────────────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo mark
            _LogoMark(),
            SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFE8281A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RoadSOSLogo(size: 96),
        const SizedBox(height: 16),
        const Text(
          'CrashGuard AI',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Emergency response · Powered by Gemma 4',
          style: TextStyle(
            color: Color(0x99FFFFFF),
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One-shot TTS locale alignment on startup.
// ─────────────────────────────────────────────────────────────────────────────
class _InitialTtsSync extends ConsumerStatefulWidget {
  const _InitialTtsSync({required this.child});

  final Widget child;

  @override
  ConsumerState<_InitialTtsSync> createState() => _InitialTtsSyncState();
}

class _InitialTtsSyncState extends ConsumerState<_InitialTtsSync> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locale = ref.read(appLocaleProvider);
      ref.read(voiceAssistantServiceProvider).syncLocale(locale);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
