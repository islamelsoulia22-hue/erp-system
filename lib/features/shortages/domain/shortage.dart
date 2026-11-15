/// طلب نقص مخزون: بيتسجل تلقائيا عند إنشاء فاتورة بيع
/// لو الكمية المطلوبة مش متاحة أو هتنزل تحت الحد الأدنى.
class Shortage {
  final String id;
  final String? productId;
  final String productName;
  final String? warehouseId;
  final String? warehouseName;
  final String? supplierId;
  final String? supplierName;
  final double requiredQty;
  final String status;
  final String? sourceType;
  final String? sourceId;
  final String? notes;
  final DateTime createdAt;

  const Shortage({
    required this.id,
    this.productId,
    required this.productName,
    this.warehouseId,
    this.warehouseName,
    this.supplierId,
    this.supplierName,
    required this.requiredQty,
    required this.status,
    this.sourceType,
    this.sourceId,
    this.notes,
    required this.createdAt,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory Shortage.fromMap(Map<String, dynamic> m) {
    final p = m['products'];
    final w = m['warehouses'];
    final s = m['suppliers'];
    String name = '';
    if (p is Map) {
      name = (p['name'] as String?) ?? '';
    }
    name = name.isEmpty ? (m['product_name'] as String? ?? '') : name;
    return Shortage(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      productName: name.isEmpty ? 'صنف' : name,
      warehouseId: m['warehouse_id'] as String?,
      warehouseName:
          w is Map ? (w['name'] as String?) : null,
      supplierId: m['supplier_id'] as String?,
      supplierName:
          s is Map ? (s['name'] as String?) : null,
      requiredQty: _n(m['required_qty']),
      status: (m['status'] as String?) ?? 'PENDING',
      sourceType: m['source_type'] as String?,
      sourceId: m['source_id'] as String?,
      notes: m['notes'] as String?,
      createdAt: DateTime.tryParse(
              m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

String shortageStatusAr(String s) {
  return switch (s) {
    'PENDING' => 'بانتظار الطلب',
    'ORDERED' => 'تم طلبها',
    'DONE' => 'تمت',
    'CANCELLED' => 'ملغاة',
    _ => s,
  };
}
