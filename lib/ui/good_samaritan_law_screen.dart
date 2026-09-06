import 'package:flutter/material.dart';
import 'package:roadsos/l10n/app_localizations.dart';

/// One-screen awareness of Good Samaritan protections (India).
class GoodSamaritanLawScreen extends StatelessWidget {
  const GoodSamaritanLawScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.goodSamaritanTitle),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.gavel, size: 56, color: Colors.green.shade400),
            const SizedBox(height: 24),
            Text(
              l10n.goodSamaritanLead,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  l10n.goodSamaritanBody,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.5,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green.shade800,
              ),
              child: Text(l10n.goodSamaritanContinue),
            ),
          ],
        ),
      ),
    );
  }
}
