import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/providers/auth_providers.dart';

class UsersRepository {
  final dynamic _client;
  UsersRepository(this._client);

  Future<List<Profile>> listProfiles({
    String search = '',
    int page = 0,
    int pageSize = AppConstants.pageSize,
  }) async {
    try {
      var q = _client.from(SupabaseTables.profiles).select();
      if (search.trim().isNotEmpty) {
        q = q.or(
          'full_name.ilike.%${search.trim()}%,email.ilike.%${search.trim()}%',
        );
      }
      q = q
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await q) as List;
      return rows
          .map((e) => Profile.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد المستخدمين المطابقين (لترقيم الصفحات).
  Future<int> countProfiles({String search = ''}) async {
    try {
      var req = _client.from(SupabaseTables.profiles).select('id');
      if (search.trim().isNotEmpty) {
        req = req.or(
          'full_name.ilike.%${search.trim()}%,email.ilike.%${search.trim()}%',
        );
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Role>> listRoles() async {
    try {
      final rows =
          (await _client.from(SupabaseTables.roles).select().order('key'))
              as List;
      return rows
          .map((e) => Role.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
  Future<List<String>> roleKeysOf(String userId) async {
    try {
      final rows = (await _client
          .from('user_roles')
          .select('roles!inner(key)')
          .eq('user_id', userId)) as List;
      return [
        for (final r in rows)
          ((r as Map)['roles'] as Map)['key'] as String,
      ];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// مفاتيح صلاحيات دور معين (لضبط صفحات الدور تلقائيا).
  Future<List<String>> permissionKeysOfRole(String roleKey) async {
    try {
      final rows = (await _client
          .from('role_permissions')
          .select('permissions!inner(key), roles!inner(key)')
          .eq('roles.key', roleKey)) as List;
      return [
        for (final r in rows)
          (((r as Map)['permissions'] as Map)['key'] as String),
      ];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> assignRole({
    required String userId,
    required String roleId,
  }) async {
    try {
      await _client.from('user_roles').upsert({
        'user_id': userId,
        'role_id': roleId,
      });
      await _client.from('audit_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'action': 'UPDATE',
        'entity_type': 'USER_ROLE',
        'entity_id': userId,
        'new_data': {'role_id': roleId},
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> removeRole({
    required String userId,
    required String roleId,
  }) async {
    try {
      await _client
          .from('user_roles')
          .delete()
          .eq('user_id', userId)
          .eq('role_id', roleId);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
  Future<void> setActive(
      {required String userId, required bool active}) async {
    try {
      await _client
          .from(SupabaseTables.profiles)
          .update({'is_active': active})
          .eq('id', userId);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// الصلاحيات الفعالة لمستخدم معين: أدوار + منح فردي.
  Future<Set<String>> userEffectivePermissions(String userId) async {
    try {
      final out = <String>{};
      try {
        final rows = (await _client
            .from('user_permissions')
            .select('permission_key')
            .eq('user_id', userId)) as List;
        for (final r in rows) {
          final k = (r as Map)['permission_key'];
          if (k != null) out.add(k.toString());
        }
      } catch (_) {}
      try {
        final grows = (await _client
            .from('user_permission_grants')
            .select('permissions!inner(key)')
            .eq('user_id', userId)) as List;
        for (final r in grows) {
          final perm = ((r as Map)['permissions'] as Map)['key'];
          if (perm != null) out.add(perm.toString());
        }
      } catch (_) {}
      // fallback: صلاحيات الأدوار مباشرة لو الـ view محجوب بـ RLS.
      if (out.isEmpty) {
        try {
          final roleKeys = await roleKeysOf(userId);
          for (final rk in roleKeys) {
            out.addAll(await permissionKeysOfRole(rk));
          }
        } catch (_) {}
      }
      return out;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// المنح الفردي فقط (permission keys) — لعرض شارة "ممنوحة فرديا".
  Future<Set<String>> userDirectGrants(String userId) async {
    try {
      final rows = (await _client
          .from('user_permission_grants')
          .select('permissions!inner(key)')
          .eq('user_id', userId)) as List;
      return {
        for (final r in rows)
          (((r as Map)['permissions'] as Map)['key'].toString()),
      };
    } catch (_) {
      return {};
    }
  }

  /// منح صلاحية فردية لمستخدم (المدير فقط).
  /// تسمع عند المستخدم بعد تحديث صلاحياته (تلقائي خلال ثواني أو دخول جديد).
  Future<void> grantPermission({
    required String userId,
    required String permissionKey,
  }) async {
    try {
      final permRow = await _client
          .from('permissions')
          .select('id')
          .eq('key', permissionKey)
          .maybeSingle();
      if (permRow == null) return;
      final permId = (permRow as Map)['id'];
      await _client.from('user_permission_grants').upsert(
          {'user_id': userId, 'permission_id': permId},
          onConflict: 'user_id,permission_id');
      await _client.from('audit_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'action': 'UPDATE',
        'entity_type': 'USER_PERMISSION_GRANT',
        'entity_id': userId,
        'new_data': {'permission': permissionKey},
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// سحب منح فردي (الإخفاء يفضل عبر user_page_overrides).
  Future<void> revokePermission({
    required String userId,
    required String permissionKey,
  }) async {
    try {
      final permRow = await _client
          .from('permissions')
          .select('id')
          .eq('key', permissionKey)
          .maybeSingle();
      if (permRow == null) return;
      final permId = (permRow as Map)['id'];
      await _client
          .from('user_permission_grants')
          .delete()
          .eq('user_id', userId)
          .eq('permission_id', permId);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
  /// خريطة إظهار الصفحات لمستخدم (route -> visible).
  /// الفعال = (صلاحية الدور OR منح فردي) AND NOT مخفي.
  Future<Map<String, bool>> pageOverrides(String userId) async {
    try {
      final rows = (await _client
          .from('user_page_overrides')
          .select('route, visible')
          .eq('user_id', userId)) as List;
      final out = <String, bool>{};
      for (final r in rows) {
        final m = Map<String, dynamic>.from(r as Map);
        out[m['route'] as String] = m['visible'] != false;
      }
      return out;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// تعيين إظهار صفحة: visible=true يمسح التجاوز (الوضع الافتراضي).
  Future<void> setPageOverride({
    required String userId,
    required String route,
    required bool visible,
  }) async {
    try {
      if (visible) {
        await _client
            .from('user_page_overrides')
            .delete()
            .eq('user_id', userId)
            .eq('route', route);
      } else {
        await _client.from('user_page_overrides').upsert(
            {'user_id': userId, 'route': route, 'visible': false},
            onConflict: 'user_id,route');
      }
      await _client.from('audit_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'action': 'UPDATE',
        'entity_type': 'USER_PAGE',
        'entity_id': userId,
        'new_data': {'route': route, 'visible': visible},
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إنشاء حساب عبر Edge Function (المدير فقط).
  /// ترجع id + email للحساب الجديد.
  Future<Map<String, String>> createUser({
    required String email,
    required String password,
    String? fullName,
    String? roleId,
  }) async {
    try {
      final res = await _client.functions.invoke('create-user', body: {
        'email': email.trim(),
        'password': password,
        'full_name': (fullName ?? '').trim(),
        if (roleId case final id) 'role_id': id,
      });
      final status = res.status as int? ?? 500;
      final data = res.data;
      if (status != 200) {
        final code =
            data is Map ? data['error']?.toString() : null;
        throw _functionError(code);
      }
      final map = Map<String, dynamic>.from(data as Map);
      return {
        'id': (map['id'] ?? '').toString(),
        'email': (map['email'] ?? '').toString(),
      };
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// حذف حساب نهائيا عبر Edge Function (المدير فقط، وممنوع حذف النفس).
  Future<void> deleteUser({required String userId}) async {
    try {
      final res = await _client.functions
          .invoke('delete-user', body: {'user_id': userId});
      final status = res.status as int? ?? 500;
      if (status != 200) {
        final data = res.data;
        final code =
            data is Map ? data['error']?.toString() : null;
        throw _functionError(code);
      }
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  AppFailure _functionError(String? code) {
    switch (code) {
      case 'NO_PERMISSION':
      case 'NOT_AUTHENTICATED':
        return const UnauthorizedFailure();
      case 'EMAIL_EXISTS':
        return const EmailExistsFailure();
      case 'INVALID_INPUT':
        return const InvalidUserInputFailure();
      case 'CANNOT_DELETE_SELF':
        return const CannotDeleteSelfFailure();
      default:
        return const UnknownFailure();
    }
  }
}

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  // (إنشاء/حذف المستخدمين يعمل عبر functions المحلية.)
  if (resolveBackendMode() == BackendMode.local) {
    return UsersRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return UsersRepository(ref.watch(supabaseClientProvider));
});

final rolesListProvider = FutureProvider<List<Role>>((ref) {
  return ref.watch(usersRepositoryProvider).listRoles();
});

/// تجاوزات صفحات مستخدم معين (لشيت المدير).
final userPagesProvider = FutureProvider.autoDispose
    .family<Map<String, bool>, String>((ref, userId) {
  return ref.watch(usersRepositoryProvider).pageOverrides(userId);
});

/// المسارات المخفية عن المستخدم الحالي (تتحدث مع تسجيل الدخول).
final myHiddenPagesProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  ref.watch(authStateProvider);
  final uid = ref.watch(authRepositoryProvider).currentUser?.id;
  if (uid == null) return const {};
  try {
    final m =
        await ref.watch(usersRepositoryProvider).pageOverrides(uid);
    return {for (final e in m.entries) if (!e.value) e.key};
  } catch (_) {
    return const {};
  }
});
