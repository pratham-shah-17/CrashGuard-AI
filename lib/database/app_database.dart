import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:powersync/powersync.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../logging/app_log.dart';
import '../services/government_facility_seed_service.dart';
import 'schema.dart';

/// True after [bootstrapSupabaseAuth] successfully calls [Supabase.initialize].
bool _supabaseSdkInitialized = false;

bool get isSupabaseSdkInitialized => _supabaseSdkInitialized;

/// Initializes Supabase and anonymous auth **at app launch** (before [initializeDatabase]).
/// Requires [dotenv.load] first. Safe no-op when URL/key missing or on web.
Future<void> bootstrapSupabaseAuth() async {
  if (kIsWeb) return;

  final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
  final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
  if (url.isEmpty || anonKey.isEmpty) {
    _supabaseSdkInitialized = false;
    appLog.w(
      'Supabase bootstrap skipped — set SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define or local .env',
    );
    return;
  }

  try {
    await Supabase.initialize(url: url, publishableKey: anonKey);
    await ensureSupabaseAnonymousSession(Supabase.instance.client);
    _supabaseSdkInitialized = true;
    appLog.i('Supabase anonymous sign-in completed.');
  } on Object catch (e, st) {
    _supabaseSdkInitialized = false;
    appLog.e('Supabase bootstrap failed', error: e, stackTrace: st);
  }
}

/// Ensures a JWT exists for PowerSync ([fetchCredentials]). Call after [Supabase.initialize].
Future<void> ensureSupabaseAnonymousSession(SupabaseClient client) async {
  try {
    final existing = client.auth.currentSession;
    if (existing != null && !existing.isExpired) {
      return;
    }
    if (existing != null) {
      try {
        await client.auth.refreshSession();
        final after = client.auth.currentSession;
        if (after != null && !after.isExpired) {
          return;
        }
      } on Object catch (e, st) {
        appLog.w(
          'Session refresh failed; re-authenticating',
          error: e,
          stackTrace: st,
        );
      }
    }
    await client.auth.signInAnonymously();
  } on Object catch (e, st) {
    appLog.w('Anonymous auth failed', error: e, stackTrace: st);
  }
}

class SupabaseConnector extends PowerSyncBackendConnector {
  final SupabaseClient db;

  SupabaseConnector(this.db);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    await ensureSupabaseAnonymousSession(db);
    final session = db.auth.currentSession;
    if (session == null) {
      appLog.w(
        'PowerSync fetchCredentials: no session — enable Anonymous sign-ins in Supabase '
        'or check SUPABASE_URL / SUPABASE_ANON_KEY',
      );
      return null;
    }
    return PowerSyncCredentials(
      endpoint: dotenv.env['POWERSYNC_URL'] ?? '',
      token: session.accessToken,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    try {
      for (var op in transaction.crud) {
        if (op.op == UpdateType.put) {
          await db.from(op.table).upsert(op.opData!);
        } else if (op.op == UpdateType.patch) {
          await db.from(op.table).update(op.opData!).eq('id', op.id);
        } else if (op.op == UpdateType.delete) {
          await db.from(op.table).delete().eq('id', op.id);
        }
      }
      await transaction.complete();
    } on Object catch (e, st) {
      appLog.e('PowerSync upload error', error: e, stackTrace: st);
    }
  }
}

late PowerSyncDatabase appDb;
bool _dbInitialized = false;

Future<void> initializeDatabase() async {
  if (kIsWeb) {
    appLog.i('Running on Web — PowerSync/SQLite disabled.');
    _dbInitialized = false;
    return;
  }

  try {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'roadsos.sqlite');

    appDb = PowerSyncDatabase(schema: schema, path: path);
    await appDb.initialize();
    await GovernmentFacilitySeedService().importBundledSeedIfNeeded(appDb);

    final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

    if (url.isEmpty || anonKey.isEmpty) {
      appLog.w(
        'SUPABASE_URL / SUPABASE_ANON_KEY missing — local SQLite only. '
        'Set credentials via --dart-define or local .env (not in Dart source) and enable RLS in Supabase.',
      );
      _dbInitialized = true;
      return;
    }

    if (!_supabaseSdkInitialized) {
      appLog.e(
        'PowerSync aborted — call [bootstrapSupabaseAuth] in main() before '
        '[initializeDatabase] when Supabase credentials are set.',
      );
      _dbInitialized = true;
      return;
    }

    await ensureSupabaseAnonymousSession(Supabase.instance.client);
    if (Supabase.instance.client.auth.currentSession == null) {
      appLog.w(
        'No Supabase session — enable Anonymous provider in Supabase '
        'and check URL/anon key. PowerSync will not sync until auth succeeds.',
      );
    }

    appDb.connect(connector: SupabaseConnector(Supabase.instance.client));
    _dbInitialized = true;
    appLog.i('PowerSync + Supabase initialized.');
  } on Object catch (e, st) {
    appLog.e('Database initialization failed', error: e, stackTrace: st);
    _dbInitialized = false;
  }
}

bool get isDatabaseInitialized => _dbInitialized;
