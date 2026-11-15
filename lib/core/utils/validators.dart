/// Arabic-first validation messages.
abstract final class Validators {
  static String? required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'رقم الهاتف مطلوب';
    final v = value.trim();
    if (v.length < 8) return 'رقم الهاتف غير صحيح';
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.isEmpty) return null; // optional in ERP
    // نسخة الجهاز: إيميلات محلية بلا TLD (admin@local) مقبولة.
    const local = String.fromEnvironment('BACKEND', defaultValue: 'supabase') ==
        'local';
    final regex = RegExp(local
        ? r'^[^@\s]+@[^@\s]+$'
        : r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(value)) return 'البريد الإلكتروني غير صحيح';
    return null;
  }

  static String? quantity(String? value) {
    final q = double.tryParse(value ?? '');
    if (q == null || q <= 0) return 'الكمية يجب أن تكون أكبر من صفر';
    return null;
  }
}
