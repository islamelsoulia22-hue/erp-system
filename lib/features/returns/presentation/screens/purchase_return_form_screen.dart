import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/errors/failures.dart';
import '../../../purchases/data/purchases_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../data/returns_repository.dart';

class PurchaseReturnFormScreen extends ConsumerStatefulWidget {
  final String? invoiceId;
  const PurchaseReturnFormScreen({super.key, this.invoiceId});
  @override
  ConsumerState<PurchaseReturnFormScreen> createState() =>
      _PurchaseReturnFormScreenState();
}

class _PurchaseReturnFormScreenState
    extends ConsumerState<PurchaseReturnFormScreen> {
  final _reason = TextEditingController();
  String? _invoiceId;
  String? _invoiceNumber;
  DateTime? _invoiceDate;
  String? _warehouseId;
  List<dynamic> _warehouses = [];
  final _lines = <Map<String, dynamic>>[];
  bool _saving = false;
  bool _loadingLines = false;

  @override
  void initState() {
    super.initState();
    _invoiceId = widget.invoiceId;
    Future.microtask(() async {
      final wh = await ref
          .read(warehousesRepositoryProvider)
          .list(onlyActive: true);
      if (!mounted) return;
      setState(() {
        _warehouses = wh;
        if (wh.isNotEmpty) {
          // ignore: avoid_dynamic_calls
          _warehouseId = (wh.first as dynamic).id as String;
        }
      });
      if (_invoiceId != null) await _loadInvoice(_invoiceId!);
    });
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// يحمّل الفاتورة: مخزنها + بنودها بالمتبقي القابل للإرجاع فقط.
  Future<void> _loadInvoice(String id) async {
    setState(() => _loadingLines = true);
    try {
      final inv = await ref
          .read(purchasesRepositoryProvider)
          .getInvoice(id);
      final rows = await ref
          .read(returnsRepositoryProvider)
          .purchaseReturnable(id);
      if (!mounted) return;
      setState(() {
        _invoiceId = id;
        _invoiceNumber = inv?.number;
        _invoiceDate = inv?.createdAt;
        if (inv?.warehouseId != null) {
          _warehouseId = inv!.warehouseId;
        }
        _lines.clear();
        for (final r in rows) {
          final rem = _num(r['remaining_qty']);
          if (rem <= 0) continue;
          _lines.add({
            'product_id': r['product_id'],
            'name': r['item_name'],
            'sku': r['sku'],
            'qty': rem,
            'price': _num(r['unit_cost']),
            'tax': _num(r['tax_rate']),
            'remaining': rem,
            'invoiced': _num(r['invoiced_qty']),
          });
        }
      });
      if (mounted && _lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'لا يوجد متبقي قابل للإرجاع في هذه الفاتورة.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر تحميل بنود الفاتورة.')));
    } finally {
      if (mounted) setState(() => _loadingLines = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickInvoice() async {
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
              const Text('فاتورة مشتريات معتمدة',
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
                  onTap: () async {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    await _loadInvoice(
                        (v as dynamic).id as String);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_invoiceId == null ||
        _warehouseId == null ||
        _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اختر الفاتورة والمخزن والأصناف.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(returnsRepositoryProvider)
          .createPurchaseReturn(
            invoiceId: _invoiceId!,
            warehouseId: _warehouseId!,
            reason: _reason.text,
            items: [
              for (final l in _lines)
                {
                  ...l,
                  'qty': ((l['qty'] as double?) ?? 0)
                      .clamp(0, (l['remaining'] as double?) ?? 1e9),
                },
            ],
          );
      ref.invalidate(purchaseReturnsPageProvider);
      if (mounted) {
        context.pushReplacement('/purchase-returns/$id');
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

  /// حفظ مباشر (نسخة الجهاز فقط): إنشاء + إتمام فوري
  /// (خصم المخزون) بدون موافقات.
  Future<void> _saveDirect() async {
    if (_invoiceId == null ||
        _warehouseId == null ||
        _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اختر الفاتورة والمخزن والأصناف.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(returnsRepositoryProvider)
          .createAndCompletePurchaseReturn(
            invoiceId: _invoiceId!,
            warehouseId: _warehouseId!,
            reason: _reason.text,
            items: [
              for (final l in _lines)
                {
                  ...l,
                  'qty': ((l['qty'] as double?) ?? 0)
                      .clamp(0, (l['remaining'] as double?) ?? 1e9),
                },
            ],
          );
      ref.invalidate(purchaseReturnsPageProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('تم حفظ المرتجع وخصم المخزون.')));
        context.pushReplacement('/purchase-returns/$id');
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
    final policy = ref.watch(returnPolicyProvider);
    final expired = policy.maybeWhen(
      data: (p) {
        final h = p.purchaseWindowHours;
        if (h == null || _invoiceDate == null) return false;
        return DateTime.now().isAfter(
            _invoiceDate!.add(Duration(minutes: (h * 60).round())));
      },
      orElse: () => false,
    );
    return Scaffold(
            body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_invoiceNumber ?? 'فاتورة معتمدة *',
                textDirection: TextDirection.ltr),
            trailing: TextButton(
                onPressed: _pickInvoice,
                child: const Text('اختيار')),
          ),
          policy.maybeWhen(
            data: (p) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: expired
                    ? Colors.red.shade50
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                expired
                    ? 'انتهت مدة المرتجع لهذه الفاتورة (${ReturnPolicy.describe(p.purchaseWindowHours)}) — لا يمكن الإتمام.'
                    : 'المسموح للمرتجع: ${ReturnPolicy.describe(p.purchaseWindowHours)}.',
                style: TextStyle(
                  fontSize: 12,
                  color: expired
                      ? Colors.red.shade900
                      : Colors.blue.shade900,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          DropdownButtonFormField<String>(
            initialValue: _warehouseId,
            decoration:
                const InputDecoration(labelText: 'مخزن الخصم *'),
            items: [
              for (final w in _warehouses)
                DropdownMenuItem(
                    // ignore: avoid_dynamic_calls
                    value: (w as dynamic).id as String,
                    // ignore: avoid_dynamic_calls
                    child: Text((w as dynamic).name as String)),
            ],
            onChanged: (v) =>
                setState(() => _warehouseId = v),
          ),
          TextField(
              controller: _reason,
              decoration:
                  const InputDecoration(labelText: 'سبب المرتجع')),
          const Divider(height: 24),
          if (_loadingLines)
            const Center(child: CircularProgressIndicator()),
          for (int i = 0; i < _lines.length; i++)
            Card(
              child: ListTile(
                title:
                    Text(_lines[i]['name'] as String),
                subtitle: Text(
                    'المرتجع: ${_lines[i]['qty']} / المتاح: ${_lines[i]['remaining']} من ${_lines[i]['invoiced']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon:
                            const Icon(Icons.remove_outlined),
                        onPressed: () => setState(() {
                              _lines[i]['qty'] =
                                  ((_lines[i]['qty']
                                              as double) -
                                          1)
                                      .clamp(0, 1e9);
                              if ((_lines[i]['qty']
                                      as double) <=
                                  0) {
                                _lines.removeAt(i);
                              }
                            })),
                    IconButton(
                        icon: const Icon(Icons.add_outlined),
                        onPressed: () => setState(() {
                              final rem =
                                  (_lines[i]['remaining']
                                          as double?) ??
                                      1e9;
                              if ((_lines[i]['qty']
                                      as double) <
                                  rem) {
                                _lines[i]['qty'] =
                                    (_lines[i]['qty']
                                            as double) +
                                        1;
                              } else {
                                ScaffoldMessenger.of(
                                        context)
                                    .showSnackBar(const SnackBar(
                                        content: Text(
                                            'وصلت للمتاح للإرجاع من هذا الصنف.')));
                              }
                            })),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (resolveBackendMode() == BackendMode.local)
            FilledButton.icon(
              onPressed: (_saving || expired) ? null : _saveDirect,
              icon: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline,
                      size: 20),
              label:
                  const Text('حفظ المرتجع (خصم المخزون فورا)'),
            )
          else
            FilledButton(
              onPressed: (_saving || expired) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ كمسودة'),
            ),
        ],
      ),
    );
  }
}
