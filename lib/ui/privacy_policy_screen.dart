import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:roadsos/l10n/app_localizations.dart';

/// In-app privacy notice (bundled EN/HI text assets; DPDP-aligned summary).
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  static const _assets = [
    'assets/legal/privacy_policy_en.txt',
    'assets/legal/privacy_policy_hi.txt',
  ];

  int _tab = 0;
  String _en = '';
  String _hi = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final en = await rootBundle.loadString(_assets[0]);
      final hi = await rootBundle.loadString(_assets[1]);
      if (mounted) {
        setState(() {
          _en = en;
          _hi = hi;
        });
      }
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _en = 'Privacy text asset missing.';
          _hi = 'गोपनीयता पाठ उपलब्ध नहीं।';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.privacyPolicyTitle),
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(l10n.privacyPolicyLanguageEn),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(l10n.privacyPolicyLanguageHi),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Text(
                _tab == 0 ? _en : _hi,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
