import 'first_aid_repository.dart';

/// Async first-aid lookup against the bundled FTS5 corpus (mobile) or token search (web).
/// Prefer [FirstAidRepository.instance.lookup] for direct access.
class FirstAidStore {
  static Future<String> getVerifiedAdvice(String query) =>
      FirstAidRepository.instance.lookup(query);

  static Future<List<String>> getSuggestions(String query) =>
      FirstAidRepository.instance.getSuggestions(query);
}
