import 'package:flutter/material.dart';

import '../errors/failures.dart';
import '../theme/app_colors.dart';

/// حوار تأكيد حذف مشترك لكل الشاشات (المدير فقط).
Future<bool> confirmDelete(
    BuildContext context, String label) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text(
          'سيتم حذف "$label" نهائيا ولا يمكن التراجع. هل أنت متأكد؟'),
      actions: [
        TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(false),
            child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
          ),
          onPressed: () =>
              Navigator.of(ctx).pop(true),
          child: const Text('حذف نهائي'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// رسالة خطأ حذف موحدة.
String deleteErrorMessage(Object e) {
  if (e is AppFailure) return e.messageAr;
  return 'تعذر الحذف، برجاء المحاولة مرة أخرى.';
}
