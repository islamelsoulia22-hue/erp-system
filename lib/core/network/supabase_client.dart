import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_mode.dart';
import '../local/local_database.dart';
import '../local/local_query.dart';

/// Centralized Supabase access. Repositories must use this, never create
/// their own client. Service role key must NEVER be used in the app.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Current authenticated user id, null when signed out.
/// نسخة الجهاز: نفس البث من المحول المحلي (بدون سوبابيز).
final currentUserIdProvider = StreamProvider<String?>((ref) {
  if (resolveBackendMode() == BackendMode.local) {
    return LocalDbClient(() => LocalDatabase.instance.db)
        .auth
        .onAuthStateChange
        .map((e) => e.session?.user.id);
  }
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange.map((event) => event.session?.user.id);
});
