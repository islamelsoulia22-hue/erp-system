import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../backend/backend_mode.dart';
import '../permissions/permissions.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_nav.dart';
import 'brand_logo.dart';

/// Company brand header used in sidebar and drawer.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.mdx),
      child: Row(
        children: [
          const BrandLogo(size: 42, radius: 10),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SANAD — سند',
                  textDirection: TextDirection.rtl,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  'نظام سند',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Permission-filtered section list. Shared by drawer and sidebar.
class NavSectionList extends StatelessWidget {
  final PermissionSet perms;
  final String currentPath;
  final VoidCallback? onNavigate;
  final Set<String> hidden;
  const NavSectionList({
    super.key,
    required this.perms,
    required this.currentPath,
    this.onNavigate,
    this.hidden = const {},
  });

  bool _active(String route) =>
      route == '/'
          ? currentPath == '/'
          : currentPath == route ||
              currentPath.startsWith('$route/');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // نسخة الجهاز: إخفاء المصاريف/الموافقات/التصنيع من القوائم.
    final local = resolveBackendMode() == BackendMode.local;
    final sections = ErpNav.visible(perms).map((s) {
      if (s.title == 'الرئيسية') {
        final items = s.items
            .where((i) =>
                i.route != '/approvals' ||
                (!local && ErpNav.approvalsVisible(perms)))
            .toList();
        return ErpNavSection(s.title, items);
      }
      return s;
    }).where((s) => s.isNotEmpty);
    // إخفاء الصفحات التي حددها المدير (UX فقط — الصلاحيات للدور).
    final filtered = sections
        .map((s) => ErpNavSection(
            s.title,
            s.items
                .where((i) => !hidden.contains(i.route))
                .where((i) =>
                    !local || !isLocalExcludedRoute(i.route))
                .toList()))
        .where((s) => s.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in filtered) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.mdx,
                AppSpacing.md,
                AppSpacing.mdx,
                AppSpacing.xs),
            child: Text(s.title.toUpperCase(),
                style: theme.textTheme.labelSmall),
          ),
          for (final item in s.items)
            _NavTile(
              item: item,
              active: _active(item.route),
              onTap: () {
                onNavigate?.call();
                context.go(item.route);
              },
            ),
        ],
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final ErpNavItem item;
  final bool active;
  final VoidCallback onTap;
  const _NavTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 1),
      child: Material(
        color: active
            ? AppColors.primaryContainer
            : Colors.transparent,
        borderRadius:
            BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(item.icon,
                    size: 20,
                    color: active
                        ? AppColors.primary
                        : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(item.title,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(
                        color: active
                            ? AppColors.primary
                            : null,
                      )),
                ),
                if (active)
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Permanent desktop sidebar (280px) with footer user card.
class ErpSidebar extends StatelessWidget {
  final PermissionSet perms;
  final String currentPath;
  final String? userName;
  final String? userEmail;
  final VoidCallback onLogout;
  final Set<String> hidden;
  const ErpSidebar({
    super.key,
    required this.perms,
    required this.currentPath,
    this.userName,
    this.userEmail,
    required this.onLogout,
    this.hidden = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          const _BrandHeader(),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: NavSectionList(
                  perms: perms,
                  currentPath: currentPath,
                  hidden: hidden),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor:
                  AppColors.primaryContainer,
              child: Text(
                (userName?.isNotEmpty == true
                        ? userName![0]
                        : 'م'),
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(userName ?? 'مستخدم',
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(userEmail ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'خروج',
              iconSize: 20,
              icon:
                  const Icon(Icons.logout_outlined),
              onPressed: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawer content for mobile/tablet (same sections + user header).
class ErpDrawer extends StatelessWidget {
  final PermissionSet perms;
  final String currentPath;
  final String? userName;
  final String? userEmail;
  final VoidCallback onLogout;
  final Set<String> hidden;
  const ErpDrawer({
    super.key,
    required this.perms,
    required this.currentPath,
    this.userName,
    this.userEmail,
    required this.onLogout,
    this.hidden = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      width: 300,
      child: Column(
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.mdx,
                AppSpacing.xxl,
                AppSpacing.mdx,
                AppSpacing.mdx),
            child: Row(
              children: [
                const BrandLogo(size: 44, radius: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(userName ?? 'مستخدم',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(
                                  color: Colors.white)),
                      Text(userEmail ?? '',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                                  color: Colors.white70)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'خروج',
                  iconSize: 20,
                  color: Colors.white,
                  icon: const Icon(Icons.logout_outlined),
                  onPressed: onLogout,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: NavSectionList(
                perms: perms,
                currentPath: currentPath,
                hidden: hidden,
                onNavigate: () =>
                    Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
