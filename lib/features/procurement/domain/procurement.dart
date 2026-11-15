class ProcurementItem {
  final String id;
  final String? productId;
  final String? productName;
  final double requested;
  final double available;
  final double missing;
  final double received;

  const ProcurementItem({
    required this.id,
    this.productId,
    this.productName,
    required this.requested,
    required this.available,
    required this.missing,
    required this.received,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ProcurementItem.fromMap(Map<String, dynamic> m) {
    final p = m['products'];
    return ProcurementItem(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      productName: p is Map
          ? ((p['name'] as String?) ?? '')
          : (m['product_name'] as String?),
      requested: _n(m['requested_quantity']),
      available: _n(m['available_quantity']),
      missing: _n(m['missing_quantity']),
      received: _n(m['received_quantity']),
    );
  }

  double get remaining => requested - received;
}

class ProcurementRequest {
  final String id;
  final String number;
  final String? supplierId;
  final String? supplierName;
  final String? warehouseId;
  final String? warehouseName;
  final String status;
  final String? reason;
  final String? requestedBy;
  final DateTime createdAt;
  // ربط فاتورة المبيعات (دورة الحجز): الفاتورة اللي طلبت التوريد.
  final String? salesInvoiceId;
  final String? salesInvoiceNumber;
  final String? salesCustomerName;
  final double salesGrandTotal;

  const ProcurementRequest({
    required this.id,
    required this.number,
    this.supplierId,
    this.supplierName,
    this.warehouseId,
    this.warehouseName,
    required this.status,
    this.reason,
    this.requestedBy,
    required this.createdAt,
    this.salesInvoiceId,
    this.salesInvoiceNumber,
    this.salesCustomerName,
    this.salesGrandTotal = 0,
  });

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ProcurementRequest.fromMap(Map<String, dynamic> m) {
    final s = m['suppliers'];
    final w = m['warehouses'];
    final inv = m['sales_invoices'];
    return ProcurementRequest(
      id: m['id'] as String,
      number: (m['request_number'] as String?) ?? '',
      supplierId: m['supplier_id'] as String?,
      supplierName: s is Map
          ? ((s['name'] as String?) ?? '')
          : (m['supplier_name'] as String?),
      warehouseId: m['warehouse_id'] as String?,
      warehouseName: w is Map
          ? ((w['name'] as String?) ?? '')
          : (m['warehouse_name'] as String?),
      status: (m['status'] as String?) ?? 'DRAFT',
      reason: m['reason'] as String?,
      requestedBy: m['requested_by'] as String?,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
      salesInvoiceId: m['sales_invoice_id'] as String?,
      salesInvoiceNumber: inv is Map
          ? ((inv['invoice_number'] as String?) ?? '')
          : (m['sales_invoice_number'] as String?),
      salesCustomerName: inv is Map
          ? (((inv['customer_name_snapshot'] ?? inv['customer_name'])
                  as String?) ??
              '')
          : (m['sales_customer_name'] as String?),
      salesGrandTotal: inv is Map
          ? _num(inv['grand_total'])
          : _num(m['sales_grand_total']),
    );
  }
}

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String? message;
  final String? entityType;
  final String? entityId;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.message,
    this.entityType,
    this.entityId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    return AppNotification(
      id: m['id'] as String,
      type: (m['type'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      message: m['message'] as String?,
      entityType: m['entity_type'] as String?,
      entityId: m['entity_id'] as String?,
      isRead: (m['is_read'] as bool?) ?? false,
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
