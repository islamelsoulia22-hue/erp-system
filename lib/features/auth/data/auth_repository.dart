import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';

/// Auth repository: thin wrapper over Supabase Auth.
/// Business rules (active check, roles) enforced in DB, not here.
/// يقبل SupabaseClient أو LocalDbClient (نسخة الجهاز بنفس الكود).
class AuthRepository {
  final dynamic _client;
  AuthRepository(this._client);

  Stream<User?> authState() {
    // cast صريح: الاستدعاء عبر dynamic يفقد استدلال Stream<User?>
    // (يرجع Stream<dynamic> ويفشل فحص النوع وقت التشغيل).
    final Stream<AuthState> source =
        _client.auth.onAuthStateChange as Stream<AuthState>;
    return source.map((e) => e.session?.user);
  }

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final uid = res.user?.id;
      if (uid == null) throw const UnauthorizedFailure();
      // Block inactive profiles client-side for UX; RLS still enforces server-side.
      final profile =
          await _client.from('profiles').select('is_active').eq('id', uid).maybeSingle();
      if (profile != null && (profile as Map)['is_active'] == false) {
        await _client.auth.signOut();
        throw const UnauthorizedFailure();
      }
      await _writeAudit('LOGIN', 'SESSION', uid, null, null);
    } on AppFailure {
      rethrow;
    } catch (e) {
      debugPrint('signIn error: ${e.runtimeType}: $e');
      throw mapSupabaseError(e);
    }
  }

  Future<void> signOut() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid != null) {
        await _writeAudit('LOGOUT', 'SESSION', uid, null, null);
      }
      await _client.auth.signOut();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> _writeAudit(
    String action,
    String entityType,
    String entityId,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  ) async {
    try {
      await _client.from('audit_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'old_data': oldData,
        'new_data': newData,
      });
    } catch (_) {
      // Audit must never block login/logout UX.
    }
  }

  /// Permission keys for current user, loaded from user_permissions view.
  /// يجمع صلاحيات الدور + المنح الفردي (user_permission_grants).
  /// المنح الفردي يُقرأ مباشرة كـ fallback لو الـ view لسه قديم.
  Future<Set<String>> loadMyPermissions() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return {};
      final out = <String>{};
      try {
        final rows = await _client
            .from('user_permissions')
            .select('permission_key')
            .eq('user_id', uid);
        for (final r in (rows as List)) {
          final k = (r as Map)['permission_key'];
          if (k != null) out.add(k.toString());
        }
      } catch (_) {
        // يتجاهل — المنح الفردي تحت هيعوض لو الـ view فيه مشكلة.
      }
      // منح فردي مباشر (يشتغل حتى لو الـ view لسه ما اتحدثش).
      try {
        final grows = await _client
            .from('user_permission_grants')
            .select('permissions!inner(key)')
            .eq('user_id', uid);
        for (final r in (grows as List)) {
          final perm = ((r as Map)['permissions'] as Map)['key'];
          if (perm != null) out.add(perm.toString());
        }
      } catch (_) {
        // الجدول قد لا يكون موجودا قبل تنفيذ migration 0023 — تجاهل.
      }
      return out;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Role keys for current user (same view exposes role_key).
  Future<Set<String>> loadMyRoles() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return {};
      final rows = await _client
          .from('user_permissions')
          .select('role_key')
          .eq('user_id', uid);
      final list = rows as List;
      return {
        for (final r in list)
          if (r is Map && r['role_key'] != null)
            r['role_key'].toString(),
      };
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Map<String, dynamic>?> loadMyProfile() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final row =
          await _client.from('profiles').select().eq('id', uid).maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row as Map);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return AuthRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return AuthRepository(ref.watch(supabaseClientProvider));
});
