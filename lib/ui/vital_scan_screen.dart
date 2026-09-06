import 'package:flutter/material.dart';
import 'package:roadsos/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/vital_signs_service.dart';

class VitalScanScreen extends ConsumerStatefulWidget {
  const VitalScanScreen({super.key});

  @override
  ConsumerState<VitalScanScreen> createState() => _VitalScanScreenState();
}

class _VitalScanScreenState extends ConsumerState<VitalScanScreen>
    with TickerProviderStateMixin {
  final _bpmCtrl = TextEditingController();
  final _rrCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _bpmCtrl.dispose();
    _rrCtrl.dispose();
    _spo2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vitals = ref.watch(vitalSignsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.vitalScanTitle,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
            ),
            child: Text(
              'Enter vitals manually. RoadSOS does not measure SpO₂/HR from the camera in this build.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _field(label: 'Pulse (BPM)', controller: _bpmCtrl, hint: 'e.g., 92'),
          const SizedBox(height: 12),
          _field(
            label: 'Respiratory rate (per min)',
            controller: _rrCtrl,
            hint: 'e.g., 18',
          ),
          const SizedBox(height: 12),
          _field(label: 'SpO₂ (%)', controller: _spo2Ctrl, hint: 'e.g., 97'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _save(),
                    icon: const Icon(Icons.check),
                    label: const Text('SAVE VITALS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () =>
                      ref.read(vitalSignsProvider.notifier).clear(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('CLEAR'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (vitals != null) ...[
            _buildVitalsGrid(vitals),
            const SizedBox(height: 14),
            _buildInterpretationCard(vitals),
          ],
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)!.vitalAlignFinger,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.blue),
        ),
      ),
    );
  }

  Widget _buildVitalsGrid(VitalSigns vitals) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildVitalItem('BPM', '${vitals.bpm}', Icons.favorite, Colors.red),
          _buildVitalItem(
            'RESP',
            '${vitals.respiratoryRate}',
            Icons.air,
            Colors.blue,
          ),
          _buildVitalItem(
            'SPO2',
            '${vitals.bloodOxygen.toStringAsFixed(1)}%',
            Icons.bloodtype,
            Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildVitalItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildInterpretationCard(VitalSigns vitals) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology, color: Colors.blue),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              vitals.interpretation,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final bpm = int.tryParse(_bpmCtrl.text.trim());
    final rr = int.tryParse(_rrCtrl.text.trim());
    final spo2 = double.tryParse(_spo2Ctrl.text.trim());

    if (bpm == null || rr == null || spo2 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid numbers for BPM, RESP, and SpO₂.'),
        ),
      );
      return;
    }

    ref
        .read(vitalSignsProvider.notifier)
        .setManual(
          bpm: bpm.clamp(20, 240),
          respiratoryRate: rr.clamp(4, 60),
          bloodOxygen: spo2.clamp(50.0, 100.0),
        );

    FocusScope.of(context).unfocus();
  }
}
