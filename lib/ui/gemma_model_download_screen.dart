import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/gemma_model_manager.dart';

/// Full-screen onboarding screen for downloading the Gemma 4 E4B on-device model.
///
/// Shows during onboarding after permissions. The user can:
///   • Enter their HuggingFace token (obtained after accepting Gemma 4 terms)
///   • Download the ~2.4 GB model with live progress
///   • Pause/resume the download
///   • Skip to use cloud-only triage (Tier 1 still works without this)
///
/// Why a HuggingFace token?
/// Gemma 4 is a gated model — Google requires users to accept usage terms
/// before downloading. The token authenticates that acceptance.
/// Token is used ONLY for this one download and never stored long-term.
class GemmaModelDownloadScreen extends StatefulWidget {
  const GemmaModelDownloadScreen({super.key, required this.onComplete});

  /// Called when the user completes or skips the download.
  final VoidCallback onComplete;

  @override
  State<GemmaModelDownloadScreen> createState() =>
      _GemmaModelDownloadScreenState();
}

class _GemmaModelDownloadScreenState extends State<GemmaModelDownloadScreen> {
  final _tokenController = TextEditingController();
  final _tokenFocus = FocusNode();

  _Phase _phase = _Phase.check;

  // Download state
  int _received = 0;
  int _total = GemmaModelManager.approximateFullBytes;
  CancelToken? _cancelToken;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _tokenController.dispose();
    _tokenFocus.dispose();
    super.dispose();
  }

  Future<void> _checkExisting() async {
    final ready = await GemmaModelManager.isModelReady();
    final soFar = await GemmaModelManager.downloadedSoFar();
    if (!mounted) return;
    setState(() {
      if (ready) {
        _phase = _Phase.done;
      } else if (soFar > 0) {
        _received = soFar;
        _phase = _Phase.prompt;
      } else {
        _phase = _Phase.prompt;
      }
    });
  }

  Future<void> _startDownload() async {
    final token = _tokenController.text.trim();
    setState(() {
      _phase = _Phase.downloading;
      _errorMessage = null;
      _cancelToken = CancelToken();
    });

    try {
      await GemmaModelManager.downloadModel(
        hfToken: token.isEmpty ? null : token,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total > 0 ? total : GemmaModelManager.approximateFullBytes;
          });
        },
      );

      if (!mounted) return;
      if (_cancelToken?.isCancelled ?? false) {
        setState(() => _phase = _Phase.prompt);
      } else {
        setState(() {
          _phase = _Phase.done;
        });
      }
    } on GemmaDownloadException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.prompt;
        _errorMessage = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.prompt;
        _errorMessage = 'Download failed: $e';
      });
    }
  }

  void _pauseDownload() {
    _cancelToken?.cancel();
    setState(() => _phase = _Phase.prompt);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080b12),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(child: SingleChildScrollView(child: _buildBody())),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1e2a40))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4a90d9).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF4a90d9).withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.memory_rounded,
              color: Color(0xFF7bc8f8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gemma 4 On-Device AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Offline emergency triage — works without internet',
                  style: TextStyle(color: Color(0xFF6b7a99), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_phase == _Phase.done) _buildDoneState(),
          if (_phase == _Phase.prompt) ...[
            _buildExplainer(),
            const SizedBox(height: 24),
            _buildTokenInput(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorCard(),
            ],
            if (_received > 0 && !(_cancelToken?.isCancelled ?? false)) ...[
              const SizedBox(height: 16),
              _buildResumeNote(),
            ],
          ],
          if (_phase == _Phase.downloading) ...[_buildProgressPanel()],
          if (_phase == _Phase.check) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(color: Color(0xFF4a90d9)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExplainer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Why download this model?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _infoRow(
          Icons.wifi_off_rounded,
          'Works with no internet',
          'On Indian highways, cell coverage drops for kilometres at a time. '
              'Gemma 4 E4B triages your emergency without any network.',
        ),
        _infoRow(
          Icons.speed_rounded,
          'Instant offline triage',
          'Runs entirely on your phone — no round-trip to a server. '
              'Triage result in under 5 seconds even at 0 bar signal.',
        ),
        _infoRow(
          Icons.lock_rounded,
          'Privacy-first',
          'Your emergency description never leaves your phone when offline. '
              'No cloud, no logging, no third-party servers.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0f1420),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1e2a40)),
          ),
          child: const Row(
            children: [
              Icon(Icons.storage_rounded, color: Color(0xFF6b7a99), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Model size: ~2.4 GB  ·  Format: Q4_K_M GGUF  ·  Download once, works forever',
                  style: TextStyle(color: Color(0xFF6b7a99), fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'How to get your HuggingFace token',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _stepRow(
          '1',
          'View model card (optional)',
          'Gemma 4 is Apache 2.0 + ungated — no terms to accept',
          GemmaModelManager.hfModelCardUrl,
        ),
        _stepRow(
          '2',
          'Create a read token (only if rate-limited)',
          'Most users skip this step',
          GemmaModelManager.hfTokenUrl,
        ),
        _stepRow(
          '3',
          'Tap Download',
          'Empty token field is fine for nearly every user',
          null,
        ),
      ],
    );
  }

  Widget _buildTokenInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HuggingFace token',
          style: TextStyle(
            color: Color(0xFF6b7a99),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tokenController,
                focusNode: _tokenFocus,
                obscureText: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'hf_...',
                  hintStyle: const TextStyle(color: Color(0xFF6b7a99)),
                  filled: true,
                  fillColor: const Color(0xFF0f1420),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1e2a40)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1e2a40)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF4a90d9)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _actionButton(
              label: 'Download',
              color: const Color(0xFF4a90d9),
              onTap: _startDownload,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressPanel() {
    final percent = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : 0.0;
    final receivedMb = (_received / 1e6).toStringAsFixed(0);
    final totalMb = (_total / 1e6).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Downloading Gemma 4 E4B...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Keep the app open. You can pause and resume any time.',
          style: const TextStyle(color: Color(0xFF6b7a99), fontSize: 13),
        ),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: const Color(0xFF1e2a40),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4a90d9)),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$receivedMb MB / $totalMb MB',
              style: const TextStyle(color: Color(0xFF6b7a99), fontSize: 13),
            ),
            Text(
              '${(percent * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Color(0xFF4a90d9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _pauseDownload,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6b7a99),
              side: const BorderSide(color: Color(0xFF1e2a40)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Pause Download'),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneState() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF27c96b).withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF27c96b).withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF27c96b),
            size: 36,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Gemma 4 E4B Ready',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'On-device AI triage is active.\nRoadSOS will work even with zero cell signal.',
          style: TextStyle(color: Color(0xFF6b7a99), fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: widget.onComplete,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27c96b),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue to RoadSOS',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFe8354a).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFe8354a).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFe8354a),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xFFe8354a),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeNote() {
    final mb = (_received / 1e6).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF4a90d9).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF4a90d9).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.restore_rounded, color: Color(0xFF4a90d9), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Partial download found ($mb MB). Tap Download to resume.',
              style: const TextStyle(color: Color(0xFF7bc8f8), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          const Divider(color: Color(0xFF1e2a40), height: 1),
          const SizedBox(height: 16),
          if (_phase != _Phase.done)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: widget.onComplete,
                child: const Text(
                  'Skip — use cloud AI only for now',
                  style: TextStyle(color: Color(0xFF6b7a99), fontSize: 13),
                ),
              ),
            ),
          const Text(
            'Your token is used only for this download and is not stored after completion.',
            style: TextStyle(color: Color(0xFF3d4a60), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF4a90d9), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF6b7a99),
                    fontSize: 12.5,
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

  Widget _stepRow(String num, String title, String sub, String? url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFF4a90d9).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF4a90d9).withValues(alpha: 0.4),
              ),
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: Color(0xFF7bc8f8),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: url != null ? () => _openUrl(url) : null,
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: url != null
                              ? const Color(0xFF7bc8f8)
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: url != null
                              ? TextDecoration.underline
                              : null,
                          decorationColor: const Color(0xFF7bc8f8),
                        ),
                      ),
                      if (url != null) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 12,
                          color: Color(0xFF7bc8f8),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    color: Color(0xFF6b7a99),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

enum _Phase { check, prompt, downloading, done }
