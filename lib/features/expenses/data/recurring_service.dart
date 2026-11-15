import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'expenses_repository.dart';

final _mfmt = DateFormat('yyyy/MM');

/// تكرارات المصروف المتكرر.
abstract final class Frequencies {
  static const weekly = 'WEEKLY';
  static const monthly = 'MONTHLY';
  static const quarterly = 'QUARTERLY';
  static const yearly = 'YEARLY';

  static const all = [weekly, monthly, quarterly, yearly];

  static String labelOf(String code) {
    return switch (code) {
      weekly => 'أسبوعي',
      monthly => 'شهري',
      quarterly => 'ربع سنوي',
      yearly => 'سنوي',
      _ => code,
    };
  }
}

DateTime _d(dynamic v) =>
    DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _lastDayOf(int year, int month) =>
    DateTime(year, month + 1, 0).day;

DateTime _addMonths(DateTime d, int n, int day) {
  final m = DateTime(d.year, d.month + n, 1);
  return DateTime(
      m.year, m.month, day.clamp(1, _lastDayOf(m.year, m.month)));
}

/// أول استحقاق من تاريخ البداية.
DateTime _firstDue(
    DateTime start, String freq, int dayOfDue) {
  final s = _day(start);
  switch (freq) {
    case Frequencies.weekly:
      return s;
    case Frequencies.monthly:
      final c = DateTime(
          s.year, s.month, dayOfDue.clamp(1, _lastDayOf(s.year, s.month)));
      return c.isBefore(s) ? _addMonths(c, 1, dayOfDue) : c;
    case Frequencies.quarterly:
      final c = DateTime(
          s.year, s.month, dayOfDue.clamp(1, _lastDayOf(s.year, s.month)));
      return c.isBefore(s) ? _addMonths(c, 3, dayOfDue) : c;
    case Frequencies.yearly:
      final c = DateTime(
          s.year, s.month, dayOfDue.clamp(1, _lastDayOf(s.year, s.month)));
      return c.isBefore(s) ? _addMonths(c, 12, dayOfDue) : c;
    default:
      return s;
  }
}

/// الاستحقاق التالي بعد تاريخ معين.
DateTime _advance(DateTime d, String freq, int dayOfDue) {
  switch (freq) {
    case Frequencies.weekly:
      return d.add(const Duration(days: 7));
    case Frequencies.monthly:
      return _addMonths(d, 1, dayOfDue);
    case Frequencies.quarterly:
      return _addMonths(d, 3, dayOfDue);
    case Frequencies.yearly:
      return _addMonths(d, 12, dayOfDue);
    default:
      return _addMonths(d, 1, dayOfDue);
  }
}

/// يولد المستحقات المتأخرة لقالب واحد حتى اليوم (أو تاريخ النهاية).
/// يرجع عدد ما تم توليده. لا يرمي أبدا.
Future<int> generateDueForTemplate(
    WidgetRef ref, Map<String, dynamic> t) async {
  try {
    if ((t['status'] as String?) != 'APPROVED') return 0;
    final freq = (t['frequency'] as String?) ?? Frequencies.monthly;
    final dayOfDue = (t['day_of_due'] as num?)?.toInt() ?? 1;
    final startRaw = t['start_date']?.toString();
    if (startRaw == null || startRaw.isEmpty) return 0;
    final start = _day(_d(startRaw));
    final endRaw = t['end_date']?.toString();
    final end = (endRaw == null || endRaw.isEmpty)
        ? null
        : _day(_d(endRaw));
    final today = _day(DateTime.now());
    final upTo = (end != null && end.isBefore(today)) ? end : today;

    DateTime from;
    final nextRaw = t['next_due_date']?.toString();
    if (nextRaw != null && nextRaw.isNotEmpty) {
      from = _day(_d(nextRaw));
    } else {
      from = _firstDue(start, freq, dayOfDue);
    }
    if (from.isBefore(start)) from = _firstDue(start, freq, dayOfDue);

    final repo = ref.read(expensesRepositoryProvider);
    var count = 0;
    var due = from;
    var guard = 0;
    final title = (t['title'] as String?) ?? 'مصروف متكرر';
    while (!due.isAfter(upTo) && guard < 120) {
      await repo.createInstance({
        'category_id': t['category_id'],
        'title': '$title — مستحق ${_mfmt.format(due)}',
        'amount': t['amount'],
        'expense_date':
            due.toIso8601String().substring(0, 10),
        'payment_method_id': t['payment_method_id'],
        'party_name': t['party_name'],
        'warehouse_id': t['warehouse_id'],
        'notes': t['notes'],
        'parent_id': t['id'],
      });
      count++;
      due = _advance(due, freq, dayOfDue);
      guard++;
    }
    if (count > 0 || (end != null && from.isAfter(end))) {
      if (end != null && due.isAfter(end)) {
        // انتهت المدة — إيقاف القالب تلقائيا.
        await repo.updateTemplate(
            t['id'] as String, {'status': 'CANCELLED'});
      } else {
        await repo.updateTemplate(t['id'] as String,
            {'next_due_date': due.toIso8601String().substring(0, 10)});
      }
    }
    return count;
  } catch (e) {
    debugPrint('generateDueForTemplate error: $e');
    return 0;
  }
}

/// يولد المستحقات لكل القوالب النشطة. يرجع الإجمالي.
Future<int> generateAllDue(WidgetRef ref) async {
  try {
    final repo = ref.read(expensesRepositoryProvider);
    final list = await repo.templates();
    var total = 0;
    for (final t in list) {
      total += await generateDueForTemplate(ref, t);
    }
    return total;
  } catch (e) {
    debugPrint('generateAllDue error: $e');
    return 0;
  }
}
