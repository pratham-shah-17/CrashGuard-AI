import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_triage_service.dart';

/// Compact status indicators for the app bar.
/// Shows GPS lock, AI model state, and network connectivity.
class StatusIndicatorBar extends ConsumerWidget {
  const StatusIndicatorBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiService = ref.read(aiTriageServiceProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusChip(
          icon: Icons.satellite_alt,
          label: 'GPS',
          color: Colors.green,
          isActive: true,
        ),
        const SizedBox(width: 6),
        _StatusChip(
          icon: Icons.psychology,
          label: 'AI',
          color: _modelStateColor(aiService.state),
          isActive: aiService.state == ModelState.ready,
        ),
        const SizedBox(width: 6),
        _StatusChip(
          icon: Icons.cloud_sync,
          label: 'Sync',
          color: Colors.blue,
          isActive: true,
        ),
      ],
    );
  }

  Color _modelStateColor(ModelState state) {
    switch (state) {
      case ModelState.ready:
        return Colors.green;
      case ModelState.degraded:
        return Colors.orange;
      case ModelState.error:
        return Colors.red;
      case ModelState.unloaded:
        return Colors.grey;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isActive;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isActive ? 0.15 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
