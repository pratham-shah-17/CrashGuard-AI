import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_locale_controller.dart';
import '../services/first_aid_repository.dart';
import '../services/first_aid_store.dart';

class FirstAidScreen extends ConsumerStatefulWidget {
  const FirstAidScreen({super.key});

  @override
  ConsumerState<FirstAidScreen> createState() => _FirstAidScreenState();
}

class _FirstAidScreenState extends ConsumerState<FirstAidScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  String _result = '';
  String? _error;
  List<String> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = _textController.text;
      if (query.length < 2) {
        if (_suggestions.isNotEmpty && mounted) {
          setState(() => _suggestions = []);
        }
        return;
      }

      final suggestions = await FirstAidStore.getSuggestions(query);
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
        });
      }
    });
  }

  Future<void> _lookupFirstAid(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _result = '';
      _error = null;
      _suggestions = []; // Clear suggestions on submit
    });

    try {
      // Gemma 4 27B (cloud) synthesises a calm step-by-step answer grounded
      // in the FTS corpus. Falls back to the raw FTS row when the cloud is
      // unreachable, so the screen never blanks out.
      final lang = ref.read(appLocaleProvider).languageCode;
      final res = await FirstAidRepository.instance.lookupWithGemma(
        query,
        languageCode: lang,
      );
      if (!mounted) return;
      setState(() {
        _result = res;
      });
      // Side-channel: keep FirstAidStore primed (used elsewhere) — best-effort.
      // ignore: discarded_futures
      FirstAidStore.getVerifiedAdvice(query);
    } on Object {
      setState(() {
        _error = 'Could not load first-aid guidance on this device.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        title: const Text(
          '🩺 First Aid Guide',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Input row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Describe injury...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (val) => _lookupFirstAid(val),
                  ),
                ),

                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    _lookupFirstAid(_textController.text);
                  },
                  icon: const Icon(Icons.send, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),

            // Suggestions List
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4, left: 4, right: 80),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        suggestion,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      onTap: () {
                        _textController.text = suggestion;
                        _lookupFirstAid(suggestion);
                      },
                    );
                  },
                ),
              ),

            const SizedBox(height: 12),

            // Loading
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(color: Colors.red),
                ),
              ),

            if (_error != null && !_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_result.isNotEmpty && !_isLoading)
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.25),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.medical_services_outlined,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Verified Medical Solutions',
                              style: TextStyle(
                                color: Colors.redAccent.withValues(alpha: 0.8),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 24),
                        MarkdownBody(
                          data: _result,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                              color: Colors.white,
                              height: 1.6,
                              fontSize: 15,
                            ),
                            strong: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                            listBullet: const TextStyle(
                              color: Colors.redAccent,
                            ),
                            h1: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            h2: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (_result.isEmpty && _error == null && !_isLoading)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.health_and_safety,
                          size: 80,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'AI Injury Identification',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Type an injury to get\nexact, verified first aid solutions.',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildChip('Severe Bleeding'),
                          _buildChip('Muscle Tear'),
                          _buildChip('Brain Injury'),
                          _buildChip('Sprains'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _lookupFirstAid(label),
      backgroundColor: const Color(0xFF1A1A2E),
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
