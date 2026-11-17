import 'package:intl/intl.dart';

/// Arabic formatting helpers. Single place for money/date rendering.
///
/// دليل YAD: أرقام لاتينية موحّدة (3,600) مع أسماء الشهور والأيام بالعربي،
/// ومبنية يدويا عشان ماتتأثرش بإعدادات لغة الجهاز.
abstract final class AppFormat {
  static final NumberFormat _money = NumberFormat('#,##0.##', 'en_US');

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  // DateTime.weekday: 1=الاثنين … 7=الأحد
  static const _days = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
    'الجمعة', 'السبت', 'الأحد',
  ];

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
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String dateTime(DateTime d) =>
      '${date(d)} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String weekday(DateTime d) =>
      '${_days[d.weekday - 1]}، ${d.day} ${_months[d.month - 1]} ${d.year}';
}
