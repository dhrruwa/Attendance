import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Initializes the global Supabase client. Call once at app startup.
class SupabaseInit {
  static Future<SupabaseClient> ensureInitialized(AppConfig config) async {
    if (!config.isValid) {
      throw StateError(
        'Supabase config missing. Pass --dart-define=SUPABASE_URL=... and '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=... (see README).',
      );
    }
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    return Supabase.instance.client;
  }

  static SupabaseClient get client => Supabase.instance.client;
}
