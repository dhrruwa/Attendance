/// Shared library: models, evidence schema, Supabase client/repositories, BLE
/// token logic, and Riverpod providers used by both the teacher and student apps.
library;

// Config
export 'src/config/app_config.dart';

// Models
export 'src/models/enums.dart';
export 'src/models/institution.dart';
export 'src/models/app_user.dart';
export 'src/models/course.dart';
export 'src/models/enrollment.dart';
export 'src/models/device.dart';
export 'src/models/session.dart';
export 'src/models/session_token.dart';
export 'src/models/attendance.dart';

// Evidence
export 'src/evidence/evidence.dart';

// BLE
export 'src/ble/session_token_source.dart';
export 'src/ble/ble_advertiser.dart';
export 'src/ble/ble_scanner.dart';

// Supabase
export 'src/supabase/supabase_init.dart';
export 'src/supabase/auth_repository.dart';
export 'src/supabase/device_repository.dart';
export 'src/supabase/course_repository.dart';
export 'src/supabase/session_repository.dart';
export 'src/supabase/attendance_repository.dart';

// Providers
export 'src/providers/providers.dart';

// Re-export supabase types commonly needed by the apps (AuthException, etc).
// NOTE: gotrue's `Session` is intentionally NOT re-exported — it would clash with
// our domain `Session` model. Import it directly from supabase_flutter if needed.
export 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthState, User, SupabaseClient;
