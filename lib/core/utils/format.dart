import 'package:intl/intl.dart';

/// Arabic formatting helpers. Single place for money/date rendering.
abstract final class AppFormat {
  static final NumberFormat _money =
      NumberFormat('#,##0.##', 'ar_EG');

  static String money(num value, {String suffix = ' ج.م'}) =>
      '${_money.format(value)}$suffix';

  static String moneyCompact(num value) {
    final v = value.toDouble();
    if (v.abs() >= 1000000) {
      return '${_money.format(v / 1000000)} م ج.م';
    }
    if (v.abs() >= 1000) {
      return '${_money.format(v / 1000)} ألف ج.م';
    }
    return money(v);
  }

  static String date(DateTime d) =>
      DateFormat('d MMM yyyy', 'ar').format(d);

  static String dateTime(DateTime d) =>
      DateFormat('d MMM yyyy • HH:mm', 'ar').format(d);

  static String weekday(DateTime d) =>
      DateFormat('EEEE، d MMMM yyyy', 'ar').format(d);
}
