import 'package:flutter/material.dart';

/// مساعدات شاشات اللوكال المشتركة.
double parseNum(String s) => double.tryParse(s.trim()) ?? 0;

/// تأكيد حذف عام.
Future<bool> confirmLocalDelete(
  BuildContext context,
  String title, [
  String? body,
]) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  return ok == true;
}

String localInvoiceStatusAr(String s) {
  return switch (s) {
    'DRAFT' => 'مسودة',
    'APPROVED' => 'معتمدة',
    'UNPAID' => 'غير مدفوعة',
    'PARTIAL' => 'مدفوعة جزئيا',
    'PAID' => 'مدفوعة بالكامل',
    _ => s,
  };
}

/// لون حالة السداد.
Color paymentStatusColor(String s) {
  return switch (s) {
    'PAID' => Colors.green,
    'PARTIAL' => Colors.orange,
    _ => Colors.grey,
  };
}
