import 'package:flutter/material.dart';
import 'package:roadsos/l10n/app_localizations.dart';
import '../services/privacy_consent_service.dart';
import 'privacy_policy_screen.dart';
import 'roadsos_logo.dart';

/// First-launch explicit consent (DPDP Act, 2023).
class ConsentScreen extends StatefulWidget {
  final VoidCallback onAccepted;

  const ConsentScreen({super.key, required this.onAccepted});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _extendedRetention = false;

  Future<void> _accept() async {
    await PrivacyConsentService.recordConsent(
      extendedCloudRetention: _extendedRetention,
    );
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: RoadSOSLogo(size: 72)),
              const SizedBox(height: 24),
              Text(
                l10n.consentTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    l10n.consentSummary,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.45,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _extendedRetention,
                onChanged: (v) =>
                    setState(() => _extendedRetention = v ?? false),
                title: Text(
                  l10n.consentExtendedRetentionLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                tileColor: Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                ),
                child: Text(l10n.consentPrivacyButton),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _accept,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue.shade700,
                ),
                child: Text(l10n.consentAccept),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
