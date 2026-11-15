class Warehouse {
  final String id;
  final String code;
  final String name;
  final String? location;
  final String? managerId;
  final bool isActive;

  const Warehouse({
    required this.id,
    required this.code,
    required this.name,
    this.location,
    this.managerId,
    required this.isActive,
  });

  factory Warehouse.fromMap(Map<String, dynamic> m) {
    return Warehouse(
      id: m['id'] as String,
      code: (m['code'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      location: m['location'] as String?,
      managerId: m['manager_id'] as String?,
      isActive: (m['is_active'] as bool?) ?? true,
    );
  }
}

class StockLine {
  final String id;
  final String warehouseId;
  final String warehouseName;
  final String productId;
  final String productName;
  final String productSku;
  final double quantity;
  final double reserved;
  final double available;

  const StockLine({
    required this.id,
    required this.warehouseId,
    required this.warehouseName,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.quantity,
    required this.reserved,
    required this.available,
  });

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory StockLine.fromMap(Map<String, dynamic> m) {
    final wh = m['warehouses'];
    final pr = m['products'];
    return StockLine(
      id: m['id'] as String,
      warehouseId: m['warehouse_id'] as String,
      warehouseName: wh is Map
          ? ((wh['name'] as String?) ?? '')
          : (m['warehouse_name'] as String? ?? ''),
      productId: m['product_id'] as String,
      productName: pr is Map
          ? ((pr['name'] as String?) ?? '')
          : (m['product_name'] as String? ?? ''),
      productSku: pr is Map
          ? ((pr['sku'] as String?) ?? '')
          : (m['product_sku'] as String? ?? ''),
      quantity: _d(m['quantity']),
      reserved: _d(m['reserved_quantity']),
      available: _d(m['available_quantity']),
    );
  }
}

class StockMovement {
  final String id;
  final String warehouseId;
  final String productId;
  final String type;
  final double quantity;
  final double beforeQty;
  final double afterQty;
  final String? referenceType;
  final String? notes;
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.warehouseId,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.beforeQty,
    required this.afterQty,
    this.referenceType,
    this.notes,
    required this.createdAt,
  });

  factory StockMovement.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    return StockMovement(
      id: m['id'] as String,
      warehouseId: m['warehouse_id'] as String,
      productId: m['product_id'] as String,
      type: (m['movement_type'] as String?) ?? '',
      quantity: n(m['quantity']),
      beforeQty: n(m['before_quantity']),
      afterQty: n(m['after_quantity']),
      referenceType: m['reference_type'] as String?,
      notes: m['notes'] as String?,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
