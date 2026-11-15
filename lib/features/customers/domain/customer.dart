class Customer {
  final String id;
  final String code;
  final String name;
  final String? phone;
  final String? email;
  final String? taxNumber;
  final String? company;
  final double creditLimit;
  final bool isActive;
  final String? notes;

  const Customer({
    required this.id,
    required this.code,
    required this.name,
    this.phone,
    this.email,
    this.taxNumber,
    this.company,
    required this.creditLimit,
    required this.isActive,
    this.notes,
  });

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory Customer.fromMap(Map<String, dynamic> m) {
    return Customer(
      id: m['id'] as String,
      code: (m['customer_code'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      phone: m['phone'] as String?,
      email: m['email'] as String?,
      taxNumber: m['tax_number'] as String?,
      company: m['company'] as String?,
      creditLimit: _num(m['credit_limit']),
      isActive: (m['is_active'] as bool?) ?? true,
      notes: m['notes'] as String?,
    );
  }
}

class CustomerAddress {
  final String id;
  final String customerId;
  final String? label;
  final String? addressLine;
  final String? governorate;
  final String? city;
  final String? area;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final bool isDefault;

  const CustomerAddress({
    required this.id,
    required this.customerId,
    this.label,
    this.addressLine,
    this.governorate,
    this.city,
    this.area,
    this.latitude,
    this.longitude,
    this.phone,
    required this.isDefault,
  });

  factory CustomerAddress.fromMap(Map<String, dynamic> m) {
    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return CustomerAddress(
      id: m['id'] as String,
      customerId: m['customer_id'] as String,
      label: m['label'] as String?,
      addressLine: m['address_line'] as String?,
      governorate: m['governorate'] as String?,
      city: m['city'] as String?,
      area: m['area'] as String?,
      latitude: d(m['latitude']),
      longitude: d(m['longitude']),
      phone: m['phone'] as String?,
      isDefault: (m['is_default'] as bool?) ?? false,
    );
  }

  String get display {
    final parts = [
      addressLine,
      area,
      city,
      governorate,
    ].where((e) => e?.isNotEmpty == true).join(' - ');
    return parts.isEmpty ? (label ?? 'عنوان') : parts;
  }
}
