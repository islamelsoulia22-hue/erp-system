import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_spacing.dart';

/// نتيجة صفحة واحدة من السيرفر: عناصر الصفحة + إجمالي العدد الكلي.
///
/// تُستخدم مع [AppPagination] لعرض ترقيم الصفحات (10 عناصر/صفحة).
class PagedData<T> {
  final List<T> items;
  final int total;

  const PagedData(this.items, this.total);

  const PagedData.empty()
      : items = const [],
        total = 0;

  /// عدد الصفحات الكلي (صفحة واحدة على الأقل عند وجود عناصر).
  int totalPages([int pageSize = AppConstants.listPageSize]) {
    if (total <= 0) return 0;
    return (total + pageSize - 1) ~/ pageSize;
  }
}

/// شريط ترقيم صفحات موحد لكل الأقسام:
/// زر السابق ‹ [ 1 ... 4 5 6 ... 20 ] التالي › + "صفحة X من Y".
///
/// [page] صفرية (0 = الصفحة الأولى).
class AppPagination extends StatelessWidget {
  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onGo;

  const AppPagination({
    super.key,
    required this.page,
    required this.total,
    this.pageSize = AppConstants.listPageSize,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = total <= 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    // صفحة واحدة أو بدون عناصر: نعرض الإجمالي فقط بدون أزرار.
    if (pages <= 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm),
        child: Center(
          child: Text(
            total <= 0
                ? 'لا توجد عناصر'
                : 'إجمالي العناصر: $total',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    final cur = page.clamp(0, pages - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment:
                WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              _ArrowButton(
                icon: Icons.chevron_right_outlined,
                tooltip: 'السابق',
                enabled: cur > 0,
                onTap: () => onGo(cur - 1),
              ),
              for (final n in _numbers(cur, pages))
                if (n == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 2),
                    child: Text('…',
                        style: TextStyle(
                            color: Colors.grey)),
                  )
                else
                  _PageButton(
                    number: n + 1,
                    selected: n == cur,
                    onTap: () => onGo(n),
                  ),
              _ArrowButton(
                icon: Icons.chevron_left_outlined,
                tooltip: 'التالي',
                enabled: cur < pages - 1,
                onTap: () => onGo(cur + 1),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'صفحة ${cur + 1} من $pages • إجمالي $total',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// أرقام الصفحات (صفرية) مع … للفجوات: الأولى + نافذة حول
  /// الحالية + الأخيرة. null = علامة الحذف.
  static List<int?> _numbers(int cur, int pages) {
    if (pages <= 7) {
      return [for (var i = 0; i < pages; i++) i];
    }
    final out = <int>{0};
    for (var i = cur - 1; i <= cur + 1; i++) {
      if (i > 0 && i < pages - 1) out.add(i);
    }
    out.add(pages - 1);
    final sorted = out.toList()..sort();
    final res = <int?>[];
    for (var k = 0; k < sorted.length; k++) {
      if (k > 0 && sorted[k] - sorted[k - 1] > 1) {
        res.add(null);
      }
      res.add(sorted[k]);
    }
    return res;
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        tapTargetSize:
            MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final int number;
  final bool selected;
  final VoidCallback onTap;
  const _PageButton({
    required this.number,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (selected) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize:
              MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text('$number'),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        tapTargetSize:
            MaterialTapTargetSize.shrinkWrap,
        foregroundColor:
            theme.colorScheme.onSurface,
      ),
      child: Text('$number'),
    );
  }
}

/// تقطيع قائمة محلية (client-side) لصفحة واحدة من 10 عناصر.
///
/// للقوائم الصغيرة المحملة بالكامل (مخازن/تصنيفات/إشعارات...).
List<T> paginateLocal<T>(List<T> all, int page,
    [int pageSize = AppConstants.listPageSize]) {
  if (all.isEmpty || page < 0) return const [];
  final start = page * pageSize;
  if (start >= all.length) return const [];
  final end = (start + pageSize).clamp(0, all.length);
  return all.sublist(start, end);
}
