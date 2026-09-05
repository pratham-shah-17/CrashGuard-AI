// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'CrashGuard AI';

  @override
  String get dashboardTitle => 'CrashGuard AI';

  @override
  String get sosButton => 'एसओएस';

  @override
  String get secondsLabel => 'सेकंड';

  @override
  String get sosDispatchWarning =>
      'अभी कुछ नहीं भेजा गया। गलती हो तो नीचे रद्द करें।';

  @override
  String get sosIdleTools => 'और';

  @override
  String get sosIdleToolsTitle => 'आपातकालीन उपकरण और स्थिति';

  @override
  String get sosButtonSub => 'आपातकाल के लिए दबाएँ';

  @override
  String get cancelSos => 'रद्द करें';

  @override
  String get orchestratorBystanderStarted => 'बाइस्टैंडर अलर्ट शुरू';

  @override
  String get orchestratorSelfSosStarted => 'सेल्फ SOS शुरू';

  @override
  String get orchestratorAcquiringLocation => 'स्थान प्राप्त कर रहे हैं…';

  @override
  String orchestratorLocationSecured(String lat, String lng) {
    return 'स्थान: $lat, $lng';
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
  String get orchestratorAiBrief => 'क्लाउड AI स्थिति जांच रहा है…';

  @override
  String orchestratorTriageDone(int level) {
    return 'ट्राइएज पूर्ण — गंभीरता $level';
  }

  @override
  String get orchestratorDispatching => 'सभी चैनलों पर अलर्ट भेज रहे हैं…';

  @override
  String get orchestratorSosLive => 'SOS सक्रिय — सभी चैनल चालू';

  @override
  String get orchestratorCancelled => 'SOS रद्द';

  @override
  String get mapPlaceholder => 'मानचित्र';

  @override
  String get actionScene => 'दृश्य';

  @override
  String get actionMedicalId => 'मेडिकल आईडी';

  @override
  String get actionResponder => 'रिस्पॉन्डर';

  @override
  String get actionSafeWalk => 'सुरक्षित चलना';

  @override
  String get actionFirstAid => 'प्राथमिक उपचार';

  @override
  String get actionVitalScan => 'वाइटल स्कैन';

  @override
  String get actionMeshChat => 'मेश चैट';

  @override
  String get actionSettings => 'सेटिंग्स';

  @override
  String get triageResultTitle => 'AI ट्राइएज परिणाम';

  @override
  String get triageDegradedTitle => 'AI ट्राइएज (ऑफ़लाइन)';

  @override
  String severityLine(int level, String label) {
    return 'गंभीरता $level/5 — $label';
  }

  @override
  String get severityCritical => 'अत्यंत गंभीर';

  @override
  String get severitySevere => 'गंभीर';

  @override
  String get severityModerate => 'मध्यम';

  @override
  String get severityMinor => 'हल्का';

  @override
  String get severityLow => 'कम';

  @override
  String get severityUnknown => 'अज्ञात';

  @override
  String get dispatchedServices => 'भेजी गई सेवाएँ';

  @override
  String get firstAidGuidance => 'प्राथमिक उपचार मार्गदर्शन';

  @override
  String get noAiBadge => 'ऑफ़लाइन';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get sectionConnectivity => 'कनेक्टिविटी';

  @override
  String get sectionLegal => 'कानूनी और डेटा';

  @override
  String get offlineMapsTitle => 'ऑफ़लाइन मानचित्र';

  @override
  String get offlineMapsSubtitle => 'क्षेत्रीय टाइल डाउनलोड करें';

  @override
  String get meshConfigTitle => 'मेश सेटिंग';

  @override
  String get meshConfigSubtitle => 'संवेदनशीलता और दृश्यता';

  @override
  String get blackBoxTitle => 'ब्लैक बॉक्स रिपोर्ट';

  @override
  String get blackBoxSubtitle => 'टेलीमेट्री और ट्राइएज निर्यात';

  @override
  String get blackBoxSnack => 'हस्ताक्षरित PDF बन रहा है…';

  @override
  String get dataPrivacyTitle => 'डेटा गोपनीयता';

  @override
  String get dataPrivacySubtitle => 'एन्क्रिप्शन और सिंक';

  @override
  String get vitalScanTitle => 'वाइटल स्कैन';

  @override
  String get vitalAlignFinger => 'PPG के लिए उंगली कैमरे और फ्लैश पर रखें।';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsLanguageSubtitle => 'इंटरफ़ेस, ट्राइएज और आवाज़';

  @override
  String get incidentAssistantAnalyzed =>
      'दृश्य: अगला प्रहार दर्ज। धुआँ या आग जाँचें।';

  @override
  String get incidentVoiceHint => 'जो देखें वह बताएँ…';

  @override
  String get profileAiLine =>
      'प्रोफ़ाइल SOS के दौरान पहला उपचार संकेतों में मदद करती है।';

  @override
  String get thinkingOffline => 'ऑफ़लाइन नियम (क्लाउड नहीं)।';

  @override
  String get sttConfirmKeywords => 'आप हाँ, पुष्टि, या मदद कह सकते हैं।';

  @override
  String get consentTitle => 'CrashGuard AI में आपका स्वागत';

  @override
  String get consentSummary =>
      'यह ऐप आपकी लोकेशन, क्रैश/मोशन संकेतों और वैकल्पिक मेडिकल प्रोफ़ाइल को आपातकालीन सहायता के लिए प्रोसेस करता है। भारत के डिजिटल व्यक्तिगत डेटा संरक्षण अधिनियम, 2023 के अनुसार, जारी रखने से पहले सहमति ज़रूरी है। क्लाउड पर 90 दिन तक रिटेंशन (जब तक नीचे विकल्प न चुने)।';

  @override
  String get consentExtendedRetentionLabel =>
      'सुरक्षा शोध के लिए क्लाउड डेटा 90 दिन से अधिक रखें (वैकल्पिक)';

  @override
  String get consentAccept => 'मैं सहमत हूँ — आगे बढ़ें';

  @override
  String get consentPrivacyButton => 'गोपनीयता नोटिस';

  @override
  String get privacyPolicyTitle => 'गोपनीयता नोटिस';

  @override
  String get privacyPolicyLanguageEn => 'English';

  @override
  String get privacyPolicyLanguageHi => 'हिंदी';

  @override
  String get goodSamaritanTitle => 'गुड सेमेरिटन सुरक्षा';

  @override
  String get goodSamaritanLead =>
      'ईमानदारी से मदद करने पर आप कानूनी रूप से सुरक्षित हैं।';

  @override
  String get goodSamaritanBody =>
      'भारत में गुड सेमेरिटन फ्रेमवर्क (2016 सर्वोच्च न्यायालय दिशानिर्देश सहित) सड़क दुर्घटना पीड़ितों की मदद करने वालों के उत्पीड़न को रोकता है। समय पर मदद जान बचा सकती है।';

  @override
  String get goodSamaritanContinue => 'समझ गया';

  @override
  String get nearbySosSectionTitle => 'आसपास SOS';

  @override
  String get nearbySosToggleTitle => 'आसपास SOS पुश अलर्ट';

  @override
  String get nearbySosToggleSubtitle =>
      'फायरबेस — जब पास में किसी को मदद चाहिए तो सूचना';

  @override
  String get nearbySosLearnProtection => 'गुड सेमेरिटन सुरक्षा';

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
  String get settingsExtendedRetentionTitle => 'विस्तारित क्लाउड रिटेंशन';

  @override
  String get settingsExtendedRetentionSubtitle =>
      'Supabase सिंक पर 90 दिन से अधिक घटना सारांश रखें (डिफ़ॉल्ट purge ओवरराइड)।';
}
