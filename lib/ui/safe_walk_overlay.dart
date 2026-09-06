import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/proactive_monitor_service.dart';

class SafeWalkOverlay extends ConsumerWidget {
  const SafeWalkOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(proactiveMonitorProvider);

    if (!monitor.isMonitoring) return const SizedBox.shrink();

    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: monitor.alertTriggered
                ? Colors.red.withValues(alpha: 0.9)
                : Colors.blue.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    monitor.alertTriggered
                        ? Icons.warning
                        : Icons.directions_walk,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          monitor.alertTriggered
                              ? 'CHECK-IN REQUIRED'
                              : 'SAFE-WALK ACTIVE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          monitor.alertTriggered
                              ? 'Confirm your safety now or SOS will trigger.'
                              : 'Heading to ${monitor.destination}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (monitor.alertTriggered)
                    TextButton(
                      onPressed: () => ref
                          .read(proactiveMonitorProvider.notifier)
                          .confirmImSafe(),
                      child: const Text(
                        'I AM SAFE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (monitor.destination != null &&
                      monitor.destination != 'your destination')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: () async {
                        final url = Uri.parse(
                          'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(monitor.destination!)}',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text(
                        'DIRECTIONS',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => ref
                        .read(proactiveMonitorProvider.notifier)
                        .endSafeWalk(),
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text(
                      'END SAFE PATH',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
