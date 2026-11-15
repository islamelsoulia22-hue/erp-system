import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/widgets/app_nav.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../auth/domain/profile.dart';
import '../../data/users_repository.dart';

final usersSearchProvider = StateProvider<String>((ref) => '');

final usersListProvider = FutureProvider.autoDispose
    .family<PagedData<Profile>, int>((ref, page) async {
  final repo = ref.watch(usersRepositoryProvider);
  final search = ref.watch(usersSearchProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.listProfiles(search: search, page: page, pageSize: ps),
    repo.countProfiles(search: search),
  ]);
  return PagedData(res[0] as List<Profile>, res[1] as int);
});

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _scroll = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int p) {
    setState(() => _page = p);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    }
  }

  void _resetPage() {
    if (_page != 0) setState(() => _page = 0);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final usersAsync = ref.watch(usersListProvider(_page));
    final rolesAsync = ref.watch(rolesListProvider);

    return Scaffold(
            body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'بحث بالاسم أو البريد',
                      prefixIcon:
                          Icon(Icons.search_outlined),
                    ),
                    onChanged: (v) {
                      ref
                          .read(usersSearchProvider.notifier)
                          .state = v;
                      _resetPage();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _showCreateSheet(
                      context, ref, rolesAsync),
                  icon: const Icon(Icons.person_add_outlined,
                      size: 18),
                  label: const Text('حساب جديد'),
                ),
              ],
            ),
          ),
          Expanded(
            child: usersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('حدث خطأ أثناء تنفيذ العملية: $e')),
              data: (paged) {
                final users = paged.items;
                if (users.isEmpty) {
                  return const Center(
                      child: Text('لا يوجد مستخدمون مطابقون'));
                }
                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        controller: _scroll,
                        itemCount: users.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final u = users[i];
                    return ListTile(
                      leading: CircleAvatar(
                          child: Text(u.fullName.isNotEmpty
                              ? u.fullName[0]
                              : '?')),
                      title: Text(u.fullName.isEmpty
                          ? (u.email ?? 'بدون اسم')
                          : u.fullName),
                      subtitle: Text(u.email ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!u.isActive)
                            const Chip(label: Text('موقوف')),
                          IconButton(
                            tooltip: 'الأدوار',
                            icon: const Icon(
                                Icons.manage_accounts_outlined),
                            onPressed: () =>
                                _showRolesSheet(context, ref, u, rolesAsync),
                          ),
                          PopupMenuButton<String>(
                            iconSize: 20,
                            tooltip: 'المزيد',
                            onSelected: (v) async {
                              if (v == 'pages') {
                                _showPagesSheet(
                                    context, ref, u);
                              } else if (v ==
                                  'toggle') {
                                try {
                                  await ref
                                      .read(
                                          usersRepositoryProvider)
                                      .setActive(
                                          userId: u.id,
                                          active:
                                              !u.isActive);
                                  ref.invalidate(
                                      usersListProvider);
                                } catch (_) {
                                  if (context
                                      .mounted) {
                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(const SnackBar(
                                            content: Text(
                                                'لا تملك صلاحية تنفيذ هذه العملية.')));
                                  }
                                }
                              } else if (v ==
                                  'delete') {
                                if (!await confirmDelete(
                                    context,
                                    'حساب "${u.email ?? u.fullName}"')) {
                                  return;
                                }
                                try {
                                  await ref
                                      .read(
                                          usersRepositoryProvider)
                                      .deleteUser(
                                          userId: u.id);
                                  ref.invalidate(
                                      usersListProvider);
                                  if (context
                                      .mounted) {
                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    'تم حذف الحساب.')));
                                  }
                                } catch (e) {
                                  if (context
                                      .mounted) {
                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(SnackBar(
                                            content: Text(e
                                                    is AppFailure
                                                ? e.messageAr
                                                : 'حدث خطأ أثناء الحذف.')));
                                  }
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'pages',
                                  child: Text(
                                      'الصفحات الظاهرة')),
                              PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(u.isActive
                                      ? 'إيقاف'
                                      : 'تفعيل')),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                      'حذف الحساب نهائيا')),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              AppPagination(
                page: _page,
                total: paged.total,
                onGo: _go,
              ),
            ],
          );
        },
            ),
          ),
        ],
      ),
    );
  }

  /// كتالوج الصفحات من أقسام القائمة (بدون تكرار).
  List<({String title, List<ErpNavItem> items})>
      _pageCatalog() {
    final seen = <String>{};
    final sections = <({String title, List<ErpNavItem> items})>[];
    for (final s in ErpNav.sections) {
      final items = [
        for (final i in s.items)
          if (seen.add(i.route)) i,
      ];
      if (items.isNotEmpty) {
        sections.add((title: s.title, items: items));
      }
    }
    return sections;
  }

  /// صفحات دور معين (حسب صلاحياته) — تنزل تلقائيا عند اختياره.
  Set<String> _roleRoutes(List<String> keys, String roleKey) {
    final perms = PermissionSet(Set.of(keys), {roleKey});
    final out = <String>{};
    for (final s in ErpNav.sections) {
      var items =
          s.items.where((i) => i.visible(perms)).toList();
      if (s.title == 'الرئيسية') {
        items = items
            .where((i) =>
                i.route != '/approvals' ||
                ErpNav.approvalsVisible(perms))
            .toList();
      }
      out.addAll(items.map((i) => i.route));
    }
    return out;
  }

  /// يظبط سويتشات الصفحات حسب الدور المختار (والمدير يعدل بعدها عادي).
  Future<void> _applyRolePages(
    WidgetRef ref,
    void Function(void Function()) setS,
    Set<String> hiddenPages,
    List<({String title, List<ErpNavItem> items})> catalog,
    String? roleId,
    List<Role> roles,
  ) async {
    if (roleId == null) {
      setS(() => hiddenPages.clear());
      return;
    }
    final matches =
        roles.where((r) => r.id == roleId).toList();
    if (matches.isEmpty) return;
    try {
      final keys = await ref
          .read(usersRepositoryProvider)
          .permissionKeysOfRole(matches.first.key);
      final allowed = _roleRoutes(keys, matches.first.key);
      final all = {
        for (final s in catalog)
          for (final i in s.items) i.route,
      };
      setS(() {
        hiddenPages
          ..clear()
          ..addAll(all.difference(allowed));
      });
    } catch (_) {}
  }

  void _showCreateSheet(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Role>> rolesAsync,
  ) {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    String? roleId;
    bool obscure = true;
    bool saving = false;
    // الصفحات المحددة للحساب الجديد (الكل ظاهر افتراضيا).
    final hiddenPages = <String>{};
    final catalog = _pageCatalog();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
              const Text('حساب جديد',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'اسم الموظف'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType:
                    TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني *',
                    prefixIcon:
                        Icon(Icons.email_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: obscure,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText:
                      'كلمة المرور * (6 أحرف على الأقل)',
                  prefixIcon:
                      const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons
                            .visibility_off_outlined),
                    onPressed: () =>
                        setS(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              rolesAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator()),
                error: (e, _) =>
                    Text('تعذر تحميل الأدوار: $e'),
                data: (roles) =>
                    DropdownButtonFormField<String>(
                  initialValue: roleId,
                  decoration: const InputDecoration(
                      labelText: 'الدور (اختياري)'),
                  items: [
                    const DropdownMenuItem(
                        value: null,
                        child: Text('بدون دور')),
                    for (final r in roles)
                      DropdownMenuItem(
                          value: r.id,
                          child: Text(
                              '${r.nameAr} (${r.key})',
                              textDirection:
                                  TextDirection.ltr)),
                  ],
                  onChanged: (v) {
                    setS(() => roleId = v);
                    // الدور ينزل بأقسامه تلقائيا — والمدير يعدل عادي.
                    _applyRolePages(ref, setS,
                        hiddenPages, catalog, v, roles);
                  },
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                    'الصفحات الظاهرة للموظف',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                subtitle: Text(
                  hiddenPages.isEmpty
                      ? 'كل الصفحات ظاهرة'
                      : 'مخفية: ${hiddenPages.length}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
                children: [
                  const Text(
                    'اختار الدور وهتنزل أقسامه تلقائياً — وعدّل براحتك. اللي مش متعلم عليه مش هيظهر خالص في تصميمه.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                  for (final s in catalog) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                          top: 8, bottom: 2),
                      child: Text(s.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              fontSize: 13)),
                    ),
                    for (final item in s.items)
                      SwitchListTile(
                        dense: true,
                        contentPadding:
                            EdgeInsets.zero,
                        title: Text(item.title,
                            style: const TextStyle(
                                fontSize: 14)),
                        value: !hiddenPages
                            .contains(item.route),
                        onChanged: (v) => setS(() {
                          if (v) {
                            hiddenPages
                                .remove(item.route);
                          } else {
                            hiddenPages
                                .add(item.route);
                          }
                        }),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (email.text.trim().isEmpty ||
                            password.text.length < 6) {
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(const SnackBar(
                                  content: Text(
                                      'اكتب بريدا صحيحا وكلمة مرور 6 أحرف على الأقل.')));
                          return;
                        }
                        setS(() => saving = true);
                        try {
                          final repo = ref.read(
                              usersRepositoryProvider);
                          final created =
                              await repo.createUser(
                            email: email.text,
                            password: password.text,
                            fullName: name.text,
                            roleId: roleId,
                          );
                          // حفظ الصفحات المحددة للحساب الجديد.
                          final newId =
                              created['id'] ?? '';
                          if (newId.isNotEmpty &&
                              hiddenPages.isNotEmpty) {
                            for (final route
                                in hiddenPages) {
                              try {
                                await repo.setPageOverride(
                                    userId: newId,
                                    route: route,
                                    visible: false);
                              } catch (_) {}
                            }
                          }
                          ref.invalidate(
                              usersListProvider);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                                    context)
                                .showSnackBar(SnackBar(
                                    content: Text(
                                        'تم إنشاء حساب ${created['email']} بنجاح.')));
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx)
                                .showSnackBar(SnackBar(
                                    content: Text(e
                                            is AppFailure
                                        ? e.messageAr
                                        : 'حدث خطأ أثناء إنشاء الحساب.')));
                          }
                        } finally {
                          if (ctx.mounted) {
                            setS(() => saving = false);
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : const Text('إنشاء الحساب'),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  void _showRolesSheet(
    BuildContext context,
    WidgetRef ref,
    Profile user,
    AsyncValue<List<Role>> rolesAsync,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: rolesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('تعذر تحميل الأدوار: $e'),
          data: (roles) => FutureBuilder<List<String>>(
            future:
                ref.read(usersRepositoryProvider).roleKeysOf(user.id),
            builder: (context, snap) {
              final assigned = Set<String>.from(snap.data ?? []);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('أدوار: ${user.email ?? ''}',
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  for (final r in roles)
                    CheckboxListTile(
                      title: Text(r.nameAr),
                      subtitle: Text(r.key, textDirection: TextDirection.ltr),
                      value: assigned.contains(r.key),
                      onChanged: (v) async {
                        try {
                          final repo =
                              ref.read(usersRepositoryProvider);
                          if (v == true) {
                            await repo.assignRole(
                                userId: user.id, roleId: r.id);
                          } else {
                            await repo.removeRole(
                                userId: user.id, roleId: r.id);
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          ref.invalidate(usersListProvider);
                        } catch (_) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'لا تملك صلاحية تنفيذ هذه العملية.')));
                          }
                        }
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// شيت تحديد الصفحات الظاهرة للمستخدم.
  /// تشغيل صفحة = إظهار + منح صلاحيتها فرديا لو ناقصة (تسمع عند المستخدم).
  /// إيقاف صفحة = إخفاء فقط (لا يسحب المنح حتى لا يكسر صفحات تشترك بنفس الصلاحية).
  /// الفعال = (صلاحية الدور OR منح فردي) AND NOT مخفي.
  void _showPagesSheet(
    BuildContext context,
    WidgetRef ref,
    Profile user,
  ) {
    final sections = _pageCatalog();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxHeight: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Text(
                      'الصفحات الظاهرة: ${user.fullName.isEmpty ? (user.email ?? '') : user.fullName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'تشغيل صفحة يظهرها ويدي صلاحيتها تلقائيا لو ناقصة. الإيقاف يخفي فقط. التغيير يسمع عند المستخدم خلال ثواني أو بعد تحديث/دخول.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<dynamic>>(
                    future: Future.wait([
                      ref
                          .read(usersRepositoryProvider)
                          .pageOverrides(user.id),
                      ref
                          .read(usersRepositoryProvider)
                          .userEffectivePermissions(user.id),
                      ref
                          .read(usersRepositoryProvider)
                          .userDirectGrants(user.id),
                    ]),
                    builder: (ctx, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child:
                                CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Text(
                            'تعذر التحميل: ${snap.error}');
                      }
                      final overrides =
                          Map<String, bool>.from(
                              (snap.data?[0] as Map?) ?? {});
                      final effective = Set<String>.from(
                          (snap.data?[1] as Set?) ?? <String>{});
                      final grants = Set<String>.from(
                          (snap.data?[2] as Set?) ?? <String>{});
                      // الصلاحية المطلوبة لمسار معين (معالجة الحالات الخاصة).
                      String? requiredFor(String route) {
                        if (route == '/approvals') return null;
                        if (route == '/returns') return null;
                        return ErpNav.permissionForRoute(route);
                      }
                      bool hasAccess(String route) {
                        if (route == '/approvals') {
                          return effective.contains(
                                  Permissions.salesApprove) ||
                              effective.contains(Permissions
                                  .purchasesApprove) ||
                              effective.contains(Permissions
                                  .expensesApprove) ||
                              effective
                                  .contains(Permissions.usersManage);
                        }
                        if (route == '/returns') {
                          return effective.contains(
                                  Permissions.salesView) ||
                              effective.contains(
                                  Permissions.purchasesView);
                        }
                        final req = requiredFor(route);
                        if (req == null) return true;
                        return effective.contains(req);
                      }
                      // نواقص الحزمة لصفحة ظاهرة (عرض موجود بس إضافة/تعديل ناقص).
                      List<String> missingBundle(String route) {
                        // لا تنبه لصفحات مطفأة.
                        if ((overrides[route] ?? true) == false) {
                          return [];
                        }
                        return ErpNav.permissionsBundleFor(route)
                            .where((k) => !effective.contains(k))
                            .toList();
                      }
                      int totalMissing() {
                        var n = 0;
                        for (final s in sections) {
                          for (final i in s.items) {
                            n += missingBundle(i.route).length;
                          }
                        }
                        return n;
                      }
                      // منح حزمة الصفحة كاملة (عرض + إضافة + تعديل).
                      Future<void> ensureGranted(
                          String route) async {
                        final bundle =
                            ErpNav.permissionsBundleFor(route);
                        if (bundle.isEmpty) return;
                        for (final key in bundle) {
                          if (!effective.contains(key)) {
                            await ref
                                .read(usersRepositoryProvider)
                                .grantPermission(
                                    userId: user.id,
                                    permissionKey: key);
                            effective.add(key);
                            grants.add(key);
                          }
                        }
                      }
                      return Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                        children: [
                          if (totalMissing() > 0)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 8),
                              child: FilledButton.icon(
                                onPressed: () async {
                                  try {
                                    for (final s
                                        in sections) {
                                      for (final i
                                          in s.items) {
                                        if ((overrides[i.route] ??
                                                true) ==
                                            false) {
                                          continue;
                                        }
                                        await ensureGranted(
                                            i.route);
                                      }
                                    }
                                    setS(() {});
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(
                                              ctx)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'تم منح صلاحيات الإضافة/التعديل للصفحات الظاهرة — ستسمع عند المستخدم خلال ثواني.')));
                                    }
                                  } catch (_) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(
                                              ctx)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'لا تملك صلاحية تنفيذ هذه العملية.')));
                                    }
                                  }
                                },
                                icon: const Icon(
                                    Icons.auto_fix_high_outlined,
                                    size: 18),
                                label: Text(
                                    'منح صلاحيات الإضافة للصفحات الظاهرة (${totalMissing()})'),
                              ),
                            ),
                          for (final s in sections) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.only(
                                      top: 8, bottom: 2),
                              child: Text(s.title,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      color: Colors.grey)),
                            ),
                            for (final item in s.items)
                              SwitchListTile(
                                dense: true,
                                contentPadding:
                                    EdgeInsets.zero,
                                title: Text(item.title,
                                    style: const TextStyle(
                                        fontSize: 14)),
                                subtitle: Builder(builder: (_) {
                                  final miss =
                                      missingBundle(item.route);
                                  if (miss.isNotEmpty) {
                                    final needAdd = miss.any((k) =>
                                        k.endsWith('.create') ||
                                        k.endsWith('.edit'));
                                    if (!(overrides[item.route] ??
                                        true)) {
                                      return const Text(
                                          'مخفية — التشغيل هيمنح صلاحياتها تلقائيا',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors
                                                  .orange));
                                    }
                                    if (needAdd) {
                                      return const Text(
                                          'ظاهرة بس ناقص صلاحية الإضافة/التعديل — دوس الزرار فوق',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors
                                                  .orange));
                                    }
                                    return Text(
                                        'محتاجة صلاحية: ${requiredFor(item.route) ?? 'اعتماد'} — التشغيل هيمنحها تلقائيا',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors
                                                .orange));
                                  }
                                  if (!hasAccess(item.route)) {
                                    return Text(
                                        'محتاجة صلاحية: ${requiredFor(item.route) ?? 'اعتماد'} — التشغيل هيمنحها تلقائيا',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors
                                                .orange));
                                  }
                                  final bundle = ErpNav
                                      .permissionsBundleFor(
                                          item.route);
                                  final hasDirect = bundle.any(
                                      (k) =>
                                          grants.contains(k));
                                  if (hasDirect) {
                                    return const Text(
                                        'ممنوحة فرديا ✓ (عرض + إضافة + تعديل)',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                Colors.green));
                                  }
                                  return const SizedBox.shrink();
                                }),
                                value: overrides[
                                        item.route] ??
                                    true,
                                onChanged: (v) async {
                                  final prev =
                                      overrides[item.route] ??
                                          true;
                                  setS(() => overrides[
                                      item.route] = v);
                                  try {
                                    if (v) {
                                      // إظهار + منح الصلاحية الناقصة.
                                      await ensureGranted(
                                          item.route);
                                    }
                                    await ref
                                        .read(
                                            usersRepositoryProvider)
                                        .setPageOverride(
                                            userId: user.id,
                                            route: item.route,
                                            visible: v);
                                    ref.invalidate(
                                        userPagesProvider(
                                            user.id));
                                    if (ctx.mounted && v) {
                                      ScaffoldMessenger.of(
                                              ctx)
                                          .showSnackBar(
                                              SnackBar(
                                                  content:
                                                      Text(hasAccess(item
                                                              .route)
                                                          ? 'تم إظهار "${item.title}" — ستظهر عند المستخدم بعد التحديث.'
                                                          : 'تمت المحاولة — راجع الصلاحيات.')));
                                    }
                                  } catch (e) {
                                    setS(() => overrides[
                                        item.route] = prev);
                                    if (ctx.mounted) {
                                      final msg = e.toString().contains(
                                              'user_permission_grants')
                                          ? 'نفّذ migration 0023 في Supabase أولا (جدول user_permission_grants ناقص).'
                                          : 'لا تملك صلاحية تنفيذ هذه العملية.';
                                      ScaffoldMessenger.of(
                                              ctx)
                                          .showSnackBar(
                                              SnackBar(
                                                  content:
                                                      Text(msg)));
                                    }
                                  }
                                },
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
