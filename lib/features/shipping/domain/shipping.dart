class Shipment {
  final String id;
  final String number;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? customerId;
  final String status;
  final String? recipient;
  final String? phone;
  final String? city;
  final double cost;
  final DateTime createdAt;

  const Shipment({
    required this.id,
    required this.number,
    this.invoiceId,
    this.invoiceNumber,
    this.customerId,
    required this.status,
    this.recipient,
    this.phone,
    this.city,
    required this.cost,
    required this.createdAt,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory Shipment.fromMap(Map<String, dynamic> m) {
    final inv = m['sales_invoices'];
    return Shipment(
      id: m['id'] as String,
      number: (m['shipment_number'] as String?) ?? '',
      invoiceId: m['sales_invoice_id'] as String?,
      invoiceNumber: inv is Map
          ? ((inv['invoice_number'] as String?) ?? '')
          : null,
      customerId: m['customer_id'] as String?,
      status: (m['status'] as String?) ?? 'PREPARING',
      recipient: m['recipient_name'] as String?,
      phone: m['recipient_phone'] as String?,
      city: m['city'] as String?,
      cost: _n(m['shipping_cost']),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class Payment {
  final String id;
  final String number;
  final double amount;
  final String? methodCode;
  final String? reference;
  final DateTime date;
  final String? salesInvoiceId;
  final String? purchaseInvoiceId;
  final String status;
  final String? invoiceNumber;
  final String? partnerName;

  const Payment({
    required this.id,
    required this.number,
    required this.amount,
    this.methodCode,
    this.reference,
    required this.date,
    this.salesInvoiceId,
    this.purchaseInvoiceId,
    this.status = 'COMPLETED',
    this.invoiceNumber,
    this.partnerName,
  });

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory Payment.fromMap(Map<String, dynamic> m) {
    final pm = m['payment_methods'];
    final si = m['sales_invoices'];
    final pi = m['purchase_invoices'];
    String? invNo;
    String? partner;
    if (si is Map) {
      invNo = si['invoice_number'] as String?;
      partner = (si['customer_name_snapshot'] as String?) ??
          ((si['customers'] is Map)
              ? ((si['customers'] as Map)['name'] as String?)
              : null);
    } else if (pi is Map) {
      invNo = pi['invoice_number'] as String?;
      partner = (pi['supplier_name_snapshot'] as String?) ??
          ((pi['suppliers'] is Map)
              ? ((pi['suppliers'] as Map)['name'] as String?)
              : null);
    }
    return Payment(
      id: m['id'] as String,
      number: (m['payment_number'] as String?) ?? '',
      amount: _n(m['amount']),
      methodCode: pm is Map
          ? ((pm['code'] as String?) ?? '')
          : (m['method_code'] as String?),
      reference: m['transaction_reference'] as String?,
      date: DateTime.tryParse(m['payment_date']?.toString() ?? '') ??
          DateTime.now(),
      salesInvoiceId: m['sales_invoice_id'] as String?,
      purchaseInvoiceId: m['purchase_invoice_id'] as String?,
      status: (m['status'] as String?) ?? 'COMPLETED',
      invoiceNumber: invNo,
      partnerName: partner,
    );
  }
}

class Balance {
  final double total;
  final double paid;
  final double outstanding;
  const Balance(
      {required this.total,
      required this.paid,
      required this.outstanding});

  factory Balance.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    return Balance(
        total: n(m['total']),
        paid: n(m['paid']),
        outstanding: n(m['outstanding']));
  }
}
