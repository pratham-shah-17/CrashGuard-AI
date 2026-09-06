import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:roadsos/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/app_locale_controller.dart';
import '../services/hardware_trigger_service.dart';
import '../services/nearby_sos_preferences.dart';
import '../services/nearby_sos_push_service.dart';
import '../services/privacy_consent_service.dart';
import 'good_samaritan_law_screen.dart';
import 'offline_map_screen.dart';
import 'permission_onboarding_screen.dart';
import '../services/emergency_orchestrator.dart';
import 'privacy_policy_screen.dart';
import 'sos_activity_log_screen.dart';
import 'mesh_chat_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _nearbySos = false;
  bool _extendedRetention = false;
  bool _loaded = false;

  static String _languageLabel(AppLocalizations l10n, String code) {
    switch (code) {
      case 'hi':
        return 'हिन्दी';
      case 'ta':
        return 'தமிழ்';
      case 'te':
        return 'తెలుగు';
      case 'bn':
        return 'বাংলা';
      case 'mr':
        return 'मराठी';
      default:
        return 'English';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await NearbySosPreferences.pushOptIn();
    final e = await PrivacyConsentService.extendedCloudRetentionEnabled();
    if (mounted) {
      setState(() {
        _nearbySos = n;
        _extendedRetention = e;
        _loaded = true;
      });
    }
  }

  Future<void> _onNearbySosChanged(bool value) async {
    if (value) {
      final seen = await NearbySosPreferences.goodSamaritanSeen();
      if (!seen && mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const GoodSamaritanLawScreen(),
          ),
        );
        await NearbySosPreferences.setGoodSamaritanSeen(true);
      }
    }
    setState(() => _nearbySos = value);
    final ok = await NearbySosPushService.instance.onOptInChanged(value);
    if (!ok && mounted) {
      setState(() => _nearbySos = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nearby SOS needs Firebase setup (google-services.json / FirebaseOptions). Toggle turned off.',
          ),
        ),
      );
    }
  }

  Future<void> _onRetentionChanged(bool value) async {
    setState(() => _extendedRetention = value);
    await PrivacyConsentService.setExtendedCloudRetention(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = ref.watch(appLocaleProvider);

    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          l10n.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionHeader(context, l10n.sectionConnectivity),
          _tile(
            context,
            Icons.language,
            l10n.settingsLanguage,
            l10n.settingsLanguageSubtitle,
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: locale.languageCode,
                dropdownColor: Colors.grey.shade900,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: kSupportedAppLocales
                    .map(
                      (l) => DropdownMenuItem<String>(
                        value: l.languageCode,
                        child: Text(_languageLabel(l10n, l.languageCode)),
                      ),
                    )
                    .toList(),
                onChanged: (code) {
                  if (code == null) return;
                  ref.read(appLocaleProvider.notifier).setLocale(Locale(code));
                },
              ),
            ),
          ),
          _tile(
            context,
            Icons.fact_check_outlined,
            'Activity log',
            'GPS, triage, SMS/mesh/cloud steps — for insurance or police records',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const SosActivityLogScreen(),
              ),
            ),
          ),
          _tile(
            context,
            Icons.map,
            l10n.offlineMapsTitle,
            l10n.offlineMapsSubtitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OfflineMapScreen()),
            ),
          ),
          _tile(
            context,
            Icons.app_shortcut,
            'Review permissions',
            'Open the setup walkthrough again',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => PermissionOnboardingScreen(
                  onComplete: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          _tile(
            context,
            Icons.bluetooth,
            l10n.meshConfigTitle,
            l10n.meshConfigSubtitle,
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
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const MeshChatScreen()),
              );
            },
          ),
          if (!kIsWeb && Platform.isAndroid) ...[
            const SizedBox(height: 8),
            _tile(
              context,
              Icons.hearing_disabled_outlined,
              'Background volume SOS',
              'Open Accessibility and enable RoadSOS for lock-screen gesture (3× up + 3× down)',
              onTap: () => ref
                  .read(hardwareTriggerServiceProvider)
                  .openAndroidAccessibilitySettings(),
            ),
          ],
          const SizedBox(height: 32),
          _sectionHeader(context, l10n.nearbySosSectionTitle),
          SwitchListTile(
            value: _nearbySos,
            onChanged: _onNearbySosChanged,
            secondary: const Icon(
              Icons.notifications_active,
              color: Colors.white70,
            ),
            title: Text(
              l10n.nearbySosToggleTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              l10n.nearbySosToggleSubtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.balance, color: Colors.greenAccent),
            title: Text(
              l10n.nearbySosLearnProtection,
              style: const TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const GoodSamaritanLawScreen(),
              ),
            ),
          ),
          const SizedBox(height: 32),
          _sectionHeader(context, l10n.sectionLegal),
          SwitchListTile(
            value: _extendedRetention,
            onChanged: _onRetentionChanged,
            secondary: const Icon(Icons.cloud_queue, color: Colors.white70),
            title: Text(
              l10n.settingsExtendedRetentionTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              l10n.settingsExtendedRetentionSubtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.38),
                fontSize: 12,
              ),
            ),
          ),
          _tile(
            context,
            Icons.description,
            l10n.blackBoxTitle,
            l10n.blackBoxSubtitle,
            onTap: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.blackBoxSnack)));
            },
          ),
          _tile(
            context,
            Icons.privacy_tip,
            l10n.dataPrivacyTitle,
            l10n.dataPrivacySubtitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.blue.withValues(alpha: 0.6),
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing:
          trailing ?? const Icon(Icons.chevron_right, color: Colors.white24),
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    );
  }
}
