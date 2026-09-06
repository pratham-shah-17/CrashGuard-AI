import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locales aligned with India-first UI + flutter_tts engines (hi/ta/te/bn/mr).
const kSupportedAppLocales = <Locale>[
  Locale('en'),
  Locale('hi'),
  Locale('ta'),
  Locale('te'),
  Locale('bn'),
  Locale('mr'),
];

const _prefsKey = 'app_locale_language_code';

Locale _resolvePlatformLocale() {
  final platform = WidgetsBinding.instance.platformDispatcher.locale;
  if (kSupportedAppLocales.any(
    (e) => e.languageCode == platform.languageCode,
  )) {
    return Locale(platform.languageCode);
  }
  return const Locale('en');
}

class AppLocaleController extends StateNotifier<Locale> {
  AppLocaleController() : super(_resolvePlatformLocale()) {
    Future.microtask(loadSaved);
  }

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null &&
        kSupportedAppLocales.any((l) => l.languageCode == code)) {
      state = Locale(code);
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (!kSupportedAppLocales.any(
      (l) => l.languageCode == locale.languageCode,
    )) {
      return;
    }
    state = Locale(locale.languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, state.languageCode);
  }
}

final appLocaleProvider = StateNotifierProvider<AppLocaleController, Locale>((
  ref,
) {
  return AppLocaleController();
});
