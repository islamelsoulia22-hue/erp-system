class Supplier {
  final String id;
  final String code;
  final String name;
  final String? phone;
  final String? email;
  final String? taxNumber;
  final String? address;
  final String? company;
  final String? supplyCategoryId;
  final double creditLimit;
  final bool isActive;
  final String? notes;

  const Supplier({
    required this.id,
    required this.code,
    required this.name,
    this.phone,
    this.email,
    this.taxNumber,
    this.address,
    this.company,
    this.supplyCategoryId,
    required this.creditLimit,
    required this.isActive,
    this.notes,
  });

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory Supplier.fromMap(Map<String, dynamic> m) {
    return Supplier(
      id: m['id'] as String,
      code: (m['supplier_code'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      phone: m['phone'] as String?,
      email: m['email'] as String?,
      taxNumber: m['tax_number'] as String?,
      address: m['address'] as String?,
      company: m['company'] as String?,
      supplyCategoryId: m['supply_category_id'] as String?,
      creditLimit: _num(m['credit_limit']),
      isActive: (m['is_active'] as bool?) ?? true,
      notes: m['notes'] as String?,
    );
  }
}
