class SalesItemInput {
  final String? productId;
  final String itemName;
  final String? sku;
  final double quantity;
  final double unitPrice;
  final double unitCost;
  final double discount;
  final double taxRate;
  // حقول الصنف الخاص (CUSTOMIZED فقط).
  final String itemType;
  final String? customUnit;
  final double? lengthValue;
  final String? lengthUnit;
  final double? widthValue;
  final String? widthUnit;
  final String? rawMaterialId;
  final String? rawMaterialName;
  final double? qtyPerRoll;
  final String? customNotes;
  // سيريالات العميل المختارة في الفاتورة (إلكترونيات).
  final List<String> serialNumbers;

  const SalesItemInput({
    this.productId,
    required this.itemName,
    this.sku,
    required this.quantity,
    required this.unitPrice,
    this.unitCost = 0,
    this.discount = 0,
    this.taxRate = 0,
    this.itemType = 'STANDARD',
    this.customUnit,
    this.lengthValue,
    this.lengthUnit,
    this.widthValue,
    this.widthUnit,
    this.rawMaterialId,
    this.rawMaterialName,
    this.qtyPerRoll,
    this.customNotes,
    this.serialNumbers = const [],
  });

  Map<String, dynamic> toMap(String invoiceId) => {
        'sales_invoice_id': invoiceId,
        'product_id': productId,
        'item_type': itemType,
        'item_name': itemName,
        'sku': sku,
        'quantity': quantity,
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'discount': discount,
        'tax_rate': taxRate,
        'custom_unit': customUnit,
        'length_value': lengthValue,
        'length_unit': lengthUnit,
        'width_value': widthValue,
        'width_unit': widthUnit,
        'raw_material_id': rawMaterialId,
        'raw_material_name': rawMaterialName,
        'qty_per_roll': qtyPerRoll,
        'custom_notes': customNotes,
        'serial_numbers': serialNumbers,
      };
}

class SalesInvoice {
  final String id;
  final String number;
  final String? reference;
  final String? customerId;
  final String? customerName;
  final String? warehouseId;
  final String? warehouseName;
  final String? paymentMethodId;
  final String? paymentMethodName;
  final String? paymentMethodCode;
  final String paymentStatus;
  final String status;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double grandTotal;
  final String? createdBy;
  final String? rejectionReason;
  final DateTime createdAt;

  const SalesInvoice({
    required this.id,
    required this.number,
    this.reference,
    this.customerId,
    this.customerName,
    this.warehouseId,
    this.warehouseName,
    this.paymentMethodId,
    this.paymentMethodName,
    this.paymentMethodCode,
    this.paymentStatus = 'UNPAID',
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.grandTotal,
    this.createdBy,
    this.rejectionReason,
    required this.createdAt,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory SalesInvoice.fromMap(Map<String, dynamic> m) {
    String? warehouseName;
    final w = m['warehouses'];
    if (w is Map) {
      final n = (w['name'] as String?)?.trim();
      warehouseName = n?.isEmpty == true ? null : n;
    }
    String? paymentMethodName;
    final pm = m['payment_methods'];
    String? paymentMethodCode;
    if (pm is Map) {
      final ar = (pm['name_ar'] as String?)?.trim();
      final en = (pm['name'] as String?)?.trim();
      final v = (ar?.isNotEmpty == true ? ar : en);
      paymentMethodName = v?.isEmpty == true ? null : v;
      final c = (pm['code'] as String?)?.trim();
      paymentMethodCode = c?.isEmpty == true ? null : c;
    }
    return SalesInvoice(
      id: m['id'] as String,
      number: (m['invoice_number'] as String?) ?? '',
      reference: m['reference_number'] as String?,
      customerId: m['customer_id'] as String?,
      customerName: (m['customer_name_snapshot'] as String?) ??
          (m['customers'] is Map
              ? ((m['customers'] as Map)['name'] as String?)
              : null),
      warehouseId: m['warehouse_id'] as String?,
      warehouseName: warehouseName,
      paymentMethodId: m['payment_method_id'] as String?,
      paymentMethodName: paymentMethodName,
      paymentMethodCode: paymentMethodCode,
      paymentStatus: (m['payment_status'] as String?) ?? 'UNPAID',
      status: (m['status'] as String?) ?? 'DRAFT',
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

class SalesInvoiceItem {
  final String id;
  final String? productId;
  final String itemName;
  final String? sku;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxRate;
  final double total;
  final String itemType;
  final String? customUnit;
  final double? lengthValue;
  final String? lengthUnit;
  final double? widthValue;
  final String? widthUnit;
  final String? rawMaterialId;
  final String? rawMaterialName;
  final double? qtyPerRoll;
  final String? customNotes;
  final String? customizedItemId;
  final double unitCost;
  final List<String> serialNumbers;

  const SalesInvoiceItem({
    required this.id,
    this.productId,
    required this.itemName,
    this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.total,
    this.itemType = 'STANDARD',
    this.customUnit,
    this.lengthValue,
    this.lengthUnit,
    this.widthValue,
    this.widthUnit,
    this.rawMaterialId,
    this.rawMaterialName,
    this.qtyPerRoll,
    this.customNotes,
    this.customizedItemId,
    this.unitCost = 0,
    this.serialNumbers = const [],
  });

  bool get isCustom => itemType == 'CUSTOMIZED';

  /// ربح السطر = (البيع - الخصم) - (التكلفة × الكمية)، بدون ضريبة.
  /// الأصناف الخاصة تكلفتها سعر الشراء المدخل في الشيت.
  double get lineProfit =>
      (quantity * unitPrice - discount) - (quantity * unitCost);

  /// سطر ملخص المواصفات للعرض (مقاس + خامة + Qty/Roll).
  String get specSummary {
    if (!isCustom) return '';
    final parts = <String>[];
    if (lengthValue != null && widthValue != null) {
      parts.add(
          '${_fmtNum(lengthValue!)} × ${_fmtNum(widthValue!)} ${lengthUnit ?? widthUnit ?? ''}'
              .trim());
    }
    if (rawMaterialName?.isNotEmpty == true) {
      parts.add(rawMaterialName!);
    }
    if (qtyPerRoll != null) {
      parts.add('Qty/Roll: ${_fmtNum(qtyPerRoll!)}');
    }
    return parts.join(' • ');
  }

  static String _fmtNum(double v) {
    return v == v.truncateToDouble()
        ? v.truncate().toString()
        : v.toString();
  }

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double? _on(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory SalesInvoiceItem.fromMap(Map<String, dynamic> m) {
    return SalesInvoiceItem(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      itemName: (m['item_name'] as String?) ?? '',
      sku: m['sku'] as String?,
      quantity: _n(m['quantity']),
      unitPrice: _n(m['unit_price']),
      discount: _n(m['discount']),
      taxRate: _n(m['tax_rate']),
      total: _n(m['total']),
      itemType: (m['item_type'] as String?) ?? 'STANDARD',
      customUnit: m['custom_unit'] as String?,
      lengthValue: _on(m['length_value']),
      lengthUnit: m['length_unit'] as String?,
      widthValue: _on(m['width_value']),
      widthUnit: m['width_unit'] as String?,
      rawMaterialId: m['raw_material_id'] as String?,
      rawMaterialName: m['raw_material_name'] as String?,
      qtyPerRoll: _on(m['qty_per_roll']),
      customNotes: m['custom_notes'] as String?,
      customizedItemId: m['customized_item_id'] as String?,
      unitCost: _n(m['unit_cost']),
      serialNumbers: m['serial_numbers'] is List
          ? [
              for (final s in (m['serial_numbers'] as List))
                '$s'
            ]
          : const [],
    );
  }
}
