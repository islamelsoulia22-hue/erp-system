import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// فلتر تاريخ (من / إلى) مشترك لقوائم الفواتير.
/// يعرض زرارين لاختيار التاريخ + مسح عند التفعيل.
class DateFilterRow extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFrom;
  final ValueChanged<DateTime?> onTo;
  final VoidCallback onClear;
  const DateFilterRow({
    super.key,
    required this.from,
    required this.to,
    required this.onFrom,
    required this.onTo,
    required this.onClear,
  });

  static final _fmt = DateFormat('yyyy/MM/dd');

  Future<void> _pick(
      BuildContext context, DateTime? initial,
      ValueChanged<DateTime?> onPick) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final active = from != null || to != null;
    return Row(
      children: [
        const Icon(Icons.date_range_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () =>
                _pick(context, from, onFrom),
            child: Text(
                from == null ? 'من' : 'من ${_fmt.format(from!)}'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => _pick(context, to, onTo),
            child: Text(
                to == null ? 'إلى' : 'إلى ${_fmt.format(to!)}'),
          ),
        ),
        if (active) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'مسح فلتر التاريخ',
            iconSize: 20,
            icon: const Icon(Icons.clear_outlined),
            onPressed: onClear,
          ),
        ],
      ],
    );
  }
}
