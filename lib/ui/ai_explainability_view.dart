import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsos/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ai_triage_service.dart';

/// Phase 10 — Reliability & explainability panel.
///
/// Displays the full reasoning chain for a triage decision:
///   • Source tier (Gemma 4 27B cloud / E4B on-device / heuristic / classifier)
///   • Confidence score with color-coded label
///   • Gemma's thinking trace (when available)
///   • Validation agent overrides — every rule that fired and what it changed
///   • Quick-action buttons: Google Maps (Phase 6), Call 112 (Phase 6)
///
/// The user always has manual control: the "Call 112" button is visible
/// regardless of whether automated dispatch succeeded, satisfying the
/// Phase 10 requirement that a manual override is always available.
class AiExplainabilityView extends ConsumerWidget {
  final TriageResult triage;

  const AiExplainabilityView({super.key, required this.triage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(77),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.psychology, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.aiThinkingTraceTitle,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
              ),
              // Confidence badge
              _ConfidenceBadge(
                confidence: triage.confidence,
                label: triage.confidenceLabel,
              ),
            ],
          ),

          const Divider(height: 20),

          // ── Source tier ───────────────────────────────────────────────────
          _InfoRow(
            icon: Icons.hub_outlined,
            label: 'Source',
            value: triage.sourceLabel,
            valueColor: scheme.primary,
          ),
          const SizedBox(height: 6),

          // ── Thinking trace ────────────────────────────────────────────────
          if (triage.thinkingTrace != null) ...[
            Text(
              triage.thinkingTrace!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── Validation overrides (Phase 3) ────────────────────────────────
          if (triage.wasOverridden && triage.validationNotes.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withAlpha(102)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Safety validation — rule-based overrides applied',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber.shade800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...triage.validationNotes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: TextStyle(
                              color: Colors.amber.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              note,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface.withAlpha(230),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ── First-aid source tag ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(31),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              triage.source == TriageSource.offlineClassifier
                  ? 'First-aid: curated offline library (WHO/ILCOR aligned)'
                  : 'First-aid: RAG from curated library (WHO/ILCOR aligned)',
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Phase 6: Android ecosystem quick-action buttons ───────────────
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.map_outlined,
                  label: 'Open in Maps',
                  color: Colors.green.shade700,
                  onTap: () => _openMaps(triage.location),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.phone_outlined,
                  label: 'Call 112',
                  color: Colors.red.shade700,
                  onTap: _call112,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Phase 6: Android Intent helpers ──────────────────────────────────────

  Future<void> _openMaps(String locationString) async {
    // locationString is "lat,lng" — build a Google Maps geo URI.
    final parts = locationString.split(',');
    if (parts.length < 2) return;
    final lat = parts[0].trim();
    final lng = parts[1].trim();
    final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(Emergency+SOS+Location)');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback to browser-based Maps if no geo handler.
      final web = Uri.parse('https://maps.google.com/?q=$lat,$lng');
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _call112() async {
    final uri = Uri(scheme: 'tel', path: '112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  final String label;

  const _ConfidenceBadge({required this.confidence, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = confidence >= 0.80
        ? Colors.green.shade700
        : confidence >= 0.60
        ? Colors.orange.shade700
        : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(102)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            confidence >= 0.80
                ? Icons.verified_outlined
                : confidence >= 0.60
                ? Icons.info_outline
                : Icons.warning_amber_outlined,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '$label confidence',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: valueColor ?? scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(26),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(77)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
