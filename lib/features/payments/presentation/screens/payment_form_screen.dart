import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../purchases/data/purchases_repository.dart';
import '../../../sales/data/sales_repository.dart';
import '../../data/payments_repository.dart';

class PaymentFormScreen extends ConsumerStatefulWidget {
  final String? salesInvoiceId;
  final String? purchaseInvoiceId;
  const PaymentFormScreen(
      {super.key, this.salesInvoiceId, this.purchaseInvoiceId});
  @override
  ConsumerState<PaymentFormScreen> createState() =>
      _PaymentFormScreenState();
}

class _PaymentFormScreenState
    extends ConsumerState<PaymentFormScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String? _methodId;
  String? _methodCode;
  List<Map<String, dynamic>> _methods = [];
  String? _salesId;
  String? _salesNumber;
  String? _purchaseId;
  String? _purchaseNumber;
  double? _purchaseTotal;
  double? _purchasePaid;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _salesId = widget.salesInvoiceId;
    _purchaseId = widget.purchaseInvoiceId;
    Future.microtask(() async {
      final ms =
          await ref.read(paymentsRepositoryProvider).methods();
      if (!mounted) return;
      setState(() {
        _methods = ms;
        if (ms.isNotEmpty) {
          _methodId = ms.first['id'] as String?;
          _methodCode = ms.first['code'] as String?;
        }
      });
    });
    // جاي من دورة الحجز (عربون): هات رقم الفاتورة واعمله مرجع تلقائي.
    Future.microtask(_prefillLinkedInvoice);
  }

  /// لو الشاشة مفتوحة على فاتورة (عربون حجز): يجيب رقمها ويحطه
  /// في الرقم المرجعي تلقائيا — المستخدم ميكتبهوش بإيده.
  Future<void> _prefillLinkedInvoice() async {
    try {
      if (_salesId != null) {
        final inv = await ref
            .read(salesRepositoryProvider)
            .getById(_salesId!);
        if (!mounted) return;
        setState(() {
          _salesNumber = inv?.number;
          if (_reference.text.trim().isEmpty &&
              (inv?.number.isNotEmpty == true)) {
            _reference.text = inv!.number;
          }
        });
      } else if (_purchaseId != null) {
        final inv = await ref
            .read(purchasesRepositoryProvider)
            .getInvoice(_purchaseId!);
        if (!mounted) return;
        setState(() {
          _purchaseNumber = inv?.number;
          if (_reference.text.trim().isEmpty &&
              _purchaseNumber?.isNotEmpty == true) {
            _reference.text = _purchaseNumber!;
          }
        });
        await _loadPurchaseSummary();
      }
    } catch (_) {}
  }

  /// ملخص المستحق لفاتورة المشتريات المختارة
  /// (الإجمالي / المدفوع / المتبقي للمورد).
  Future<void> _loadPurchaseSummary() async {
    final id = _purchaseId;
    if (id == null) return;
    try {
      final inv = await ref
          .read(purchasesRepositoryProvider)
          .getInvoice(id);
      final paid = await ref
          .read(paymentsRepositoryProvider)
          .purchaseInvoicePaid(id);
      if (!mounted || _purchaseId != id) return;
      setState(() {
        _purchaseNumber = inv?.number ?? _purchaseNumber;
        _purchaseTotal = inv?.grandTotal;
        _purchasePaid = paid;
      });
    } catch (_) {}
  }

  bool get _fromLinkedInvoice =>
      widget.salesInvoiceId != null ||
      widget.purchaseInvoiceId != null;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _needsReference =>
      _methodCode == 'INSTAPAY' ||
      _methodCode == 'VODAFONE_CASH' ||
      _methodCode == 'BANK_TRANSFER';

  Future<void> _pickSales() async {
    final q = TextEditingController();
    List<dynamic> results = [];
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('فاتورة مبيعات',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration: const InputDecoration(
                            labelText: 'بحث'))),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () async {
                    results = await ref
                        .read(salesRepositoryProvider)
                        .list(
                            query: q.text,
                            status: 'APPROVED');
                    setS(() {});
                  },
                ),
              ]),
              for (final v in results)
                ListTile(
                  title: Text((v as dynamic).number as String,
                      textDirection: TextDirection.ltr),
                  onTap: () {
                    setState(() {
                      _salesId = (v as dynamic).id as String;
                      _salesNumber =
                          (v as dynamic).number as String;
                      _purchaseId = null;
                      _purchaseNumber = null;
                      if (_reference.text.trim().isEmpty) {
                        _reference.text = _salesNumber ?? '';
                      }
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPurchase() async {
    final q = TextEditingController();
    List<dynamic> results = [];
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('فاتورة مشتريات',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration: const InputDecoration(
                            labelText: 'بحث'))),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () async {
                    results = await ref
                        .read(purchasesRepositoryProvider)
                        .listInvoices(
                            query: q.text,
                            status: 'APPROVED');
                    setS(() {});
                  },
                ),
              ]),
              for (final v in results)
                ListTile(
                  title: Text((v as dynamic).number as String,
                      textDirection: TextDirection.ltr),
                  onTap: () {
                    setState(() {
                      _purchaseId = (v as dynamic).id as String;
                      _purchaseNumber =
                          (v as dynamic).number as String;
                      _purchaseTotal = null;
                      _purchasePaid = null;
                      _salesId = null;
                      _salesNumber = null;
                      if (_reference.text.trim().isEmpty) {
                        _reference.text =
                            _purchaseNumber ?? '';
                      }
                    });
                    Navigator.of(ctx).pop();
                    _loadPurchaseSummary();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل مبلغا صحيحا.')));
      return;
    }
    // مرجع تلقائي من رقم الفاتورة المرتبطة (عربون): لو فاضي املاه
    // برقم الفاتورة قبل التحقق — المستخدم مش مطالب يكتبه.
    if (_reference.text.trim().isEmpty) {
      final autoRef = _salesNumber?.isNotEmpty == true
          ? _salesNumber!
          : (_purchaseNumber?.isNotEmpty == true
              ? _purchaseNumber!
              : null);
      if (autoRef != null) {
        setState(() => _reference.text = autoRef);
      }
    }
    if (_needsReference && _reference.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'التحويل يتطلب الرقم المرجعي للعملية.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(paymentsRepositoryProvider).pay(
            salesInvoiceId: _salesId,
            purchaseInvoiceId: _purchaseId,
            methodId: _methodId,
            amount: amt,
            reference: _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty
                ? null
                : _notes.text.trim(),
          );
      ref.invalidate(paymentsPageProvider);
      if (!mounted) return;
      // جاي من حجز فاتورة: ارجع على نفس الفاتورة بعد الحفظ.
      if (_fromLinkedInvoice && _salesId != null) {
        context.pushReplacement('/sales/$_salesId');
      } else if (_fromLinkedInvoice && _purchaseId != null) {
        context.pushReplacement('/purchase-invoices/$_purchaseId');
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء تنفيذ العملية.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
            body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_salesNumber ?? 'فاتورة مبيعات معتمدة',
                textDirection: TextDirection.ltr),
            trailing: TextButton(
                onPressed: _pickSales,
                child: const Text('اختيار')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_purchaseNumber ?? 'فاتورة مشتريات معتمدة',
                textDirection: TextDirection.ltr),
            trailing: TextButton(
                onPressed: _pickPurchase,
                child: const Text('اختيار')),
          ),
          // ملخص المستحق للمورد: الإجمالي − المدفوع = المتبقي.
          // لو الفاتورة آجل: المتبقي بينزل في مستحقات المورد،
          // وممكن متدفعش حاجة خالص عادي.
          if (_purchaseId != null &&
              _purchaseTotal != null &&
              _purchasePaid != null)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('إجمالي الفاتورة')),
                      Text(
                          _purchaseTotal!.toStringAsFixed(2),
                          textDirection:
                              TextDirection.ltr),
                    ]),
                    Row(children: [
                      const Expanded(
                          child: Text('المدفوع')),
                      Text(
                          _purchasePaid!.toStringAsFixed(2),
                          textDirection:
                              TextDirection.ltr),
                    ]),
                    const Divider(),
                    Row(children: [
                      const Expanded(
                          child: Text('المتبقي للمورد',
                              style: TextStyle(
                                  fontWeight:
                                      FontWeight.bold))),
                      Text(
                          (_purchaseTotal! - _purchasePaid!)
                              .toStringAsFixed(2),
                          textDirection:
                              TextDirection.ltr,
                          style: const TextStyle(
                              fontWeight:
                                  FontWeight.bold)),
                    ]),
                  ],
                ),
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: _methodId,
            decoration:
                const InputDecoration(labelText: 'طريقة الدفع'),
            items: [
              for (final m in _methods)
                DropdownMenuItem(
                    value: m['id'] as String,
                    child: Text(
                        (m['name_ar'] ?? m['code']).toString())),
            ],
            onChanged: (v) => setState(() {
              _methodId = v;
              _methodCode = _methods
                  .where((e) => e['id'] == v)
                  .map((e) => e['code'] as String)
                  .firstOrNull;
            }),
          ),
          TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(
                      decimal: true),
              textDirection: TextDirection.ltr,
              decoration:
                  const InputDecoration(labelText: 'المبلغ *')),
          TextField(
              controller: _reference,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                  labelText:
                      'الرقم المرجعي ${_needsReference ? '*' : '(للتحويلات)'}',
                  helperText: _fromLinkedInvoice
                      ? 'يتعبى تلقائيا برقم الفاتورة — تقدر تغيره'
                      : null)),
          TextField(
              controller: _notes,
              decoration:
                  const InputDecoration(labelText: 'ملاحظات')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ الدفعة'),
          ),
        ],
      ),
    );
  }
}
