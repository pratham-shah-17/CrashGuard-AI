import 'package:flutter/material.dart';
import '../models/dispatch_channel_status.dart';

/// Honest per-channel dispatch states (SMS, mesh, cloud) — no fake “help is coming” timer.
class DispatchStatusPanel extends StatelessWidget {
  final List<DispatchChannelRow> channels;
  final bool isBeaconActive;

  const DispatchStatusPanel({
    super.key,
    required this.channels,
    this.isBeaconActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (channels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      container: true,
      label: 'Dispatch status list',
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  'DISPATCH STATUS',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    color: scheme.onSurface.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isBeaconActive) _BeaconBanner(scheme: scheme),
              for (final row in channels)
                _DispatchRow(row: row, scheme: scheme),
            ],
          ),
        ),
      ),
    );
  }
}

class _DispatchRow extends StatelessWidget {
  final DispatchChannelRow row;
  final ColorScheme scheme;

  const _DispatchRow({required this.row, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = _iconFor(row.lifecycle, scheme);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  row.detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.87),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _iconFor(
    DispatchChannelLifecycle life,
    ColorScheme scheme,
  ) {
    switch (life) {
      case DispatchChannelLifecycle.pending:
        return (Icons.radio_button_unchecked, scheme.outline);
      case DispatchChannelLifecycle.inProgress:
        return (Icons.pending_outlined, scheme.primary);
      case DispatchChannelLifecycle.success:
        return (Icons.check_circle_rounded, scheme.secondary);
      case DispatchChannelLifecycle.failed:
        return (Icons.error_outline_rounded, scheme.error);
      case DispatchChannelLifecycle.skipped:
        return (Icons.do_not_disturb_on_outlined, scheme.outline);
    }
  }
}

class _BeaconBanner extends StatefulWidget {
  final ColorScheme scheme;
  const _BeaconBanner({required this.scheme});

  @override
  State<_BeaconBanner> createState() => _BeaconBannerState();
}

class _BeaconBannerState extends State<_BeaconBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.scheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: widget.scheme.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.emergency_share, color: widget.scheme.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'RESCUE BEACON ACTIVE: FLASH + SIREN',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: widget.scheme.error,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
