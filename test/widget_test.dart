import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

/// VM/widget tests cannot fully mount [RoadSOSApp] without extra harness:
/// `google_fonts` runtime fetching + Supabase auth timers fail under the default
/// test binding. Use `integration_test/` or drive `flutter run` for full smoke.
void main() {
  test('dotenv loads strings used by RuntimeConfig / bootstrap', () {
    dotenv.loadFromString(
      envString:
          'SUPABASE_URL=https://example.supabase.co\nSUPABASE_ANON_KEY=test_anon',
    );
    expect(dotenv.env['SUPABASE_URL'], contains('supabase'));
    expect(dotenv.env['SUPABASE_ANON_KEY'], 'test_anon');
  });
}
