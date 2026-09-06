import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in for FCM “Nearby SOS” + one-time Good Samaritan banner acknowledgement.
class NearbySosPreferences {
  NearbySosPreferences._();

  static const _kPushOptIn = 'nearby_sos_fcm_opt_in';
  static const _kGoodSamaritanSeen = 'good_samaritan_banner_seen';

  static Future<bool> pushOptIn() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kPushOptIn) ?? false;
  }

  static Future<void> setPushOptIn(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPushOptIn, value);
  }

  static Future<bool> goodSamaritanSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kGoodSamaritanSeen) ?? false;
  }

  static Future<void> setGoodSamaritanSeen(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kGoodSamaritanSeen, value);
  }
}
