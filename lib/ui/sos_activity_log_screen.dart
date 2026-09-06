import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/sos_activity_record.dart';
import '../services/emergency_orchestrator.dart';
import '../services/sos_activity_log_service.dart';
import 'dispatch_status_panel.dart';

final _activityHistoryProvider = FutureProvider<List<SosActivityRecord>>((
  ref,
) async {
  return SosActivityLogService.instance.loadHistory();
});

/// Post-SOS transparency: timestamps, GPS, AI triage, channels, sync — supports insurer / FIR context in India.
class SosActivityLogScreen extends ConsumerWidget {
  const SosActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(_activityHistoryProvider);
    final live = ref.watch(emergencyOrchestratorProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'ACTIVITY LOG',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1,
          ),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(_activityHistoryProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _insuranceBanner(),
          const SizedBox(height: 16),
          if (live.phase != SOSPhase.idle &&
              live.dispatchChannels.isNotEmpty) ...[
            _sectionTitle('CURRENT SESSION'),
            const SizedBox(height: 8),
            Text(
              live.incidentId ?? '—',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            DispatchStatusPanel(channels: live.dispatchChannels),
            const Divider(color: Colors.white12, height: 32),
          ],
          _sectionTitle('SAVED INCIDENTS'),
          const SizedBox(height: 8),
          history.when(
            data: (items) {
              if (items.isEmpty) {
                return const Text(
                  'No completed incidents stored yet. After an SOS finishes dispatch, a summary is saved here automatically.',
                  style: TextStyle(color: Colors.white54, height: 1.4),
                );
              }
              return Column(
                children: items.map((e) => _historyCard(context, e)).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(
              'Could not load history: $e',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _insuranceBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'This log shows what the app attempted: GPS coordinates, AI triage, mesh/SMS/cloud steps, '
        'and sync status. You can show it to insurers or police — it is not proof that emergency '
        'services answered, only that RoadSOS ran these steps on your device.',
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: TextStyle(
        color: Colors.blue.withValues(alpha: 0.75),
        fontWeight: FontWeight.w900,
        fontSize: 10,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _historyCard(BuildContext context, SosActivityRecord r) {
    final localTime = r.completedAtUtc.toLocal();
    final fmt = DateFormat.yMMMd().add_jm();
    final coarseLat = r.latitude.toStringAsFixed(3);
    final coarseLng = r.longitude.toStringAsFixed(3);
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fmt.format(localTime),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Incident ${r.incidentId}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'GPS shared (coarse by default)',
              style: TextStyle(
                color: Colors.blue.withValues(alpha: 0.8),
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              '$coarseLat, $coarseLng (±${r.accuracyM.round()} m • ${r.locationSource})',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Precise coordinates are stored encrypted on-device. If police/insurer requests exact GPS, export via a dedicated signed report (not implemented yet).',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'AI triage',
              style: TextStyle(
                color: Colors.blue.withValues(alpha: 0.8),
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Severity ${r.triageSeverity}/5 • ${r.triageSourceName}${r.isBystander ? ' • bystander report' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (r.requiredServices.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Services flagged: ${r.requiredServices.join(', ')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Sync / storage',
              style: TextStyle(
                color: Colors.blue.withValues(alpha: 0.8),
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              r.syncStatusLine,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Text(
              'Channels',
              style: TextStyle(
                color: Colors.blue.withValues(alpha: 0.8),
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 8),
            DispatchStatusPanel(channels: r.channels),
          ],
        ),
      ),
    );
  }
}
