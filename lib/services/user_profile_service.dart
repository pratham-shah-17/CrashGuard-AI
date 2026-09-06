import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserProfile {
  final String fullName;
  final String bloodType;
  final String allergies;
  final String medications;
  final String conditions;
  final String emergencyContact;

  /// Multiple emergency contacts for multi-contact SOS dispatch.
  /// When a crash is detected, ALL contacts in this list will be
  /// notified via SMS with the accident location and medical info.
  final List<String> emergencyContacts;

  UserProfile({
    this.fullName = '',
    this.bloodType = 'Unknown',
    this.allergies = 'None',
    this.medications = 'None',
    this.conditions = 'None',
    this.emergencyContact = '',
    this.emergencyContacts = const [],
  });

  /// Returns a deduplicated list of all emergency contacts,
  /// merging the legacy single contact with the new contacts list.
  List<String> get allEmergencyContacts {
    final all = <String>{};
    if (emergencyContact.trim().isNotEmpty) {
      all.add(emergencyContact.trim());
    }
    for (final c in emergencyContacts) {
      if (c.trim().isNotEmpty) all.add(c.trim());
    }
    return all.toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'bloodType': bloodType,
      'allergies': allergies,
      'medications': medications,
      'conditions': conditions,
      'emergencyContact': emergencyContact,
      'emergencyContacts': emergencyContacts,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final rawContacts = map['emergencyContacts'];
    final contacts = <String>[];
    if (rawContacts is List) {
      for (final e in rawContacts) {
        if (e is String && e.trim().isNotEmpty) contacts.add(e.trim());
      }
    }
    return UserProfile(
      fullName: map['fullName'] ?? '',
      bloodType: map['bloodType'] ?? 'Unknown',
      allergies: map['allergies'] ?? 'None',
      medications: map['medications'] ?? 'None',
      conditions: map['conditions'] ?? 'None',
      emergencyContact: map['emergencyContact'] ?? '',
      emergencyContacts: contacts,
    );
  }

  String toJson() => json.encode(toMap());
}

class UserProfileService extends StateNotifier<UserProfile> {
  UserProfileService() : super(UserProfile()) {
    _loadProfile();
  }

  static const _storage = FlutterSecureStorage();
  static const _key = 'roadsos.user_profile.v1';

  Future<void> _loadProfile() async {
    final data = await _storage.read(key: _key);
    if (data != null) {
      state = UserProfile.fromMap(json.decode(data));
    }
  }

  Future<void> updateProfile(UserProfile newProfile) async {
    state = newProfile;
    await _storage.write(key: _key, value: newProfile.toJson());
  }

  /// Risk hint for allergies (deterministic — no on-device LLM).
  Future<String> getMedicalRiskBrief() async {
    // Prompt: "Analyze this profile for emergency responders: $state"
    if (state.bloodType == 'Unknown' && state.allergies == 'None') {
      return "Low specific medical risk detected.";
    }
    return 'Allergy alert: prioritize avoiding exposure to ${state.allergies}.';
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileService, UserProfile>((ref) {
      return UserProfileService();
    });
