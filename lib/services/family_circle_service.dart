import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart'
    show isSupabaseSdkInitialized, ensureSupabaseAnonymousSession;
import '../logging/app_log.dart';

/// A member of a Family Circle (mapped from `family_circle_members` + auth uid).
class FamilyMember {
  const FamilyMember({
    required this.userId,
    required this.circleId,
    required this.displayName,
    required this.role,
    this.phoneE164,
    this.joinedAt,
  });

  final String userId;
  final String circleId;
  final String displayName;
  final String role;
  final String? phoneE164;
  final DateTime? joinedAt;
}

/// Live position of a circle peer (mapped from `family_live_locations`).
class FamilyLiveLocation {
  const FamilyLiveLocation({
    required this.userId,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.accuracyM,
    this.headingDeg,
    this.speedMps,
    this.batteryPct,
    this.isSafeWalk = false,
    this.isSos = false,
    this.destination,
  });

  final String userId;
  final String displayName;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? headingDeg;
  final double? speedMps;
  final int? batteryPct;
  final bool isSafeWalk;
  final bool isSos;
  final String? destination;
  final DateTime updatedAt;

  factory FamilyLiveLocation.fromRow(Map<String, dynamic> row) {
    return FamilyLiveLocation(
      userId: row['user_id'] as String,
      displayName: (row['display_name'] as String?) ?? 'Family member',
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      accuracyM: (row['accuracy_m'] as num?)?.toDouble(),
      headingDeg: (row['heading_deg'] as num?)?.toDouble(),
      speedMps: (row['speed_mps'] as num?)?.toDouble(),
      batteryPct: (row['battery_pct'] as num?)?.toInt(),
      isSafeWalk: (row['is_safewalk'] as bool?) ?? false,
      isSos: (row['is_sos'] as bool?) ?? false,
      destination: row['destination'] as String?,
      updatedAt:
          DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class FamilyCircle {
  const FamilyCircle({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;

  factory FamilyCircle.fromRow(Map<String, dynamic> row) {
    return FamilyCircle(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? 'Family',
      createdBy: row['created_by'] as String,
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

class FamilyCircleState {
  const FamilyCircleState({
    this.circles = const <FamilyCircle>[],
    this.members = const <FamilyMember>[],
    this.livePositions = const <String, FamilyLiveLocation>{},
    this.busy = false,
    this.lastError,
    this.publishing = false,
    this.publishingMode = FamilyPublishMode.off,
    this.publishingDestination,
  });

  final List<FamilyCircle> circles;
  final List<FamilyMember> members;
  final Map<String, FamilyLiveLocation> livePositions;
  final bool busy;
  final String? lastError;
  final bool publishing;
  final FamilyPublishMode publishingMode;
  final String? publishingDestination;

  FamilyCircleState copyWith({
    List<FamilyCircle>? circles,
    List<FamilyMember>? members,
    Map<String, FamilyLiveLocation>? livePositions,
    bool? busy,
    Object? lastError = _sentinel,
    bool? publishing,
    FamilyPublishMode? publishingMode,
    Object? publishingDestination = _sentinel,
  }) {
    return FamilyCircleState(
      circles: circles ?? this.circles,
      members: members ?? this.members,
      livePositions: livePositions ?? this.livePositions,
      busy: busy ?? this.busy,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      publishing: publishing ?? this.publishing,
      publishingMode: publishingMode ?? this.publishingMode,
      publishingDestination: identical(publishingDestination, _sentinel)
          ? this.publishingDestination
          : publishingDestination as String?,
    );
  }

  static const _sentinel = Object();
}

enum FamilyPublishMode { off, safeWalk, sos }

/// Service: manages Family Circles, invites, live-location publishing, and a
/// realtime subscription to peer positions.
///
/// Safe in absence of Supabase auth — every method returns a typed failure
/// string instead of throwing, so UI can render an actionable hint.
class FamilyCircleService extends StateNotifier<FamilyCircleState> {
  FamilyCircleService(Ref ref) : super(const FamilyCircleState()) {
    // Ref is currently unused but kept in the constructor so future work
    // (FCM push, profile sync) can read other providers without changing the
    // call-site contract.
    _ref = ref;
    _bootstrap();
  }

  // ignore: unused_field
  Ref? _ref;

  RealtimeChannel? _peerChannel;
  Timer? _publishTimer;
  StreamSubscription<Position>? _positionSub;

  bool get _hasSession {
    try {
      return isSupabaseSdkInitialized &&
          Supabase.instance.client.auth.currentSession != null;
    } on Object catch (_) {
      return false;
    }
  }

  Future<void> _retryAnonSignIn() async {
    if (!isSupabaseSdkInitialized) return;
    try {
      await ensureSupabaseAnonymousSession(Supabase.instance.client);
    } on Object catch (e, st) {
      appLog.d('[FamilyCircle] anon sign-in retry failed', stackTrace: st);
    }
  }

  Future<void> _bootstrap() async {
    if (!_hasSession) return;
    await refresh();
  }

  /// Reload circles + members + initial live snapshot. Re-subscribes realtime.
  ///
  /// If [_hasSession] is false but Supabase SDK is initialized, transparently
  /// retries anonymous sign-in once before giving up. This handles the
  /// first-launch race where the user reached the dashboard before the
  /// background sign-in finished.
  Future<void> refresh() async {
    if (!_hasSession) {
      await _retryAnonSignIn();
    }
    if (!_hasSession) {
      state = state.copyWith(
        circles: const [],
        members: const [],
        livePositions: const {},
        lastError: isSupabaseSdkInitialized
            ? 'Sign-in to Supabase is still completing — tap Refresh in a moment.'
            : 'Family Circle needs Supabase credentials. Add SUPABASE_URL + SUPABASE_ANON_KEY to your build (see README) and restart the app.',
      );
      return;
    }
    state = state.copyWith(busy: true, lastError: null);

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

      final circlesRows = await client
          .from('family_circles')
          .select('id, name, created_by, created_at');
      final circles = (circlesRows as List)
          .cast<Map<String, dynamic>>()
          .map(FamilyCircle.fromRow)
          .toList();

      final memberRows = await client
          .from('family_circle_members')
          .select(
            'circle_id, user_id, display_name, phone_e164, role, joined_at',
          );
      final members = (memberRows as List)
          .cast<Map<String, dynamic>>()
          .map(
            (r) => FamilyMember(
              userId: r['user_id'] as String,
              circleId: r['circle_id'] as String,
              displayName: (r['display_name'] as String?) ?? 'Member',
              phoneE164: r['phone_e164'] as String?,
              role: (r['role'] as String?) ?? 'member',
              joinedAt: DateTime.tryParse(r['joined_at']?.toString() ?? ''),
            ),
          )
          .toList();

      final positionsRows = await client
          .from('family_live_locations')
          .select(
            'user_id, display_name, latitude, longitude, accuracy_m, heading_deg, '
            'speed_mps, battery_pct, is_safewalk, is_sos, destination, updated_at',
          );
      final live = <String, FamilyLiveLocation>{};
      for (final row in (positionsRows as List).cast<Map<String, dynamic>>()) {
        if (row['user_id'] == uid) continue; // skip self
        live[row['user_id'] as String] = FamilyLiveLocation.fromRow(row);
      }

      state = state.copyWith(
        circles: circles,
        members: members,
        livePositions: live,
        busy: false,
      );

      await _resubscribePeerChannel();
    } on Object catch (e, st) {
      appLog.w('[FamilyCircle] refresh failed', error: e, stackTrace: st);
      state = state.copyWith(busy: false, lastError: 'Refresh failed: $e');
    }
  }

  Future<void> _resubscribePeerChannel() async {
    if (!_hasSession) return;
    try {
      _peerChannel?.unsubscribe();
    } on Object catch (_) {}
    _peerChannel = null;

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser!.id;

    final channel = client
        .channel('public:family_live_locations:peer-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'family_live_locations',
          callback: (payload) {
            try {
              final row = (payload.newRecord as Map?)?.cast<String, dynamic>();
              if (row == null) return;
              if (row['user_id'] == uid) return;
              final updated = Map<String, FamilyLiveLocation>.from(
                state.livePositions,
              );
              updated[row['user_id'] as String] = FamilyLiveLocation.fromRow(
                row,
              );
              state = state.copyWith(livePositions: updated);
            } on Object catch (e, st) {
              appLog.d('[FamilyCircle] realtime decode failed', stackTrace: st);
            }
          },
        )
        .subscribe();

    _peerChannel = channel;
  }

  /// Create a new circle owned by the signed-in user.
  Future<String?> createCircle(String name) async {
    if (!_hasSession) return 'Sign in first.';
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      final inserted = await client
          .from('family_circles')
          .insert({'name': name, 'created_by': uid})
          .select('id')
          .single();
      await client.from('family_circle_members').insert({
        'circle_id': inserted['id'],
        'user_id': uid,
        'display_name': name,
        'role': 'owner',
      });
      await refresh();
      return null;
    } on Object catch (e, st) {
      appLog.w('[FamilyCircle] createCircle failed', error: e, stackTrace: st);
      return 'Could not create circle: $e';
    }
  }

  /// Creates an invite row and returns the invite code + shareable deep link.
  /// The UI calls `sendSmsDirectAndroid` separately so we never silently text
  /// without explicit user choice.
  Future<({String? code, String? shareUrl, String? error})> createInvite({
    required String circleId,
    required String phoneE164,
  }) async {
    if (!_hasSession) {
      return (code: null, shareUrl: null, error: 'Sign in first.');
    }
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      final code = _generateInviteCode();
      await client.from('family_invites').insert({
        'circle_id': circleId,
        'inviter_id': uid,
        'invitee_phone_e164': phoneE164,
        'code': code,
      });
      final shareUrl = 'https://roadsos.app/i/$code';
      return (code: code, shareUrl: shareUrl, error: null);
    } on Object catch (e, st) {
      appLog.w('[FamilyCircle] createInvite failed', error: e, stackTrace: st);
      return (code: null, shareUrl: null, error: 'Invite create failed: $e');
    }
  }

  /// Redeem an invite code to join a circle.
  Future<String?> redeemInvite(String code) async {
    if (!_hasSession) return 'Sign in first.';
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      final row = await client
          .from('family_invites')
          .select('id, circle_id, expires_at, accepted_by, revoked_at')
          .eq('code', code)
          .maybeSingle();
      if (row == null) return 'Invite not found.';
      if (row['revoked_at'] != null) return 'Invite revoked.';
      if (row['accepted_by'] != null) return 'Invite already used.';
      final exp = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (exp != null && exp.isBefore(DateTime.now().toUtc())) {
        return 'Invite expired.';
      }
      final circleId = row['circle_id'] as String;
      await client.from('family_circle_members').insert({
        'circle_id': circleId,
        'user_id': uid,
        'display_name': 'Me',
        'role': 'member',
      });
      await client
          .from('family_invites')
          .update({
            'accepted_by': uid,
            'accepted_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', row['id']);
      await refresh();
      return null;
    } on Object catch (e, st) {
      appLog.w('[FamilyCircle] redeemInvite failed', error: e, stackTrace: st);
      return 'Could not redeem invite: $e';
    }
  }

  /// Start publishing live position to all circle peers.
  ///
  /// Uses geolocator stream w/ 5-second debounce — minimal battery hit during
  /// Safe Walk / SOS. Off mode stops publishing and deletes the row so peers
  /// see the user disappear from the map.
  Future<void> startPublishing({
    required FamilyPublishMode mode,
    String? destination,
    String? displayName,
  }) async {
    if (!_hasSession) {
      state = state.copyWith(
        lastError: 'Sign in (anonymous Supabase auth) to share live location.',
      );
      return;
    }
    if (mode == FamilyPublishMode.off) {
      await stopPublishing();
      return;
    }
    state = state.copyWith(
      publishing: true,
      publishingMode: mode,
      publishingDestination: destination,
      lastError: null,
    );

    _publishTimer?.cancel();
    await _positionSub?.cancel();

    Position? lastPos;
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 8,
          ),
        ).listen(
          (pos) => lastPos = pos,
          onError: (e) => appLog.d('[FamilyCircle] position stream error: $e'),
        );

    Future<void> tick() async {
      final pos = lastPos;
      if (pos == null) return;
      await _upsertLive(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyM: pos.accuracy,
        headingDeg: pos.heading.isNaN ? null : pos.heading,
        speedMps: pos.speed.isNaN ? null : pos.speed,
        isSafeWalk: mode == FamilyPublishMode.safeWalk,
        isSos: mode == FamilyPublishMode.sos,
        destination: destination,
        displayName: displayName,
      );
    }

    // First tick immediately (best-effort), then steady cadence.
    unawaited(tick());
    _publishTimer = Timer.periodic(const Duration(seconds: 5), (_) => tick());
  }

  /// Stop publishing and clear our row so peers see us go offline.
  Future<void> stopPublishing() async {
    _publishTimer?.cancel();
    _publishTimer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    state = state.copyWith(
      publishing: false,
      publishingMode: FamilyPublishMode.off,
      publishingDestination: null,
    );
    if (!_hasSession) return;
    try {
      final client = Supabase.instance.client;
      await client
          .from('family_live_locations')
          .delete()
          .eq('user_id', client.auth.currentUser!.id);
    } on Object catch (e, st) {
      appLog.d('[FamilyCircle] stopPublishing delete failed', stackTrace: st);
    }
  }

  Future<void> _upsertLive({
    required double latitude,
    required double longitude,
    double? accuracyM,
    double? headingDeg,
    double? speedMps,
    int? batteryPct,
    required bool isSafeWalk,
    required bool isSos,
    String? destination,
    String? displayName,
  }) async {
    if (!_hasSession) return;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      await client.from('family_live_locations').upsert({
        'user_id': uid,
        'display_name': displayName ?? 'Me',
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_m': accuracyM,
        'heading_deg': headingDeg,
        'speed_mps': speedMps,
        'battery_pct': batteryPct,
        'is_safewalk': isSafeWalk,
        'is_sos': isSos,
        'destination': destination,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object catch (e, st) {
      appLog.d('[FamilyCircle] upsert failed', stackTrace: st);
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _publishTimer?.cancel();
    _positionSub?.cancel();
    try {
      _peerChannel?.unsubscribe();
    } on Object catch (_) {}
    super.dispose();
  }
}

final familyCircleServiceProvider =
    StateNotifierProvider<FamilyCircleService, FamilyCircleState>((ref) {
      return FamilyCircleService(ref);
    });
