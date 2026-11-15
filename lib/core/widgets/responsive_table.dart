import 'package:flutter/material.dart';

import '../responsive/responsive.dart';
import '../theme/app_spacing.dart';

/// Table column definition for [ResponsiveTable].
class TableColumn<T> {
  final String label;
  final String Function(T item) value;
  final bool numeric;
  const TableColumn({
    required this.label,
    required this.value,
    this.numeric = false,
  });
}

/// DataTable on desktop, compact cards on mobile.
/// Same data, intelligent use of space.
class ResponsiveTable<T> extends StatelessWidget {
  final List<TableColumn<T>> columns;
  final List<T> rows;
  final Widget Function(T item) cardBuilder;
  final void Function(T item)? onTap;
  const ResponsiveTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.cardBuilder,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      return Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(
                  bottom: AppSpacing.sm),
              child: cardBuilder(r),
            ),
        ],
      );
    }
    final theme = Theme.of(context);
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.sizeOf(context).width -
                  context.contentPadding * 2 -
                  48),
          child: DataTable(
            headingTextStyle: theme.textTheme.labelMedium,
            dataTextStyle: theme.textTheme.bodyMedium,
            headingRowHeight: 40,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 56,
            showCheckboxColumn: false,
            columns: [
              for (final c in columns)
                DataColumn(
                    label: Text(c.label),
                    numeric: c.numeric),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  onSelectChanged: onTap == null
                      ? null
                      : (_) => onTap!(r),
                  cells: [
                    for (final c in columns)
                      DataCell(Text(
                        c.value(r),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
