import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../logging/app_log.dart';

/// Evidence-based first-aid text bundled in assets and indexed with SQLite FTS5
/// on the **same** PowerSync database as the rest of the app (no separate sqflite DB).
///
/// **Not a substitute for professional training or emergency services.** Always call local EMS.
class _FirstAidEntry {
  _FirstAidEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.tags,
    required this.source,
  }) : titleLower = title.toLowerCase(),
       tagsLower = tags.toLowerCase(),
       // ⚡ Bolt Optimization: Pre-compute lowercased fields and search haystack
       // during initialization to eliminate redundant String allocations and
       // expensive .toLowerCase() calls inside frequent search loops.
       searchHaystackLower = '$title $body $tags'.toLowerCase();

  final String id;
  final String title;
  final String body;
  final String tags;
  final String source;

  final String titleLower;
  final String tagsLower;
  final String searchHaystackLower;
}

class FirstAidRepository {
  FirstAidRepository._();

  static final FirstAidRepository instance = FirstAidRepository._();

  static const String assetPath = 'assets/first_aid/corpus.json';

  List<_FirstAidEntry>? _corpusEntries;
  bool _ftsReady = false;

  static const String medicalDisclaimer =
      'This guidance summarizes generic first-aid teaching aligned with international '
      'resuscitation consensus (verify against current WHO/ILCOR/AHA guidance and local protocols). '
      'It is not medical advice. In India dial 108 (or 112 ERSS) for ambulance / coordinated emergency '
      'response where available — follow dispatcher instructions.';

  Future<void> ensureInitialized() async {
    if (_corpusEntries == null) {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw) as List<dynamic>;
      _corpusEntries = decoded.cast<Map<String, dynamic>>().map((row) {
        return _FirstAidEntry(
          id: row['id'] as String? ?? '',
          title: row['title'] as String? ?? '',
          body: row['body'] as String? ?? '',
          tags: row['tags'] as String? ?? '',
          source: row['source'] as String? ?? '',
        );
      }).toList();
    }
    if (kIsWeb || !isDatabaseInitialized || _ftsReady) {
      return;
    }
    await appDb.execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS first_aid_fts USING fts5(
  title,
  body,
  tags,
  source
);
''');

    final countRows = await appDb.getAll(
      'SELECT COUNT(*) AS c FROM first_aid_fts',
    );
    final count = (countRows.first['c'] as num?)?.toInt() ?? 0;

    if (count == 0 && _corpusEntries!.isNotEmpty) {
      final parameterSets = _corpusEntries!
          .map((entry) => [entry.title, entry.body, entry.tags, entry.source])
          .toList();

      await appDb.executeBatch('''
        INSERT INTO first_aid_fts (title, body, tags, source)
        VALUES (?, ?, ?, ?)
        ''', parameterSets);
    }
    _ftsReady = true;
  }

  /// Full-text search; returns formatted guidance with title, body, source, disclaimer.
  Future<String> lookup(String query) async {
    await ensureInitialized();
    final q = query.trim();
    if (q.isEmpty) {
      return _pickGeneralOrFirst();
    }

    if (kIsWeb || !isDatabaseInitialized || !_ftsReady) {
      return _lookupTokenScore(q);
    }
    return _lookupFts(q);
  }

  /// Public RAG entry point: retrieve grounding from the FTS corpus, then ask
  /// Gemma 4 27B (cloud) to synthesise a calm, step-by-step answer in the
  /// user's locale. Falls back to the raw corpus result if cloud is down /
  /// times out / Supabase is not configured.
  ///
  /// This is the recommended call for the First Aid screen and any UI that
  /// shows guidance to a human bystander — it produces locale-correct,
  /// reading-friendly steps instead of a raw corpus row.
  ///
  /// `languageCode` is passed through so the model produces output in the
  /// reader's language (en/hi/ta/te/bn/mr).
  Future<String> lookupWithGemma(
    String query, {
    String languageCode = 'en',
    Duration cloudTimeout = const Duration(seconds: 5),
  }) async {
    final grounding = await lookup(query);
    if (kIsWeb || query.trim().isEmpty) return grounding;

    final composed = await _gemmaCompose(
      query: query,
      grounding: grounding,
      languageCode: languageCode,
      cloudTimeout: cloudTimeout,
    );
    if (composed != null && composed.trim().isNotEmpty) {
      return '$composed\n\n---\n$medicalDisclaimer';
    }
    return grounding;
  }

  Future<String?> _gemmaCompose({
    required String query,
    required String grounding,
    required String languageCode,
    required Duration cloudTimeout,
  }) async {
    final langLabel = switch (languageCode) {
      'hi' => 'Hindi (Devanagari)',
      'ta' => 'Tamil',
      'te' => 'Telugu',
      'bn' => 'Bengali',
      'mr' => 'Marathi (Devanagari)',
      _ => 'English',
    };
    // Cap grounding so we never blow the token budget on a tiny prompt.
    final clipped = grounding.length > 2400
        ? grounding.substring(0, 2400)
        : grounding;
    final prompt =
        'You are RoadSOS First Aid Coach. Produce a short, calm, step-by-step '
        'answer that the bystander can read aloud. Constraints:\n'
        '- Output in $langLabel only.\n'
        '- Maximum 6 numbered steps, each <= 22 words.\n'
        '- Plain words, no jargon, no medication doses, no markdown headings.\n'
        '- If situation looks life-threatening, step 1 MUST be "Call 108 (or 112) now".\n'
        '- Never invent steps that are not supported by the GROUNDING TEXT.\n'
        '- End with the line: "Stay with them until help arrives."\n\n'
        'BYSTANDER QUESTION:\n"""$query"""\n\n'
        'GROUNDING TEXT (verbatim from RoadSOS first-aid corpus):\n'
        '"""\n$clipped\n"""';

    try {
      final client = Supabase.instance.client;
      final res = await client.functions
          .invoke(
            'gemini-generate',
            body: <String, dynamic>{
              'prompt': prompt,
              'model': 'gemma-4-27b-it',
              'temperature': 0.25,
              'max_output_tokens': 320,
            },
          )
          .timeout(cloudTimeout);
      final data = res.data;
      if (data is Map && data['text'] is String) {
        return (data['text'] as String).trim();
      }
      return null;
    } on Object catch (e, st) {
      appLog.d('[FirstAid] Gemma 4 compose failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// Returns a list of titles for autocomplete suggestions.
  Future<List<String>> getSuggestions(String query) async {
    await ensureInitialized();
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    final suggestions = <String>[];
    for (final entry in _corpusEntries!) {
      if (entry.titleLower.contains(q) || entry.tagsLower.contains(q)) {
        suggestions.add(entry.title);
      }
      if (suggestions.length >= 6) break;
    }
    return suggestions;
  }

  String _lookupTokenScore(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) {
      return _pickGeneralOrFirst();
    }

    var bestScore = -1;
    _FirstAidEntry? best;
    for (final entry in _corpusEntries!) {
      final haystack = entry.searchHaystackLower;
      var score = 0;
      for (final t in tokens) {
        if (haystack.contains(t)) score += 3;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }

    if (best == null || bestScore <= 0) {
      return _pickGeneralOrFirst();
    }

    return _formatResult(
      title: best.title,
      body: best.body,
      source: best.source,
    );
  }

  Future<String> _lookupFts(String query) async {
    final ftsQuery = _buildFtsQuery(query);
    List<Map<String, Object?>> rows;

    try {
      rows = await appDb.getAll(
        '''
        SELECT title, body, source
        FROM first_aid_fts
        WHERE first_aid_fts MATCH ?
        LIMIT 4
        ''',
        [ftsQuery],
      );
    } on Object {
      rows = [];
    }

    if (rows.isEmpty) {
      try {
        rows = await appDb.getAll(
          '''
          SELECT title, body, source
          FROM first_aid_fts
          WHERE first_aid_fts MATCH ?
          LIMIT 3
          ''',
          ['general OR trauma OR emergency OR india OR 108'],
        );
      } on Object {
        rows = [];
      }
    }

    if (rows.isEmpty) {
      return _pickGeneralOrFirst();
    }

    final buf = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (i > 0) buf.writeln('\n---\n');
      buf.writeln(
        _formatResult(
          title: r['title'] as String? ?? '',
          body: r['body'] as String? ?? '',
          source: r['source'] as String? ?? '',
          includeDisclaimer: false,
        ),
      );
    }
    buf.writeln('\n---\n$medicalDisclaimer');
    return buf.toString();
  }

  String _pickGeneralOrFirst() {
    _FirstAidEntry? row;
    for (final r in _corpusEntries!) {
      if (r.id == 'general-road-emergency-india') {
        row = r;
        break;
      }
    }
    row ??= _corpusEntries!.first;
    return _formatResult(title: row.title, body: row.body, source: row.source);
  }

  List<String> _tokenize(String q) {
    return q
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();
  }

  /// FTS5 MATCH: OR token groups; strip FTS specials.
  String _buildFtsQuery(String raw) {
    final tokens = _tokenize(raw);
    if (tokens.isEmpty) return 'general OR emergency OR trauma';
    final escaped = tokens.map(_escapeFtsToken).where((t) => t.isNotEmpty);
    return escaped.join(' OR ');
  }

  String _escapeFtsToken(String t) {
    final safe = t.replaceAll('"', '');
    if (safe.isEmpty) return '';
    return '"$safe"';
  }

  String _formatResult({
    required String title,
    required String body,
    required String source,
    bool includeDisclaimer = true,
  }) {
    final buf = StringBuffer()
      ..writeln('**$title**')
      ..writeln()
      ..writeln(body.trim())
      ..writeln()
      ..writeln('Source: $source');
    if (includeDisclaimer) {
      buf.writeln('\n---\n$medicalDisclaimer');
    }
    return buf.toString();
  }
}

/// Call from [main] after [initializeDatabase] so FTS lives on [appDb].
Future<void> initializeFirstAidRepository() async {
  await FirstAidRepository.instance.ensureInitialized();
}
