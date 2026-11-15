class POItemInput {
  final String? productId;
  final String productName;
  final String? sku;
  final double quantity;
  final double unitCost;
  final double taxRate;

  const POItemInput({
    this.productId,
    required this.productName,
    this.sku,
    required this.quantity,
    required this.unitCost,
    this.taxRate = 0,
  });

  Map<String, dynamic> toMap(String orderId) => {
        'purchase_order_id': orderId,
        'product_id': productId,
        'product_name': productName,
        'sku': sku,
        'quantity': quantity,
        'unit_cost': unitCost,
        'tax_rate': taxRate,
      };
}

class PIItemInput {
  final String? productId;
  final String productName;
  final String? sku;
  final double quantity;
  final double unitCost;
  final double taxRate;

  const PIItemInput({
    this.productId,
    required this.productName,
    this.sku,
    required this.quantity,
    required this.unitCost,
    this.taxRate = 0,
  });

  Map<String, dynamic> toMap(String invoiceId) => {
        'purchase_invoice_id': invoiceId,
        'product_id': productId,
        'product_name_snapshot': productName,
        'sku_snapshot': sku,
        'quantity': quantity,
        'unit_cost': unitCost,
        'tax_rate': taxRate,
      };
}

class PurchaseOrder {
  final String id;
  final String number;
  final String? supplierId;
  final String? supplierName;
  final String? warehouseId;
  final String status;
  final double grandTotal;
  final String? createdBy;
  final DateTime createdAt;

  const PurchaseOrder({
    required this.id,
    required this.number,
    this.supplierId,
    this.supplierName,
    this.warehouseId,
    required this.status,
    required this.grandTotal,
    this.createdBy,
    required this.createdAt,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory PurchaseOrder.fromMap(Map<String, dynamic> m) {
    return PurchaseOrder(
      id: m['id'] as String,
      number: (m['order_number'] as String?) ?? '',
      supplierId: m['supplier_id'] as String?,
      supplierName: m['suppliers'] is Map
          ? ((m['suppliers'] as Map)['name'] as String?)
          : null,
      warehouseId: m['warehouse_id'] as String?,
      status: (m['status'] as String?) ?? 'DRAFT',
      grandTotal: _n(m['grand_total']),
      createdBy: m['created_by'] as String?,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class PurchaseOrderItem {
  final String id;
  final String? productId;
  final String productName;
  final double quantity;
  final double received;
  final double unitCost;
  final double total;

  const PurchaseOrderItem({
    required this.id,
    this.productId,
    required this.productName,
    required this.quantity,
    required this.received,
    required this.unitCost,
    required this.total,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> m) {
    return PurchaseOrderItem(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      productName: (m['product_name'] as String?) ?? '',
      quantity: _n(m['quantity']),
      received: _n(m['received_quantity']),
      unitCost: _n(m['unit_cost']),
      total: _n(m['total']),
    );
  }

  double get remaining => quantity - received;
}

class PurchaseInvoice {
  final String id;
  final String number;
  final String? referenceNumber;
  final String? supplierId;
  final String? supplierName;
  final String? warehouseId;
  final String? warehouseName;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final String? paymentMethodCode;
  final String status;
  final String paymentStatus;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double grandTotal;
  final String? createdBy;
  final String? rejectionReason;
  final DateTime createdAt;

  const PurchaseInvoice({
    required this.id,
    required this.number,
    this.referenceNumber,
    this.supplierId,
    this.supplierName,
    this.warehouseId,
    this.warehouseName,
    this.paymentMethodId,
    this.paymentMethodName,
    this.paymentMethodCode,
    required this.status,
    this.paymentStatus = 'UNPAID',
    this.subtotal = 0,
    this.discount = 0,
    this.taxAmount = 0,
    required this.grandTotal,
    this.createdBy,
    this.rejectionReason,
    required this.createdAt,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String? _warehouseName(Map<String, dynamic> m) {
    final w = m['warehouses'];
    if (w is Map) return (w['name'] as String?)?.trim().isEmpty == true ? null : w['name'] as String?;
    return null;
  }

  static String? _paymentMethodName(Map<String, dynamic> m) {
    final pm = m['payment_methods'];
    if (pm is Map) {
      final ar = (pm['name_ar'] as String?)?.trim();
      final en = (pm['name'] as String?)?.trim();
      final v = (ar?.isNotEmpty == true ? ar : en);
      return v?.isEmpty == true ? null : v;
    }
    return null;
  }

  static String? _paymentMethodCode(Map<String, dynamic> m) {
    final pm = m['payment_methods'];
    if (pm is Map) {
      final c = (pm['code'] as String?)?.trim().toUpperCase();
      return c?.isEmpty == true ? null : c;
    }
    return null;
  }

  factory PurchaseInvoice.fromMap(Map<String, dynamic> m) {
    return PurchaseInvoice(
      id: m['id'] as String,
      number: (m['invoice_number'] as String?) ?? '',
      referenceNumber: (m['reference_number'] as String?)?.trim().isEmpty == true
          ? null
          : m['reference_number'] as String?,
      supplierId: m['supplier_id'] as String?,
      supplierName: (m['supplier_name_snapshot'] as String?) ??
          (m['suppliers'] is Map
              ? ((m['suppliers'] as Map)['name'] as String?)
              : null),
      warehouseId: m['warehouse_id'] as String?,
      warehouseName: _warehouseName(m),
      paymentMethodId: m['payment_method_id'] as String?,
      paymentMethodName: _paymentMethodName(m),
      paymentMethodCode: _paymentMethodCode(m),
      status: (m['status'] as String?) ?? 'DRAFT',
      paymentStatus:
          (m['payment_status'] as String?) ?? 'UNPAID',
      subtotal: _n(m['subtotal']),
      discount: _n(m['discount']),
      taxAmount: _n(m['tax_amount']),
      grandTotal: _n(m['grand_total']),
      createdBy: m['created_by'] as String?,
      rejectionReason: m['rejection_reason'] as String?,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class PurchaseInvoiceItem {
  final String id;
  final String? productId;
  final String productName;
  final double quantity;
  final double unitCost;
  final double discount;
  final double taxRate;
  final double total;

  const PurchaseInvoiceItem({
    required this.id,
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    this.discount = 0,
    this.taxRate = 0,
    required this.total,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory PurchaseInvoiceItem.fromMap(Map<String, dynamic> m) {
    return PurchaseInvoiceItem(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      productName: (m['product_name_snapshot'] as String?) ??
          (m['product_name'] as String?) ??
          '',
      quantity: _n(m['quantity']),
      unitCost: _n(m['unit_cost']),
      discount: _n(m['discount']),
      taxRate: _n(m['tax_rate']),
      total: _n(m['total']),
    );
  }
}
