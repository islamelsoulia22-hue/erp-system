/// تصنيف مصروف (يضيفه المدير).
class ExpenseCategory {
  final String id;
  final String? code;
  final String name;
  final String? nameAr;
  final bool isActive;

  const ExpenseCategory({
    required this.id,
    this.code,
    required this.name,
    this.nameAr,
    required this.isActive,
  });

  factory ExpenseCategory.fromMap(Map<String, dynamic> m) {
    return ExpenseCategory(
      id: m['id'] as String,
      code: m['code'] as String?,
      name: (m['name'] as String?) ?? '',
      nameAr: m['name_ar'] as String?,
      isActive: (m['is_active'] as bool?) ?? true,
    );
  }

  String get display =>
      (nameAr?.isNotEmpty == true ? nameAr! : name);
}

/// مصروف: دورة (مسودة → اعتماد → دفع). الاعتماد ≠ الدفع.
class Expense {
  final String id;
  final String number;
  final String? categoryId;
  final String? categoryName;
  final String title;
  final double amount;
  final DateTime expenseDate;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final String? partyName;
  final String? referenceNumber;
  final String? warehouseId;
  final String? warehouseName;
  final String? notes;
  final String status;
  final String paymentStatus;
  final String? createdBy;
  final String? rejectionReason;
  final String? groupId;
  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.number,
    this.categoryId,
    this.categoryName,
    required this.title,
    required this.amount,
    required this.expenseDate,
    this.paymentMethodId,
    this.paymentMethodName,
    this.partyName,
    this.referenceNumber,
    this.warehouseId,
    this.warehouseName,
    this.notes,
    required this.status,
    required this.paymentStatus,
    this.createdBy,
    this.rejectionReason,
    this.groupId,
    required this.createdAt,
  });

  bool get isPaid => paymentStatus == 'PAID';
  bool get editable =>
      status == 'DRAFT' || status == 'REJECTED';
  bool get pending => status == 'PENDING_APPROVAL';

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory Expense.fromMap(Map<String, dynamic> m) {
    final c = m['expense_categories'];
    final w = m['warehouses'];
    final pm = m['payment_methods'];
    String? catName;
    if (c is Map) {
      final ar = (c['name_ar'] as String?)?.trim();
      final en = (c['name'] as String?)?.trim();
      catName = (ar?.isNotEmpty == true ? ar : en);
    }
    String? payName;
    if (pm is Map) {
      final ar = (pm['name_ar'] as String?)?.trim();
      final en = (pm['name'] as String?)?.trim();
      payName = (ar?.isNotEmpty == true ? ar : en);
    }
    return Expense(
      id: m['id'] as String,
      number: (m['expense_number'] as String?) ?? '',
      categoryId: m['category_id'] as String?,
      categoryName: catName,
      title: (m['title'] as String?) ?? '',
      amount: _n(m['amount']),
      expenseDate: DateTime.tryParse(
              m['expense_date']?.toString() ?? '') ??
          DateTime.now(),
      paymentMethodId: m['payment_method_id'] as String?,
      paymentMethodName: payName,
      partyName: m['party_name'] as String?,
      referenceNumber: m['reference_number'] as String?,
      warehouseId: m['warehouse_id'] as String?,
      warehouseName:
          w is Map ? (w['name'] as String?) : null,
      notes: m['notes'] as String?,
      status: (m['status'] as String?) ?? 'DRAFT',
      paymentStatus:
          (m['payment_status'] as String?) ?? 'UNPAID',
      createdBy: m['created_by'] as String?,
      rejectionReason: m['rejection_reason'] as String?,
      groupId: m['group_id'] as String?,
      createdAt: DateTime.tryParse(
              m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

String expenseStatusAr(String status, String paymentStatus) {
  if (status == 'APPROVED' && paymentStatus == 'PAID') {
    return 'مدفوعة';
  }
  return switch (status) {
    'DRAFT' => 'مسودة',
    'PENDING_APPROVAL' => 'بانتظار الاعتماد',
    'APPROVED' => 'معتمدة (غير مدفوعة)',
    'REJECTED' => 'مرفوضة',
    'CANCELLED' => 'ملغاة',
    _ => status,
  };
}
