import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
    Locale('hi'),
    Locale('mr'),
    Locale('ta'),
    Locale('te'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'RoadSOS'**
  String get appTitle;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'RoadSOS'**
  String get dashboardTitle;

  /// No description provided for @sosButton.
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get sosButton;

  /// No description provided for @secondsLabel.
  ///
  /// In en, this message translates to:
  /// **'SECONDS'**
  String get secondsLabel;

  /// No description provided for @sosDispatchWarning.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been sent yet. Cancel now if this was a mistake.'**
  String get sosDispatchWarning;

  /// No description provided for @sosIdleTools.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get sosIdleTools;

  /// No description provided for @sosIdleToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency tools & status'**
  String get sosIdleToolsTitle;

  /// No description provided for @sosButtonSub.
  ///
  /// In en, this message translates to:
  /// **'Press to start emergency'**
  String get sosButtonSub;

  /// No description provided for @cancelSos.
  ///
  /// In en, this message translates to:
  /// **'CANCEL SOS'**
  String get cancelSos;

  /// No description provided for @orchestratorBystanderStarted.
  ///
  /// In en, this message translates to:
  /// **'Bystander alert started'**
  String get orchestratorBystanderStarted;

  /// No description provided for @orchestratorSelfSosStarted.
  ///
  /// In en, this message translates to:
  /// **'Self SOS started'**
  String get orchestratorSelfSosStarted;

  /// No description provided for @orchestratorAcquiringLocation.
  ///
  /// In en, this message translates to:
  /// **'Getting your location…'**
  String get orchestratorAcquiringLocation;

  /// No description provided for @orchestratorLocationSecured.
  ///
  /// In en, this message translates to:
  /// **'Location: {lat}, {lng}'**
  String orchestratorLocationSecured(String lat, String lng);

  /// No description provided for @orchestratorLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable — enable location services or move to open sky.'**
  String get orchestratorLocationUnavailable;

  /// No description provided for @orchestratorManualActionRequired.
  ///
  /// In en, this message translates to:
  /// **'Manual action required — if automated dispatch fails, dial your emergency number now.'**
  String get orchestratorManualActionRequired;

  /// No description provided for @orchestratorSmsNoGpsPayload.
  ///
  /// In en, this message translates to:
  /// **'SOS (no GPS). Please call emergency services now. RoadSOS could not acquire location.'**
  String get orchestratorSmsNoGpsPayload;

  /// No description provided for @orchestratorAiBrief.
  ///
  /// In en, this message translates to:
  /// **'Cloud AI is assessing the situation…'**
  String get orchestratorAiBrief;

  /// No description provided for @orchestratorTriageDone.
  ///
  /// In en, this message translates to:
  /// **'Triage complete — severity {level}'**
  String orchestratorTriageDone(int level);

  /// No description provided for @orchestratorDispatching.
  ///
  /// In en, this message translates to:
  /// **'Trying SMS, mesh beacon, and on-device log…'**
  String get orchestratorDispatching;

  /// No description provided for @orchestratorSosLive.
  ///
  /// In en, this message translates to:
  /// **'SOS live — all channels active'**
  String get orchestratorSosLive;

  /// No description provided for @orchestratorCancelled.
  ///
  /// In en, this message translates to:
  /// **'SOS cancelled'**
  String get orchestratorCancelled;

  /// No description provided for @mapPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get mapPlaceholder;

  /// No description provided for @actionScene.
  ///
  /// In en, this message translates to:
  /// **'SCENE'**
  String get actionScene;

  /// No description provided for @actionMedicalId.
  ///
  /// In en, this message translates to:
  /// **'MEDICAL ID'**
  String get actionMedicalId;

  /// No description provided for @actionResponder.
  ///
  /// In en, this message translates to:
  /// **'RESPONDER'**
  String get actionResponder;

  /// No description provided for @actionSafeWalk.
  ///
  /// In en, this message translates to:
  /// **'SAFE-WALK'**
  String get actionSafeWalk;

  /// No description provided for @actionFirstAid.
  ///
  /// In en, this message translates to:
  /// **'FIRST AID'**
  String get actionFirstAid;

  /// No description provided for @actionVitalScan.
  ///
  /// In en, this message translates to:
  /// **'VITAL SCAN'**
  String get actionVitalScan;

  /// No description provided for @actionMeshChat.
  ///
  /// In en, this message translates to:
  /// **'MESH CHAT'**
  String get actionMeshChat;

  /// No description provided for @actionSettings.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get actionSettings;

  /// No description provided for @triageResultTitle.
  ///
  /// In en, this message translates to:
  /// **'AI TRIAGE RESULT'**
  String get triageResultTitle;

  /// No description provided for @triageDegradedTitle.
  ///
  /// In en, this message translates to:
  /// **'AI TRIAGE (OFFLINE)'**
  String get triageDegradedTitle;

  /// No description provided for @severityLine.
  ///
  /// In en, this message translates to:
  /// **'Severity {level}/5 — {label}'**
  String severityLine(int level, String label);

  /// No description provided for @severityCritical.
  ///
  /// In en, this message translates to:
  /// **'CRITICAL'**
  String get severityCritical;

  /// No description provided for @severitySevere.
  ///
  /// In en, this message translates to:
  /// **'SEVERE'**
  String get severitySevere;

  /// No description provided for @severityModerate.
  ///
  /// In en, this message translates to:
  /// **'MODERATE'**
  String get severityModerate;

  /// No description provided for @severityMinor.
  ///
  /// In en, this message translates to:
  /// **'MINOR'**
  String get severityMinor;

  /// No description provided for @severityLow.
  ///
  /// In en, this message translates to:
  /// **'LOW'**
  String get severityLow;

  /// No description provided for @severityUnknown.
  ///
  /// In en, this message translates to:
  /// **'UNKNOWN'**
  String get severityUnknown;

  /// No description provided for @dispatchedServices.
  ///
  /// In en, this message translates to:
  /// **'DISPATCHED SERVICES'**
  String get dispatchedServices;

  /// No description provided for @firstAidGuidance.
  ///
  /// In en, this message translates to:
  /// **'FIRST AID GUIDANCE'**
  String get firstAidGuidance;

  /// No description provided for @noAiBadge.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get noAiBadge;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get settingsTitle;

  /// No description provided for @sectionConnectivity.
  ///
  /// In en, this message translates to:
  /// **'CONNECTIVITY'**
  String get sectionConnectivity;

  /// No description provided for @sectionLegal.
  ///
  /// In en, this message translates to:
  /// **'LEGAL & DATA'**
  String get sectionLegal;

  /// No description provided for @offlineMapsTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline maps'**
  String get offlineMapsTitle;

  /// No description provided for @offlineMapsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download and manage regional tiles'**
  String get offlineMapsSubtitle;

  /// No description provided for @meshConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Mesh configuration'**
  String get meshConfigTitle;

  /// No description provided for @meshConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Broadcast sensitivity and node visibility'**
  String get meshConfigSubtitle;

  /// No description provided for @blackBoxTitle.
  ///
  /// In en, this message translates to:
  /// **'Black box report'**
  String get blackBoxTitle;

  /// No description provided for @blackBoxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export signed telemetry and triage logs'**
  String get blackBoxSubtitle;

  /// No description provided for @blackBoxSnack.
  ///
  /// In en, this message translates to:
  /// **'Generating signed black box PDF…'**
  String get blackBoxSnack;

  /// No description provided for @dataPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Data privacy'**
  String get dataPrivacyTitle;

  /// No description provided for @dataPrivacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage local encryption and cloud sync'**
  String get dataPrivacySubtitle;

  /// No description provided for @vitalScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Vital scan'**
  String get vitalScanTitle;

  /// No description provided for @vitalAlignFinger.
  ///
  /// In en, this message translates to:
  /// **'Align index finger with rear camera and flash for PPG reading.'**
  String get vitalAlignFinger;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'UI, triage prompts, and voice output'**
  String get settingsLanguageSubtitle;

  /// No description provided for @incidentAssistantAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'Scene note: frontal impact logged. Check for smoke or fire.'**
  String get incidentAssistantAnalyzed;

  /// No description provided for @incidentVoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what you see…'**
  String get incidentVoiceHint;

  /// No description provided for @profileAiLine.
  ///
  /// In en, this message translates to:
  /// **'Medical profile helps first aid prompts during SOS.'**
  String get profileAiLine;

  /// No description provided for @thinkingOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline rules (no cloud).'**
  String get thinkingOffline;

  /// No description provided for @sttConfirmKeywords.
  ///
  /// In en, this message translates to:
  /// **'You can say yes, confirm, or help.'**
  String get sttConfirmKeywords;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to RoadSOS'**
  String get consentTitle;

  /// No description provided for @consentSummary.
  ///
  /// In en, this message translates to:
  /// **'This app processes location, motion/crash signals, and optional medical profile data to coordinate emergency help. Under India’s Digital Personal Data Protection Act, 2023, we need your informed consent before continuing. Cloud incident summaries are retained for 90 days unless you opt in below.'**
  String get consentSummary;

  /// No description provided for @consentExtendedRetentionLabel.
  ///
  /// In en, this message translates to:
  /// **'Keep anonymised cloud incident copies longer than 90 days for safety research (optional)'**
  String get consentExtendedRetentionLabel;

  /// No description provided for @consentAccept.
  ///
  /// In en, this message translates to:
  /// **'I agree — continue'**
  String get consentAccept;

  /// No description provided for @consentPrivacyButton.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get consentPrivacyButton;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy notice'**
  String get privacyPolicyTitle;

  /// No description provided for @privacyPolicyLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get privacyPolicyLanguageEn;

  /// No description provided for @privacyPolicyLanguageHi.
  ///
  /// In en, this message translates to:
  /// **'हिंदी'**
  String get privacyPolicyLanguageHi;

  /// No description provided for @goodSamaritanTitle.
  ///
  /// In en, this message translates to:
  /// **'Good Samaritan protection'**
  String get goodSamaritanTitle;

  /// No description provided for @goodSamaritanLead.
  ///
  /// In en, this message translates to:
  /// **'You are legally protected when helping in good faith.'**
  String get goodSamaritanLead;

  /// No description provided for @goodSamaritanBody.
  ///
  /// In en, this message translates to:
  /// **'India’s Good Samaritan framework (including the 2016 Supreme Court guidelines) discourages harassment of bystanders who assist road accident victims. Helping promptly can save lives.'**
  String get goodSamaritanBody;

  /// No description provided for @goodSamaritanContinue.
  ///
  /// In en, this message translates to:
  /// **'Understood'**
  String get goodSamaritanContinue;

  /// No description provided for @nearbySosSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby SOS'**
  String get nearbySosSectionTitle;

  /// No description provided for @nearbySosToggleTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby SOS push alerts'**
  String get nearbySosToggleTitle;

  /// No description provided for @nearbySosToggleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Firebase Cloud Messaging — notify me when someone nearby needs help'**
  String get nearbySosToggleSubtitle;

  /// No description provided for @nearbySosLearnProtection.
  ///
  /// In en, this message translates to:
  /// **'Good Samaritan protection'**
  String get nearbySosLearnProtection;

  /// No description provided for @aiThinkingTraceTitle.
  ///
  /// In en, this message translates to:
  /// **'TRIAGE REASONING'**
  String get aiThinkingTraceTitle;

  /// No description provided for @crisisCompanionTitle.
  ///
  /// In en, this message translates to:
  /// **'CRISIS ASSISTANT'**
  String get crisisCompanionTitle;

  /// No description provided for @crisisCompanionBreathing.
  ///
  /// In en, this message translates to:
  /// **'Breathe steadily. Monitoring your situation.'**
  String get crisisCompanionBreathing;

  /// No description provided for @sceneIntelligenceTitle.
  ///
  /// In en, this message translates to:
  /// **'SCENE INTELLIGENCE'**
  String get sceneIntelligenceTitle;

  /// No description provided for @helpEtaPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'No ETA available'**
  String get helpEtaPlaceholder;

  /// No description provided for @talkButton.
  ///
  /// In en, this message translates to:
  /// **'TALK'**
  String get talkButton;

  /// No description provided for @settingsExtendedRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Extended cloud retention'**
  String get settingsExtendedRetentionTitle;

  /// No description provided for @settingsExtendedRetentionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep incident summaries beyond 90 days when synced to Supabase (overrides default purge).'**
  String get settingsExtendedRetentionSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'bn',
    'en',
    'hi',
    'mr',
    'ta',
    'te',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'mr':
      return AppLocalizationsMr();
    case 'ta':
      return AppLocalizationsTa();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
