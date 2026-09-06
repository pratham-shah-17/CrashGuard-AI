import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'vehicle_rescue_data.dart';

/// VehicleRescueScreen
///
/// Allows a bystander to:
///   1. Select vehicle type (or enter plate number)
///   2. Get instant offline rescue steps specific to that vehicle
///   3. Works 100% offline — no internet required
///
/// Add to dashboard.dart:
///   import 'vehicle_rescue_screen.dart';
///   _buildActionItem(
///     icon: Icons.car_crash,
///     label: 'RESCUE',
///     onTap: () => Navigator.push(context,
///       MaterialPageRoute(builder: (_) => const VehicleRescueScreen())),
///   )

class VehicleRescueScreen extends StatefulWidget {
  const VehicleRescueScreen({super.key});

  @override
  State<VehicleRescueScreen> createState() => _VehicleRescueScreenState();
}

class _VehicleRescueScreenState extends State<VehicleRescueScreen> {
  // Currently selected vehicle key
  String? _selectedVehicleKey;

  // Plate number input
  final TextEditingController _plateController = TextEditingController();

  // Whether user is viewing rescue steps
  bool _showingRescueSteps = false;

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  // ── When user selects a vehicle type ──
  void _onVehicleSelected(String key) {
    setState(() {
      _selectedVehicleKey = key;
      _showingRescueSteps = true;
    });
  }

  // ── Go back to vehicle selection ──
  void _goBack() {
    setState(() {
      _showingRescueSteps = false;
      _selectedVehicleKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _showingRescueSteps
              ? _goBack
              : () => Navigator.pop(context),
        ),
        title: Text(
          _showingRescueSteps ? 'Rescue Guide' : 'Vehicle Rescue',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          // Offline badge — reassures user this works without internet
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.offline_bolt, color: Colors.green, size: 14),
                SizedBox(width: 4),
                Text(
                  'OFFLINE',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _showingRescueSteps && _selectedVehicleKey != null
            ? _buildRescueStepsView(_selectedVehicleKey!)
            : _buildVehicleSelectionView(),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // VIEW 1: VEHICLE SELECTION
  // ─────────────────────────────────────────────
  Widget _buildVehicleSelectionView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red.shade900.withValues(alpha: 0.6),
                  Colors.black,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.car_crash, color: Colors.red, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'VEHICLE RESCUE GUIDE',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Select the type of vehicle involved in the accident to get instant rescue instructions.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Plate number input
          const Text(
            'PLATE NUMBER (optional)',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _plateController,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'TN 11 AB 1234',
                hintStyle: TextStyle(color: Colors.white24, letterSpacing: 2),
                prefixIcon: Icon(Icons.badge, color: Colors.white38),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
              onChanged: (value) {
                final formatted = value.toUpperCase();
                if (formatted != value) {
                  _plateController.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(
                      offset: formatted.length,
                    ),
                  );
                }
              },
            ),
          ),

          const SizedBox(height: 28),

          // Vehicle type selection
          const Text(
            'SELECT VEHICLE TYPE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),

          // Vehicle type grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: kVehicleTypes.map((v) {
              return _buildVehicleCard(
                key: v['key']!,
                label: v['label']!,
                icon: v['icon']!,
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Bottom tip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.tips_and_updates, color: Colors.amber, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All rescue instructions work offline — no internet needed.',
                    style: TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Single vehicle card ──
  Widget _buildVehicleCard({
    required String key,
    required String label,
    required String icon,
  }) {
    final isEV = key == 'ev_car';

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _onVehicleSelected(key);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEV ? Colors.yellow.withValues(alpha: 0.4) : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isEV ? Colors.yellow : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            if (isEV)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'HIGH VOLTAGE',
                  style: TextStyle(
                    color: Colors.yellow,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // VIEW 2: RESCUE STEPS
  // ─────────────────────────────────────────────
  Widget _buildRescueStepsView(String vehicleKey) {
    final data = kVehicleRescueDatabase[vehicleKey];
    if (data == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vehicle header
          _buildVehicleHeader(data),
          const SizedBox(height: 16),

          // Dangers section
          _buildSectionTitle('⚠️  DANGERS — READ FIRST', Colors.red),
          const SizedBox(height: 8),
          _buildDangersCard(data.dangers),
          const SizedBox(height: 20),

          // Extraction steps
          _buildSectionTitle('👐  EXTRACTION STEPS', Colors.orange),
          const SizedBox(height: 8),
          ...data.extractionSteps.map((step) => _buildStepCard(step)),
          const SizedBox(height: 20),

          // First aid tips
          _buildSectionTitle('🩺  WHILE WAITING FOR AMBULANCE', Colors.blue),
          const SizedBox(height: 8),
          _buildFirstAidCard(data.firstAidTips),
          const SizedBox(height: 20),

          // Emergency call button
          _buildEmergencyCallButton(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Vehicle header card ──
  Widget _buildVehicleHeader(VehicleRescueData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Text(data.icon, style: const TextStyle(fontSize: 44)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.vehicleType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.description,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '⛽ ${data.fuelType}',
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section title ──
  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w900,
        fontSize: 13,
        letterSpacing: 1.2,
      ),
    );
  }

  // ── Dangers card ──
  Widget _buildDangersCard(List<String> dangers) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: dangers.map((danger) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              danger,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Single step card ──
  Widget _buildStepCard(RescueStep step) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: step.isCritical
            ? Colors.red.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: step.isCritical
              ? Colors.red.withValues(alpha: 0.3)
              : Colors.white12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number circle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: step.isCritical
                  ? Colors.red.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${step.stepNumber}',
                style: TextStyle(
                  color: step.isCritical ? Colors.red : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: TextStyle(
                          color: step.isCritical ? Colors.red : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (step.isCritical)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CRITICAL',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  step.detail,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── First aid tips card ──
  Widget _buildFirstAidCard(List<String> tips) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tips.map((tip) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tip,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Emergency call button ──
  Widget _buildEmergencyCallButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final uri = Uri(scheme: 'tel', path: '108');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not launch dialer. Please call 108 manually.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        icon: const Icon(Icons.call, size: 20),
        label: const Text(
          'CALL AMBULANCE — 108',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
