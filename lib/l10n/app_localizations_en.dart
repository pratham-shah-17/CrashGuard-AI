// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CrashGuard AI';

  @override
  String get dashboardTitle => 'CrashGuard AI';

  @override
  String get sosButton => 'SOS';

  @override
  String get secondsLabel => 'SECONDS';

  @override
  String get sosDispatchWarning =>
      'Nothing has been sent yet. Cancel now if this was a mistake.';

  @override
  String get sosIdleTools => 'More';

  @override
  String get sosIdleToolsTitle => 'Emergency tools & status';

  @override
  String get sosButtonSub => 'Press to start emergency';

  @override
  String get cancelSos => 'CANCEL SOS';

  @override
  String get orchestratorBystanderStarted => 'Bystander alert started';

  @override
  String get orchestratorSelfSosStarted => 'Self SOS started';

  @override
  String get orchestratorAcquiringLocation => 'Getting your location…';

  @override
  String orchestratorLocationSecured(String lat, String lng) {
    return 'Location: $lat, $lng';
  }

  @override
  String get orchestratorLocationUnavailable =>
      'Location unavailable — enable location services or move to open sky.';

  @override
  String get orchestratorManualActionRequired =>
      'Manual action required — if automated dispatch fails, dial your emergency number now.';

  @override
  String get orchestratorSmsNoGpsPayload =>
      'SOS (no GPS). Please call emergency services now. CrashGuard AI could not acquire location.';

  @override
  String get orchestratorAiBrief => 'Cloud AI is assessing the situation…';

  @override
  String orchestratorTriageDone(int level) {
    return 'Triage complete — severity $level';
  }

  @override
  String get orchestratorDispatching =>
      'Trying SMS, mesh beacon, and on-device log…';

  @override
  String get orchestratorSosLive => 'SOS live — all channels active';

  @override
  String get orchestratorCancelled => 'SOS cancelled';

  @override
  String get mapPlaceholder => 'Map';

  @override
  String get actionScene => 'SCENE';

  @override
  String get actionMedicalId => 'MEDICAL ID';

  @override
  String get actionResponder => 'RESPONDER';

  @override
  String get actionSafeWalk => 'SAFE-WALK';

  @override
  String get actionFirstAid => 'FIRST AID';

  @override
  String get actionVitalScan => 'VITAL SCAN';

  @override
  String get actionMeshChat => 'MESH CHAT';

  @override
  String get actionSettings => 'SETTINGS';

  @override
  String get triageResultTitle => 'AI TRIAGE RESULT';

  @override
  String get triageDegradedTitle => 'AI TRIAGE (OFFLINE)';

  @override
  String severityLine(int level, String label) {
    return 'Severity $level/5 — $label';
  }

  @override
  String get severityCritical => 'CRITICAL';

  @override
  String get severitySevere => 'SEVERE';

  @override
  String get severityModerate => 'MODERATE';

  @override
  String get severityMinor => 'MINOR';

  @override
  String get severityLow => 'LOW';

  @override
  String get severityUnknown => 'UNKNOWN';

  @override
  String get dispatchedServices => 'DISPATCHED SERVICES';

  @override
  String get firstAidGuidance => 'FIRST AID GUIDANCE';

  @override
  String get noAiBadge => 'OFFLINE';

  @override
  String get settingsTitle => 'SETTINGS';

  @override
  String get sectionConnectivity => 'CONNECTIVITY';

  @override
  String get sectionLegal => 'LEGAL & DATA';

  @override
  String get offlineMapsTitle => 'Offline maps';

  @override
  String get offlineMapsSubtitle => 'Download and manage regional tiles';

  @override
  String get meshConfigTitle => 'Mesh configuration';

  @override
  String get meshConfigSubtitle => 'Broadcast sensitivity and node visibility';

  @override
  String get blackBoxTitle => 'Black box report';

  @override
  String get blackBoxSubtitle => 'Export signed telemetry and triage logs';

  @override
  String get blackBoxSnack => 'Generating signed black box PDF…';

  @override
  String get dataPrivacyTitle => 'Data privacy';

  @override
  String get dataPrivacySubtitle => 'Manage local encryption and cloud sync';

  @override
  String get vitalScanTitle => 'Vital scan';

  @override
  String get vitalAlignFinger =>
      'Align index finger with rear camera and flash for PPG reading.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'UI, triage prompts, and voice output';

  @override
  String get incidentAssistantAnalyzed =>
      'Scene note: frontal impact logged. Check for smoke or fire.';

  @override
  String get incidentVoiceHint => 'Describe what you see…';

  @override
  String get profileAiLine =>
      'Medical profile helps first aid prompts during SOS.';

  @override
  String get thinkingOffline => 'Offline rules (no cloud).';

  @override
  String get sttConfirmKeywords => 'You can say yes, confirm, or help.';

  @override
  String get consentTitle => 'Welcome to CrashGuard AI';

  @override
  String get consentSummary =>
      'This app processes location, motion/crash signals, and optional medical profile data to coordinate emergency help. Under India’s Digital Personal Data Protection Act, 2023, we need your informed consent before continuing. Cloud incident summaries are retained for 90 days unless you opt in below.';

  @override
  String get consentExtendedRetentionLabel =>
      'Keep anonymised cloud incident copies longer than 90 days for safety research (optional)';

  @override
  String get consentAccept => 'I agree — continue';

  @override
  String get consentPrivacyButton => 'Privacy notice';

  @override
  String get privacyPolicyTitle => 'Privacy notice';

  @override
  String get privacyPolicyLanguageEn => 'English';

  @override
  String get privacyPolicyLanguageHi => 'हिंदी';

  @override
  String get goodSamaritanTitle => 'Good Samaritan protection';

  @override
  String get goodSamaritanLead =>
      'You are legally protected when helping in good faith.';

  @override
  String get goodSamaritanBody =>
      'India’s Good Samaritan framework (including the 2016 Supreme Court guidelines) discourages harassment of bystanders who assist road accident victims. Helping promptly can save lives.';

  @override
  String get goodSamaritanContinue => 'Understood';

  @override
  String get nearbySosSectionTitle => 'Nearby SOS';

  @override
  String get nearbySosToggleTitle => 'Nearby SOS push alerts';

  @override
  String get nearbySosToggleSubtitle =>
      'Firebase Cloud Messaging — notify me when someone nearby needs help';

  @override
  String get nearbySosLearnProtection => 'Good Samaritan protection';

  @override
  String get aiThinkingTraceTitle => 'TRIAGE REASONING';

  @override
  String get crisisCompanionTitle => 'CRISIS ASSISTANT';

  @override
  String get crisisCompanionBreathing =>
      'Breathe steadily. Monitoring your situation.';

  @override
  String get sceneIntelligenceTitle => 'SCENE INTELLIGENCE';

  @override
  String get helpEtaPlaceholder => 'No ETA available';

  @override
  String get talkButton => 'TALK';

  @override
  String get settingsExtendedRetentionTitle => 'Extended cloud retention';

  @override
  String get settingsExtendedRetentionSubtitle =>
      'Keep incident summaries beyond 90 days when synced to Supabase (overrides default purge).';
}
