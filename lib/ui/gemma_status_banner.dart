import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gemma_auto_downloader.dart';

/// Compact banner that surfaces the on-device Gemma 4 E4B install progress.
///
/// Auto-hides when the model is ready. Tap → opens the Bystander Coach
/// onboarding which has the manual override (force cellular / paste token).
class GemmaStatusBanner extends ConsumerWidget {
  const GemmaStatusBanner({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(gemmaAutoDownloaderProvider);

    if (status.state == GemmaAutoState.ready ||
        status.state == GemmaAutoState.idle) {
      return const SizedBox.shrink();
    }

    final (icon, label, sub, color) = switch (status.state) {
      GemmaAutoState.waitingForWifi => (
        Icons.wifi_find_rounded,
        'Gemma 4 offline brain · waiting for Wi-Fi',
        'Downloads silently the moment you reach Wi-Fi (~2.4 GB).',
        const Color(0xFF4a90d9),
      ),
      GemmaAutoState.downloading => (
        Icons.download_rounded,
        'Installing Gemma 4 (${(status.fraction * 100).round()}%)',
        '${(status.received / 1e6).round()} MB / ${(status.total / 1e6).round()} MB · safe to keep using the app.',
        const Color(0xFF27c96b),
      ),
      GemmaAutoState.failed => (
        Icons.refresh_rounded,
        'Gemma 4 download paused',
        status.errorMessage ?? 'Will retry on next Wi-Fi.',
        const Color(0xFFFFB400),
      ),
      GemmaAutoState.optedOut => (
        Icons.cloud_outlined,
        'Cloud-only AI',
        'On-device brain disabled in Settings.',
        const Color(0xFF6b7a99),
      ),
      _ => (Icons.hourglass_top, 'Preparing…', '', const Color(0xFF6b7a99)),
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        color: Color(0xFFB9C2D6),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (status.state == GemmaAutoState.downloading) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: status.fraction,
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
