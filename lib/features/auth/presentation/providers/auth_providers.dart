import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/permissions/permissions.dart';
import '../../data/auth_repository.dart';

/// Raw auth state; rebuilds router + permission providers on change.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authState();
});

/// Synchronous snapshot for router redirect.
final isLoggedInProvider = Provider<bool>((ref) {
  final asyncUser = ref.watch(authStateProvider);
  final direct = ref.watch(authRepositoryProvider).currentUser;
  return asyncUser.maybeWhen(data: (u) => u != null, orElse: () => direct != null);
});

final myPermissionsProvider = FutureProvider<PermissionSet>((ref) async {
  final loggedIn = ref.watch(isLoggedInProvider);
  // Re-fetch when auth stream emits.
  ref.watch(authStateProvider);
  if (!loggedIn) return const PermissionSet({});
  final repo = ref.watch(authRepositoryProvider);
  final keys = await repo.loadMyPermissions();
  final roles = await repo.loadMyRoles();
  return PermissionSet(keys, roles);
});

final myProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final loggedIn = ref.watch(isLoggedInProvider);
  ref.watch(authStateProvider);
  if (!loggedIn) return null;
  return ref.watch(authRepositoryProvider).loadMyProfile();
});

/// Login controller with Arabic error surfaced via AppFailure.messageAr.
class LoginController extends AutoDisposeAsyncNotifier<void> {
  KeepAliveLink? _alive;

  @override
  Future<void> build() async {}

  Future<bool> login({required String email, required String password}) async {
    // امنع الـ auto-dispose أثناء العملية: الـ router بينقل لشاشة
    // تانية بعد نجاح الدخول، وتعيين state بعد التدمير بيرمي اكسبشن.
    _alive ??= ref.keepAlive();
    state = const AsyncLoading();
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password);
      // Invalidate dependents so router + permissions refresh.
      ref
        ..invalidate(authStateProvider)
        ..invalidate(myPermissionsProvider)
        ..invalidate(myProfileProvider);
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      debugPrint('login controller error: $e (${e.runtimeType})');
      state = AsyncError(e, st);
      return false;
    } finally {
      _alive?.close();
      _alive = null;
    }
  }
}

final loginControllerProvider =
    AutoDisposeAsyncNotifierProvider<LoginController, void>(
  LoginController.new,
);

final logoutControllerProvider =
    AutoDisposeAsyncNotifierProvider<LogoutController, void>(
  LogoutController.new,
);

class LogoutController extends AutoDisposeAsyncNotifier<void> {
  KeepAliveLink? _alive;

  @override
  Future<void> build() async {}

  Future<void> logout() async {
    _alive ??= ref.keepAlive();
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signOut();
      ref
        ..invalidate(authStateProvider)
        ..invalidate(myPermissionsProvider)
        ..invalidate(myProfileProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('logout controller error: $e (${e.runtimeType})');
      state = AsyncError(e, st);
    } finally {
      _alive?.close();
      _alive = null;
    }
  }
}
