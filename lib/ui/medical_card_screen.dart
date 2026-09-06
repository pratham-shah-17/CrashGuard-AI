import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/user_profile_service.dart';
import 'profile_editor_screen.dart';

class MedicalCardScreen extends ConsumerWidget {
  const MedicalCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);

    // QR contains a short, offline-safe summary (no network dependency).
    final qrData =
        'ROADSOS_MEDICAL_V1|NAME:${profile.fullName}|BLOOD:${profile.bloodType}|ALLERGIES:${profile.allergies}|MEDS:${profile.medications}|CONTACT:${profile.emergencyContact}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'EMERGENCY MEDICAL ID',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileEditorScreen()),
            ),
            icon: const Icon(Icons.edit, size: 20),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Dynamic QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200,
                gapless: false,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'SCAN FOR MEDICAL SUMMARY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.white54,
              ),
            ),

            const SizedBox(height: 48),
            _buildInfoRow(
              Icons.person,
              'FULL NAME',
              profile.fullName.isEmpty ? 'NOT SET' : profile.fullName,
            ),
            _buildDivider(),
            _buildInfoRow(Icons.bloodtype, 'BLOOD TYPE', profile.bloodType),
            _buildDivider(),
            _buildInfoRow(Icons.warning, 'ALLERGIES', profile.allergies),
            _buildDivider(),
            _buildInfoRow(
              Icons.contact_phone,
              'EMERGENCY CONTACT',
              profile.emergencyContact.isEmpty
                  ? 'NOT SET'
                  : profile.emergencyContact,
            ),

            const Spacer(),
            const Text(
              'Tip: Keep this screen open for responders. For lock-screen wallpaper export, use your device screenshot tools.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.red, size: 28),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white38,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(color: Colors.white.withValues(alpha: 0.1), height: 1);
  }
}
