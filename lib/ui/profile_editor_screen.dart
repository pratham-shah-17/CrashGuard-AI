import 'package:flutter/material.dart';
import 'package:roadsos/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/user_profile_service.dart';

class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key});

  @override
  ConsumerState<ProfileEditorScreen> createState() =>
      _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _bloodController;
  late TextEditingController _allergiesController;
  late TextEditingController _medsController;
  late TextEditingController _conditionsController;
  late TextEditingController _contactController;
  final List<TextEditingController> _additionalContactControllers = [];

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    _nameController = TextEditingController(text: profile.fullName);
    _bloodController = TextEditingController(text: profile.bloodType);
    _allergiesController = TextEditingController(text: profile.allergies);
    _medsController = TextEditingController(text: profile.medications);
    _conditionsController = TextEditingController(text: profile.conditions);
    _contactController = TextEditingController(text: profile.emergencyContact);

    for (final contact in profile.emergencyContacts) {
      _additionalContactControllers.add(TextEditingController(text: contact));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bloodController.dispose();
    _allergiesController.dispose();
    _medsController.dispose();
    _conditionsController.dispose();
    _contactController.dispose();
    for (final c in _additionalContactControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final newProfile = UserProfile(
      fullName: _nameController.text,
      bloodType: _bloodController.text,
      allergies: _allergiesController.text,
      medications: _medsController.text,
      conditions: _conditionsController.text,
      emergencyContact: _contactController.text,
      emergencyContacts: _additionalContactControllers
          .map((c) => c.text)
          .where((t) => t.isNotEmpty)
          .toList(),
    );

    ref.read(userProfileProvider.notifier).updateProfile(newProfile);

    if (!mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Medical Profile Updated')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'EDIT MEDICAL ID',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check, color: Colors.green),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildField('Full Name', _nameController, Icons.person),
            _buildField('Blood Type', _bloodController, Icons.bloodtype),
            _buildField('Allergies', _allergiesController, Icons.warning),
            _buildField(
              'Current Medications',
              _medsController,
              Icons.medication,
            ),
            _buildField(
              'Chronic Conditions',
              _conditionsController,
              Icons.medical_information,
            ),

            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'EMERGENCY CONTACTS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            _buildField(
              'Primary Contact',
              _contactController,
              Icons.contact_phone,
            ),

            ..._additionalContactControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        'Additional Contact ${index + 1}',
                        controller,
                        Icons.contact_phone,
                        showLabel: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(
                        () => _additionalContactControllers.removeAt(index),
                      ),
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              );
            }),

            TextButton.icon(
              onPressed: () => setState(
                () =>
                    _additionalContactControllers.add(TextEditingController()),
              ),
              icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
              label: const Text(
                'ADD CONTACT',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 40),
            Center(
              child: Text(
                AppLocalizations.of(context)!.profileAiLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool showLabel = true,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: showLabel ? 24 : 0),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          labelText: showLabel ? label.toUpperCase() : null,
          hintText: !showLabel ? label.toUpperCase() : null,
          hintStyle: TextStyle(color: Colors.white24, fontSize: 10),
          labelStyle: TextStyle(
            color: Colors.blue.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
          prefixIcon: Icon(icon, color: Colors.white24),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
