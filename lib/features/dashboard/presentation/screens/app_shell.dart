import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_nav.dart';
import '../../../../core/widgets/app_sidebar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../users/data/users_repository.dart';

/// Responsive ERP shell:
/// mobile → AppBar + bottom bar (5) + drawer,
/// tablet → NavigationRail + drawer,
/// desktop → permanent sidebar.
///
/// زرار الرجوع موحد في الشيل (مش في كل شاشة): pop لو فيه
/// حاجة تتشال، وإلا الذهاب لصفحة القسم — عشان الدخول
/// المباشر بالرابط (مفيش وراه حاجة) ميطلعش
/// "There is nothing to pop".
void safeBack(BuildContext context) {
  try {
    if (context.canPop()) {
      context.pop();
      return;
    }
  } catch (_) {
    // اختلاف نادر بين canPop وpop — نكمل للبديل.
  }
  context.go(sectionHomeOf(
      GoRouterState.of(context).uri.path));
}

/// صفحة القسم لأي مسار: الأقسام اللي ملهاش قايمة مستقلة
/// (فواتير/طلبات المشتريات، المرتجعات) ترجع للهب بتاعها،
/// والباقي يشيل آخر جزء من المسار.
String sectionHomeOf(String path) {
  const homes = {
    '/purchase-invoices': '/purchases',
    '/purchase-orders': '/purchases',
    '/purchase-returns': '/returns',
    '/sales-returns': '/returns',
  };
  for (final e in homes.entries) {
    if (path == e.key ||
        path.startsWith('${e.key}/')) {
      return e.value;
    }
  }
  final i = path.lastIndexOf('/');
  if (i > 0) return path.substring(0, i);
  return '/';
}

/// زرار الرجوع (سهم يمين = اتجاه الرجوع في العربي).
Widget backButton(BuildContext context) {
  return IconButton(
    tooltip: 'رجوع',
    icon: const Icon(Icons.arrow_forward),
    onPressed: () => safeBack(context),
  );
}
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Object? _realtimeChannel;
  String? _subscribedUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // المستخدم راجع من الخلفية — حدّث صلاحياته فورا بدون logout.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(myPermissionsProvider);
      ref.invalidate(myHiddenPagesProvider);
    }
  }

  void _unsubscribe() {
    try {
      final ch = _realtimeChannel;
      if (ch != null) {
        (ch as dynamic).unsubscribe();
      }
    } catch (_) {}
    _realtimeChannel = null;
    _subscribedUid = null;
  }

  /// اشتراك realtime على منح/أدوار/صفحات المستخدم الحالي.
  /// أي تغيير من المدير يسمع خلال ثواني بدون logout.
  /// نسخة الجهاز: لا realtime — تُحدَّث الصلاحيات يدويا/بالدخول.
  void _ensureSubscribed(String? uid) {
    if (resolveBackendMode() == BackendMode.local) return;
    if (uid == null || uid == _subscribedUid) return;
    _unsubscribe();
    try {
      final client = ref.read(supabaseClientProvider);
      final channel = (client as dynamic).channel('my-perms-$uid');
      (channel as dynamic)
          .onPostgresChanges(
            event: '*',
            schema: 'public',
            table: 'user_permission_grants',
            filter: 'user_id=eq.$uid',
            callback: (_) {
              ref.invalidate(myPermissionsProvider);
            },
          )
          .onPostgresChanges(
            event: '*',
            schema: 'public',
            table: 'user_roles',
            filter: 'user_id=eq.$uid',
            callback: (_) {
              ref.invalidate(myPermissionsProvider);
            },
          )
          .onPostgresChanges(
            event: '*',
            schema: 'public',
            table: 'user_page_overrides',
            filter: 'user_id=eq.$uid',
            callback: (_) {
              ref.invalidate(myHiddenPagesProvider);
            },
          )
          .subscribe();
      _realtimeChannel = channel;
      _subscribedUid = uid;
    } catch (_) {
      // realtime غير متاح — التحديث اليدوي و lifecycle يكفيان.
    }
  }

  void _refreshPerms() {
    ref.invalidate(myPermissionsProvider);
    ref.invalidate(myHiddenPagesProvider);
    ref.invalidate(myProfileProvider);
  }

  /// عناصر الشريط السفلي بعد إخفاء ما حدده المدير.
  List<ErpNavItem> _visibleBottom(Set<String> hidden) =>
      BottomNav.items.where((i) => !hidden.contains(i.route)).toList();

  int _bottomIndex(String path, List<ErpNavItem> items) {
    for (var i = 0; i < items.length; i++) {
      final r = items[i].route;
      if (r == '/') {
        if (path == '/') return i;
      } else if (path == r || path.startsWith('$r/')) {
        return i;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final permsAsync = ref.watch(myPermissionsProvider);
    final profileAsync = ref.watch(myProfileProvider);
    // فعّل التحديث الفوري لصلاحيات المستخدم الحالي.
    final uid = ref.watch(authRepositoryProvider).currentUser?.id;
    if (uid != null) _ensureSubscribed(uid);
    final path = GoRouterState.of(context).uri.path;
    final title = pageTitleFor(path);

    return permsAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(
          body: Center(
              child: Text('تعذر تحميل الصلاحيات'))),
      data: (perms) {
        final name = profileAsync.maybeWhen(
          data: (p) =>
              (p?['full_name'] as String?)?.isNotEmpty == true
                  ? p!['full_name'] as String
                  : 'مستخدم',
          orElse: () => 'مستخدم',
        );
        final email = profileAsync.maybeWhen(
          data: (p) => (p?['email'] as String?) ?? '',
          orElse: () => '',
        );
        Future<void> logout() => ref
            .read(logoutControllerProvider.notifier)
            .logout();
        // الصفحات المخفية عن المستخدم الحالي (حددها المدير).
        final hidden =
            ref.watch(myHiddenPagesProvider).maybeWhen(
                  data: (h) => h,
                  orElse: () => const <String>{},
                );
        final bottomItems = _visibleBottom(hidden);

        final drawer = ErpDrawer(
          perms: perms,
          currentPath: path,
          userName: name,
          userEmail: email,
          onLogout: logout,
          hidden: hidden,
        );

        if (context.isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                ErpSidebar(
                  perms: perms,
                  currentPath: path,
                  userName: name,
                  userEmail: email,
                  onLogout: logout,
                  hidden: hidden,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _DesktopHeader(
                        title: title,
                        userName: name,
                        onRefresh: _refreshPerms,
                      ),
                      Expanded(child: widget.child),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        if (context.isTablet) {
          final railIndex = bottomItems.isEmpty
              ? 0
              : _bottomIndex(path, bottomItems)
                  .clamp(0, bottomItems.length - 1);
          return Scaffold(
            key: _scaffoldKey,
            appBar: AppBar(
              title: Text(title),
              // كل الصفح فيها رجوع ما عدا الرئيسية
              // (الزرار الثابت للقائمة كان بيخفي الرجوع).
              leading: GoRouterState.of(context)
                          .uri
                          .path ==
                      '/'
                  ? IconButton(
                      tooltip: 'القائمة',
                      icon: const Icon(
                          Icons.menu_outlined),
                      onPressed: () => _scaffoldKey
                          .currentState
                          ?.openDrawer(),
                    )
                  : backButton(context),
              actions: [
                IconButton(
                  tooltip: 'تحديث الصلاحيات',
                  icon: const Icon(Icons.refresh_outlined),
                  onPressed: _refreshPerms,
                ),
                const _BellButton(),
              ],
            ),
            drawer: drawer,
            body: Row(
              children: [
                if (bottomItems.isNotEmpty)
                  NavigationRail(
                    selectedIndex: railIndex,
                    onDestinationSelected: (i) =>
                        context.go(bottomItems[i].route),
                    labelType:
                        NavigationRailLabelType.all,
                    destinations: [
                      for (final item in bottomItems)
                        NavigationRailDestination(
                            icon: Icon(item.icon),
                            label:
                                Text(item.title)),
                    ],
                  ),
                if (bottomItems.isNotEmpty)
                  const VerticalDivider(width: 1),
                Expanded(child: widget.child),
              ],
            ),
          );
        }

        // Mobile.
        final selected = _bottomIndex(path, bottomItems);
        return Scaffold(
          key: _scaffoldKey,
          appBar: path == '/'
              ? null
              : AppBar(
                  title: Text(title),
                  leading: backButton(context),
                  actions: [
                    IconButton(
                      tooltip: 'تحديث الصلاحيات',
                      icon: const Icon(Icons.refresh_outlined),
                      onPressed: _refreshPerms,
                    ),
                    const _BellButton(),
                  ],
                ),
          drawer: drawer,
          body: widget.child,
          bottomNavigationBar: _YadBottomBar(
            items: bottomItems,
            selectedIndex: selected,
            onSelect: (i) => context.go(bottomItems[i].route),
            onMore: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        );
      },
    );
  }
}

class _BellButton extends ConsumerWidget {
  const _BellButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread =
        ref.watch(unreadCountProvider).maybeWhen(
              data: (n) => n,
              orElse: () => 0,
            );
    return Stack(
      children: [
        IconButton(
          tooltip: 'الإشعارات',
          onPressed: () => context.push('/notifications'),
          icon:
              const Icon(Icons.notifications_outlined),
        ),
        if (unread > 0)
          PositionedDirectional(
            end: 6,
            top: 6,
            child: CircleAvatar(
              radius: 9,
              backgroundColor: AppColors.danger,
              child: Text('$unread',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

/// Slim desktop header: page title + user chip.
class _DesktopHeader extends ConsumerWidget {
  final String title;
  final String userName;
  final VoidCallback? onRefresh;
  const _DesktopHeader(
      {required this.title, required this.userName, this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            bottom: BorderSide(
                color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // زرار رجوع في كل الصفح ما عدا الرئيسية.
          if (GoRouterState.of(context)
                  .uri
                  .path !=
              '/')
            backButton(context),
          Expanded(
              child: Text(title,
                  style:
                      theme.textTheme.headlineSmall)),
          if (onRefresh != null)
            IconButton(
              tooltip: 'تحديث الصلاحيات',
              icon: const Icon(Icons.refresh_outlined),
              onPressed: onRefresh,
            ),
          const _BellButton(),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor:
                AppColors.primaryContainer,
            child: Text(
              userName.isNotEmpty ? userName[0] : 'م',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(userName,
              style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}


/// YAD floating navigation: midnight surface and a springy active bubble.
class _YadBottomBar extends StatelessWidget {
  final List<ErpNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onMore;

  const _YadBottomBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final visible = items.take(4).toList();
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF12163A),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF2A2F8A)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF12163A).withValues(alpha: .20),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < visible.length; i++)
              Expanded(
                child: _YadNavItem(
                  item: visible[i],
                  selected: selectedIndex == i,
                  onTap: () => onSelect(i),
                ),
              ),
            Expanded(
              child: _YadNavItem(
                item: const ErpNavItem(
                    'المزيد', Icons.grid_view_rounded, ''),
                selected: false,
                onTap: onMore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YadNavItem extends StatelessWidget {
  final ErpNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _YadNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF8E93C8);
    return Semantics(
      button: true,
      selected: selected,
      label: item.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AnimatedSlide(
                duration: const Duration(milliseconds: 450),
                curve: const Cubic(.34, 1.56, .64, 1),
                offset: selected ? const Offset(0, -.16) : Offset.zero,
                child: AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                curve: const Cubic(.34, 1.56, .64, 1),
                width: selected ? 52 : 42,
                height: selected ? 52 : 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4F46FF), Color(0xFF8B5CF6)],
                        )
                      : null,
                  border: selected
                      ? Border.all(
                          color: const Color(0xFF0E1330), width: 5)
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4F46FF)
                                .withValues(alpha: .32),
                            blurRadius: 16,
                            offset: const Offset(0, 7),
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  item.icon,
                  size: 23,
                  color: selected ? Colors.white : muted,
                ),
              ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? Colors.white : muted,
                ),
                child: Text(item.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 7),
            ],
          ),
        ),
      ),
    );
  }
}
