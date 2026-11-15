class ReturnDoc {
  final String id;
  final String number;
  final String? linkId;
  final String? partner;
  final String status;
  final double total;
  final DateTime createdAt;

  const ReturnDoc({
    required this.id,
    required this.number,
    this.linkId,
    this.partner,
    required this.status,
    required this.total,
    required this.createdAt,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ReturnDoc.sales(Map<String, dynamic> m) {
    return ReturnDoc(
      id: m['id'] as String,
      number: (m['return_number'] as String?) ?? '',
      linkId: m['sales_invoice_id'] as String?,
      partner: m['customers'] is Map
          ? ((m['customers'] as Map)['name'] as String?)
          : null,
      status: (m['status'] as String?) ?? 'DRAFT',
      total: _n(m['grand_total']),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  factory ReturnDoc.purchase(Map<String, dynamic> m) {
    return ReturnDoc(
      id: m['id'] as String,
      number: (m['return_number'] as String?) ?? '',
      linkId: m['purchase_invoice_id'] as String?,
      partner: m['suppliers'] is Map
          ? ((m['suppliers'] as Map)['name'] as String?)
          : null,
      status: (m['status'] as String?) ?? 'DRAFT',
      total: _n(m['grand_total']),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ReturnItem {
  final String id;
  final String? productId;
  final String name;
  final double qty;
  final double price;
  final double total;

  const ReturnItem({
    required this.id,
    this.productId,
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ReturnItem.sales(Map<String, dynamic> m) {
    return ReturnItem(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      name: (m['item_name'] as String?) ?? '',
      qty: _n(m['quantity']),
      price: _n(m['unit_price']),
      total: _n(m['total']),
    );
  }

  factory ReturnItem.purchase(Map<String, dynamic> m) {
    return ReturnItem(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      name: (m['product_name'] as String?) ?? '',
      qty: _n(m['quantity']),
      price: _n(m['unit_cost']),
      total: _n(m['total']),
    );
  }
}
