import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/family_circle_service.dart';
import '../services/family_tracking_service.dart';
import '../services/sms_direct_send.dart';
import '../services/user_profile_service.dart';
import '../services/webrtc_voice_call_service.dart';

/// Family Circle: list of trusted peers, live map of their positions, invite +
/// redeem flows. Map uses the same `flutter_map` + OSM tiles used elsewhere in
/// the app, so no extra credentials needed.
class FamilyCircleScreen extends ConsumerStatefulWidget {
  const FamilyCircleScreen({super.key});

  @override
  ConsumerState<FamilyCircleScreen> createState() => _FamilyCircleScreenState();
}

class _FamilyCircleScreenState extends ConsumerState<FamilyCircleScreen> {
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(familyCircleServiceProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyCircleServiceProvider);
    final notifier = ref.read(familyCircleServiceProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF080A0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080A0D),
        elevation: 0,
        title: const Text(
          'FAMILY CIRCLE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            fontSize: 14,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.busy ? null : notifier.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Redeem invite',
            onPressed: () => _showRedeemDialog(context, notifier),
            icon: const Icon(Icons.qr_code),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.lastError != null) _errorBanner(state.lastError!),
            SizedBox(height: 220, child: _liveMap(state)),
            _publishingControls(state, notifier),
            const Divider(height: 1, color: Color(0xFF1F2933)),
            Expanded(child: _membersList(state, notifier)),
          ],
        ),
      ),
      floatingActionButton: state.circles.isEmpty
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF5C7CFA),
              onPressed: () => _showCreateCircleDialog(context, notifier),
              icon: const Icon(Icons.group_add),
              label: const Text('CREATE CIRCLE'),
            )
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF5C7CFA),
              onPressed: () =>
                  _showInviteDialog(context, notifier, state.circles.first.id),
              icon: const Icon(Icons.person_add),
              label: const Text('INVITE BY SMS'),
            ),
    );
  }

  // ── Map ────────────────────────────────────────────────────────────────────

  Widget _liveMap(FamilyCircleState state) {
    final markers = <Marker>[];
    LatLng? first;
    for (final loc in state.livePositions.values) {
      final point = LatLng(loc.latitude, loc.longitude);
      first ??= point;
      markers.add(
        Marker(
          point: point,
          width: 70,
          height: 70,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                loc.isSos
                    ? Icons.warning
                    : loc.isSafeWalk
                    ? Icons.directions_walk
                    : Icons.person_pin_circle,
                size: 32,
                color: loc.isSos
                    ? const Color(0xFFE8281A)
                    : loc.isSafeWalk
                    ? const Color(0xFF00B8A0)
                    : const Color(0xFF5C7CFA),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  loc.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: first ?? const LatLng(12.9716, 77.5946),
        initialZoom: first != null ? 14 : 5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'app.roadsos',
          maxZoom: 18,
        ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _publishingControls(
    FamilyCircleState state,
    FamilyCircleService notifier,
  ) {
    final mode = state.publishingMode;
    final profile = ref.read(userProfileProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF11151B),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.publishing ? 'YOU ARE LIVE' : 'YOU ARE PRIVATE',
                  style: TextStyle(
                    color: state.publishing
                        ? const Color(0xFF00B8A0)
                        : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.publishing
                      ? mode == FamilyPublishMode.sos
                            ? 'Sharing SOS location with circle'
                            : 'Sharing Safe Walk position with circle'
                      : 'Circle peers cannot see your location',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          if (state.publishing)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFE8281A)),
              ),
              onPressed: notifier.stopPublishing,
              icon: const Icon(
                Icons.stop_circle_outlined,
                color: Color(0xFFE8281A),
              ),
              label: const Text('STOP'),
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B8A0),
                foregroundColor: Colors.black,
              ),
              onPressed: state.circles.isEmpty
                  ? null
                  : () => notifier.startPublishing(
                      mode: FamilyPublishMode.safeWalk,
                      displayName: profile.fullName.trim().isEmpty
                          ? 'Me'
                          : profile.fullName.trim(),
                    ),
              icon: const Icon(Icons.location_on),
              label: const Text('GO LIVE'),
            ),
        ],
      ),
    );
  }

  // ── Members list ───────────────────────────────────────────────────────────

  Widget _membersList(FamilyCircleState state, FamilyCircleService notifier) {
    if (state.circles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No circle yet.\n\nTap CREATE CIRCLE to start one — then invite parents, partner, or hostel friends by SMS.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
      );
    }
    if (state.members.isEmpty) {
      return const Center(
        child: Text(
          'Circle is empty. Tap INVITE BY SMS.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemCount: state.members.length,
      itemBuilder: (context, i) {
        final m = state.members[i];
        final live = state.livePositions[m.userId];
        final isSelf = m.role == 'owner'; // best-effort; not strict
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF11151B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1F2933)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF5C7CFA),
                child: Text(
                  (m.displayName.isNotEmpty ? m.displayName[0] : '?')
                      .toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (m.phoneE164 != null)
                      Text(
                        m.phoneE164!,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      live == null
                          ? 'Not sharing right now'
                          : live.isSos
                          ? 'SOS · ${_age(live.updatedAt)} ago'
                          : live.isSafeWalk
                          ? 'Safe Walk · ${_age(live.updatedAt)} ago'
                          : 'Live · ${_age(live.updatedAt)} ago',
                      style: TextStyle(
                        color: live == null
                            ? Colors.white38
                            : live.isSos
                            ? const Color(0xFFE8281A)
                            : const Color(0xFF00B8A0),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isSelf) ...[
                IconButton(
                  tooltip: 'Voice call in app',
                  onPressed: () async {
                    final res = await ref
                        .read(webRtcVoiceCallServiceProvider.notifier)
                        .startCall(calleeId: m.userId, peerName: m.displayName);
                    if (!context.mounted) return;
                    if (res.error != null) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(res.error!)));
                    }
                  },
                  icon: const Icon(Icons.headset_mic, color: Color(0xFF5C7CFA)),
                ),
                if (m.phoneE164 != null)
                  IconButton(
                    tooltip: 'PSTN call',
                    onPressed: () => launchUrl(Uri.parse('tel:${m.phoneE164}')),
                    icon: const Icon(Icons.call, color: Color(0xFF00B8A0)),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _age(DateTime t) {
    final delta = DateTime.now().toUtc().difference(t.toUtc());
    if (delta.inSeconds < 60) return '${delta.inSeconds}s';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    if (delta.inHours < 24) return '${delta.inHours}h';
    return '${delta.inDays}d';
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Widget _errorBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0x44E8281A),
      child: Text(text, style: const TextStyle(color: Color(0xFFFF9494))),
    );
  }

  Future<void> _showCreateCircleDialog(
    BuildContext context,
    FamilyCircleService notifier,
  ) async {
    final controller = TextEditingController(text: 'Family');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create circle'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Circle name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              Navigator.pop(ctx);
              if (name.isEmpty) return;
              final err = await notifier.createCircle(name);
              if (!context.mounted) return;
              if (err != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(err)));
              }
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  Future<void> _showInviteDialog(
    BuildContext context,
    FamilyCircleService notifier,
    String circleId,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite by SMS'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone (E.164, e.g. +91987654xxxx)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = controller.text.trim();
              final phone = FamilyTrackingService.normalizePhoneDigits(raw);
              Navigator.pop(ctx);
              if (phone == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Need at least 10 digits.')),
                );
                return;
              }
              final res = await notifier.createInvite(
                circleId: circleId,
                phoneE164: '+91$phone',
              );
              if (!context.mounted) return;
              if (res.error != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(res.error!)));
                return;
              }
              final body =
                  'RoadSOS: Join my Family Circle. Tap to accept: ${res.shareUrl} (code ${res.code}). Expires in 7 days.';
              await Clipboard.setData(ClipboardData(text: body));
              var sent = false;
              if (!kIsWeb && Platform.isAndroid) {
                sent = await sendSmsDirectAndroid(phone, body);
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    sent
                        ? 'Invite SMS sent to +91$phone'
                        : 'Invite ready — message copied to clipboard',
                  ),
                ),
              );
            },
            child: const Text('SEND'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRedeemDialog(
    BuildContext context,
    FamilyCircleService notifier,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeem invite'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Invite code'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              final code = controller.text.trim().toUpperCase();
              Navigator.pop(ctx);
              if (code.isEmpty) return;
              final err = await notifier.redeemInvite(code);
              if (!context.mounted) return;
              if (err != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(err)));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Joined circle ✓')),
                );
              }
            },
            child: const Text('JOIN'),
          ),
        ],
      ),
    );
  }
}
