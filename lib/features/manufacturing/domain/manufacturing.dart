class CustomizedItem {
  final String id;
  final String code;
  final String name;
  final String? description;
  final String? rawMaterial;
  final String? rawMaterialId;
  final double? length;
  final String? lengthUnit;
  final double? width;
  final String? widthUnit;
  final double? qtyPerRoll;
  final String? unit;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String status;
  final String? warehouseId;
  final String? salesInvoiceId;
  final String? salesInvoiceItemId;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;

  const CustomizedItem({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.rawMaterial,
    this.rawMaterialId,
    this.length,
    this.lengthUnit,
    this.width,
    this.widthUnit,
    this.qtyPerRoll,
    this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.status,
    this.warehouseId,
    this.salesInvoiceId,
    this.salesInvoiceItemId,
    this.createdBy,
    this.createdByName,
    required this.createdAt,
  });

  /// هل ناتج عن فاتورة مبيعات (صنف خاص)؟
  bool get fromSalesInvoice => salesInvoiceId != null;

  String get specSummary {
    final parts = <String>[];
    if (length != null && width != null) {
      parts.add(
          '${_f(length!)} × ${_f(width!)} ${lengthUnit ?? widthUnit ?? ''}'
              .trim());
    }
    if (rawMaterial?.isNotEmpty == true) parts.add(rawMaterial!);
    if (qtyPerRoll != null) {
      parts.add('Qty/Roll: ${_f(qtyPerRoll!)}');
    }
    return parts.join(' • ');
  }

  static String _f(double v) =>
      v == v.truncateToDouble() ? v.truncate().toString() : v.toString();

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _on(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory CustomizedItem.fromMap(Map<String, dynamic> m) {
    return CustomizedItem(
      id: m['id'] as String,
      code: (m['code'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      description: m['description'] as String?,
      rawMaterial: m['raw_material'] as String?,
      rawMaterialId: m['raw_material_id'] as String?,
      length: _on(m['length']),
      lengthUnit: m['length_unit'] as String?,
      width: _on(m['width']),
      widthUnit: m['width_unit'] as String?,
      qtyPerRoll: _on(m['qty_per_roll']),
      unit: m['unit'] as String?,
      quantity: _n(m['quantity']),
      unitPrice: _n(m['unit_price']),
      totalPrice: _n(m['total_price']),
      status: (m['status'] as String?) ?? 'DRAFT',
      warehouseId: m['warehouse_id'] as String?,
      salesInvoiceId: m['sales_invoice_id'] as String?,
      salesInvoiceItemId:
          m['sales_invoice_item_id'] as String?,
      createdBy: m['created_by'] as String?,
      createdByName: m['created_by_name'] as String?,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ManufacturingOrder {
  final String id;
  final String number;
  final String? customizedId;
  final String? warehouseId;
  final String? finishedProductId;
  final double? finishedQty;
  final String status;
  final double quantity;
  final DateTime createdAt;

  const ManufacturingOrder({
    required this.id,
    required this.number,
    this.customizedId,
    this.warehouseId,
    this.finishedProductId,
    this.finishedQty,
    required this.status,
    required this.quantity,
    required this.createdAt,
  });

  static double? _on(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ManufacturingOrder.fromMap(Map<String, dynamic> m) {
    return ManufacturingOrder(
      id: m['id'] as String,
      number: (m['order_number'] as String?) ?? '',
      customizedId: m['customized_item_id'] as String?,
      warehouseId: m['warehouse_id'] as String?,
      finishedProductId: m['finished_product_id'] as String?,
      finishedQty: _on(m['finished_quantity']),
      status: (m['status'] as String?) ?? 'DRAFT',
      quantity: _n(m['quantity']),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ManufacturingMaterial {
  final String id;
  final String? productId;
  final String? productName;
  final double requiredQty;
  final double consumedQty;

  const ManufacturingMaterial({
    required this.id,
    this.productId,
    this.productName,
    required this.requiredQty,
    required this.consumedQty,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ManufacturingMaterial.fromMap(Map<String, dynamic> m) {
    final p = m['products'];
    return ManufacturingMaterial(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      productName: p is Map
          ? ((p['name'] as String?) ?? '')
          : (m['product_name'] as String? ?? ''),
      requiredQty: _n(m['required_quantity']),
      consumedQty: _n(m['consumed_quantity']),
    );
  }
}
