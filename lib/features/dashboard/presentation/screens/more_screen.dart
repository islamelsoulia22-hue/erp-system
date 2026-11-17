import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_nav.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/yad_widgets.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../users/data/users_repository.dart';

/// شاشة "المزيد": بطاقة المستخدم + كل الأقسام المسموحة كشبكة
/// أيقونات ملونة (3 أعمدة). تحترم الصلاحيات والصفحات المخفية.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const _tints = <(Color, Color)>[
    (AppColors.primaryContainer, AppColors.indigoDeep),
    (AppColors.successContainer, AppColors.success),
    (AppColors.warningContainer, AppColors.warning),
    (AppColors.infoContainer, AppColors.info),
    (AppColors.dangerContainer, AppColors.danger),
    (AppColors.purpleContainer, AppColors.purple),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permsAsync = ref.watch(myPermissionsProvider);
    final profile = ref.watch(myProfileProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );
    final hidden = ref.watch(myHiddenPagesProvider).maybeWhen(
          data: (h) => h,
          orElse: () => const <String>{},
        );
    final name = (profile?['full_name'] as String?)?.isNotEmpty == true
        ? profile!['full_name'] as String
        : 'مستخدم';
    final email = (profile?['email'] as String?) ?? '';

    return permsAsync.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(16), child: LoadingSkeleton(rows: 6)),
      error: (_, _) => const ErrorState(),
      data: (perms) {
        final local = resolveBackendMode() == BackendMode.local;
        final seen = <String>{'/', '/notifications'};
        final groups = <(String, List<ErpNavItem>)>[];
        for (final s in ErpNav.visible(perms)) {
          final items = <ErpNavItem>[];
          for (final i in s.items) {
            if (seen.contains(i.route)) continue;
            if (hidden.contains(i.route)) continue;
            if (local && isLocalExcludedRoute(i.route)) continue;
            if (i.route == '/approvals' &&
                (local || !ErpNav.approvalsVisible(perms))) {
              continue;
            }
            seen.add(i.route);
            items.add(i);
          }
          if (items.isNotEmpty) groups.add((s.title, items));
        }

        var tint = 0;
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              RiseIn(
                child: YadHeroCard(
                  gradient: AppColors.heroGradient,
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Text(
                          'YAD',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  color: AppColors.indigo, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            if (email.isNotEmpty)
                              Text(email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: TextDirection.ltr,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppColors.heroSoft,
                                      fontSize: 12)),
                          ],
                        ),
                      ),
                      TapScale(
                        semanticLabel: 'تسجيل الخروج',
                        onTap: () => ref
                            .read(logoutControllerProvider.notifier)
                            .logout(),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.logout_outlined,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                      child: Text('لا توجد صفحات مفعلة لحسابك بعد.')),
                ),
              for (var g = 0; g < groups.length; g++) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 22, bottom: 10),
                  child: Text(groups[g].$1,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                              color: AppColors.secondaryText,
                              fontWeight: FontWeight.w800)),
                ),
                RiseIn(
                  index: g + 1,
                  child: GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 132,
                    ),
                    children: [
                      for (final item in groups[g].$2)
                        _MoreTile(
                          item: item,
                          tint: _tints[tint++ % _tints.length],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MoreTile extends StatelessWidget {
  final ErpNavItem item;
  final (Color, Color) tint;
  const _MoreTile({required this.item, required this.tint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return TapScale(
      semanticLabel: item.title,
      onTap: () => context.go(item.route),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: dark ? AppColors.darkDivider : AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            YadIconTile(
                icon: item.icon, color: tint.$2, background: tint.$1),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}