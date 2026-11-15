import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_pagination.dart';
import 'local_partners.dart' show LocalPartner;
import 'local_partners_screens.dart' show pickLocalPartner;
import 'local_payments.dart';
import 'local_products.dart' show LocalDataFailure;
import 'local_products_screens.dart' show pickLocalProduct;
import 'local_sales.dart';
import 'local_ui.dart';
import 'local_warehouses.dart';

class _SL {
  String? productId;
  String name;
  double qty;
  double price;
  _SL({
    this.productId,
    required this.name,
    required this.qty,
    required this.price,
  });
}

/// قايمة فواتير المبيعات اللوكال.
class LocalSalesScreen extends ConsumerStatefulWidget {
  const LocalSalesScreen({super.key});

  @override
  ConsumerState<LocalSalesScreen> createState() => _LocalSalesScreenState();
}

class _LocalSalesScreenState extends ConsumerState<LocalSalesScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(
      localSalesPageProvider((query: _query, page: _page)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('المبيعات — نسخة الجهاز')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const LocalSalesFormScreen()),
          );
          if (ok == true) {
            ref.invalidate(localSalesPageProvider);
          }
        },
        child: const Icon(Icons.add_outlined),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => setState(() {
                      _query = _search.text.trim();
                      _page = 0;
                    }),
                    decoration: const InputDecoration(
                      labelText: 'بحث برقم الفاتورة / العميل',
                      prefixIcon: Icon(Icons.search_outlined),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => setState(() {
                    _query = _search.text.trim();
                    _page = 0;
                  }),
                  child: const Text('بحث'),
                ),
              ],
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('تعذر التحميل.')),
              data: (paged) {
                if (paged.items.isEmpty) {
                  return const Center(child: Text('لا توجد فواتير مبيعات.'));
                }
                return ListView.separated(
                  itemCount: paged.items.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i >= paged.items.length) {
                      return AppPagination(
                        page: _page,
                        total: paged.total,
                        pageSize: LocalSalesRepository.pageSize,
                        onGo: (p) => setState(() => _page = p),
                      );
                    }
                    final v = paged.items[i];
                    return ListTile(
                      title: Text(v.number, textDirection: TextDirection.ltr),
                      subtitle: Text(
                        '${v.customerName} • ${localInvoiceStatusAr(v.status)} • ${localInvoiceStatusAr(v.paymentStatus)}',
                      ),
                      trailing: Text(
                        '${v.grandTotal}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                LocalSalesDetailScreen(invoiceId: v.id),
                          ),
                        );
                        ref.invalidate(localSalesPageProvider);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// فورم فاتورة مبيعات لوكال (مسودة).
class LocalSalesFormScreen extends ConsumerStatefulWidget {
  const LocalSalesFormScreen({super.key});

  @override
  ConsumerState<LocalSalesFormScreen> createState() =>
      _LocalSalesFormScreenState();
}

class _LocalSalesFormScreenState extends ConsumerState<LocalSalesFormScreen> {
  LocalPartner? _customer;
  String? _warehouseId;
  String? _methodId;
  final _lines = <_SL>[];
  bool _saving = false;

  double get _sub => _lines.fold(0, (s, l) => s + l.qty * l.price);
  double get _total => _sub;

  Future<void> _addItem() async {
    final p = await pickLocalProduct(context, ref);
    if (p == null || !mounted) return;
    final qty = TextEditingController(text: '1');
    final price = TextEditingController(text: '${p.salePrice}');
    final res = await showModalBottomSheet<({double qty, double price})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'الكمية *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'سعر البيع *'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final q = parseNum(qty.text);
                final pr = parseNum(price.text);
                if (q <= 0 || pr < 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('ادخل كمية وسعرا صحيحين.')),
                  );
                  return;
                }
                Navigator.of(ctx).pop((qty: q, price: pr));
              },
              child: const Text('تم'),
            ),
          ],
        ),
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      final i = _lines.indexWhere(
        (l) => l.productId != null && l.productId == p.id,
      );
      if (i >= 0) {
        _lines[i].qty += res.qty;
        _lines[i].price = res.price;
      } else {
        _lines.add(
          _SL(productId: p.id, name: p.name, qty: res.qty, price: res.price),
        );
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_warehouseId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اختار المخزن أولا.')));
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أضف صنفا واحدا.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(localSalesRepositoryProvider)
          .create(
            customerId: _customer?.id,
            warehouseId: _warehouseId!,
            paymentMethodId: _methodId,
            lines: [
              for (final l in _lines)
                LocalSalesLineInput(
                  productId: l.productId,
                  name: l.name,
                  qty: l.qty,
                  unitPrice: l.price,
                ),
            ],
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on LocalDataFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.messageAr)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(localWarehousesProvider);
    final methods = ref.watch(localPaymentMethodsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('فاتورة مبيعات جديدة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outlined),
            title: Text(_customer?.name ?? 'عميل نقدي (اختياري)'),
            trailing: TextButton(
              child: const Text('اختيار'),
              onPressed: () async {
                final c = await pickLocalPartner(context, ref, supplier: false);
                if (c != null) {
                  setState(() => _customer = c);
                }
              },
            ),
          ),
          warehouses.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const Text('تعذر تحميل المخازن.'),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _warehouseId,
              decoration: const InputDecoration(labelText: 'المخزن *'),
              items: [
                for (final w in list)
                  DropdownMenuItem(value: w.id, child: Text(w.name)),
              ],
              onChanged: (v) => setState(() => _warehouseId = v),
            ),
          ),
          const SizedBox(height: 8),
          methods.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _methodId,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: [
                for (final m in list)
                  DropdownMenuItem(value: m.id, child: Text(m.nameAr)),
              ],
              onChanged: (v) => setState(() => _methodId = v),
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Text(
                'الأصناف',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_outlined),
                label: const Text('إضافة صنف'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _lines.length; i++)
            Card(
              child: ListTile(
                dense: true,
                title: Text(_lines[i].name),
                subtitle: Text(
                  '${_lines[i].qty} × ${_lines[i].price}',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _lines.removeAt(i)),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'الإجمالي',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '$_total',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ كمسودة'),
          ),
        ],
      ),
    );
  }
}

/// تفاصيل فاتورة مبيعات لوكال.
class LocalSalesDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const LocalSalesDetailScreen({super.key, required this.invoiceId});

  void _refresh(WidgetRef ref) {
    ref.invalidate(localSalesDetailProvider(invoiceId));
    ref.invalidate(localSalesItemsProvider(invoiceId));
    ref.invalidate(
      localInvoiceOutstandingProvider((sales: true, id: invoiceId)),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(localSalesRepositoryProvider).approve(invoiceId);
      _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الاعتماد وخصم المخزون.')),
        );
      }
    } on LocalDataFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.messageAr)));
      }
    }
  }

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    double outstanding,
  ) async {
    if (outstanding <= 0) return;
    final amount = TextEditingController(text: '$outstanding');
    String? methodId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل تحصيل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'المبلغ *',
                helperText: 'المتبقي: $outstanding',
              ),
            ),
            const SizedBox(height: 8),
            Consumer(
              builder: (ctx2, ref2, _) {
                final methods = ref2.watch(localPaymentMethodsProvider);
                return methods.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) {
                    methodId ??= list.isEmpty ? null : list.first.id;
                    return DropdownButtonFormField<String>(
                      initialValue: methodId,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                      ),
                      items: [
                        for (final m in list)
                          DropdownMenuItem(value: m.id, child: Text(m.nameAr)),
                      ],
                      onChanged: (v) => methodId = v,
                    );
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    final amt = parseNum(amount.text);
    if (ok != true || amt <= 0 || methodId == null) {
      return;
    }
    try {
      await ref
          .read(localPaymentsRepositoryProvider)
          .record(salesInvoiceId: invoiceId, methodId: methodId!, amount: amt);
      _refresh(ref);
    } on LocalDataFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.messageAr)));
      }
    }
  }

  Future<void> _return(
    BuildContext context,
    WidgetRef ref,
    List<LocalSalesItem> items,
  ) async {
    final qtys = {for (final it in items) it.id: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مرتجع مبيعات'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final it in items)
                  TextField(
                    controller: qtys[it.id],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: '${it.name} (بالفاتورة ${it.qty})',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حفظ المرتجع'),
          ),
        ],
      ),
    );
    final lines = <LocalSalesLineInput>[];
    for (final it in items) {
      final q = parseNum(qtys[it.id]!.text);
      qtys[it.id]!.dispose();
      if (q > 0) {
        lines.add(
          LocalSalesLineInput(
            productId: it.productId,
            name: it.name,
            qty: q,
            unitPrice: it.unitPrice,
            taxRate: it.taxRate,
          ),
        );
      }
    }
    if (ok != true || lines.isEmpty) return;
    try {
      await ref
          .read(localSalesRepositoryProvider)
          .recordReturn(invoiceId: invoiceId, lines: lines);
      _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ المرتجع ورجوع المخزون.')),
        );
      }
    } on LocalDataFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.messageAr)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(localSalesDetailProvider(invoiceId));
    final items = ref.watch(localSalesItemsProvider(invoiceId));
    final outstanding = ref.watch(
      localInvoiceOutstandingProvider((sales: true, id: invoiceId)),
    );
    return detail.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('تعذر التحميل.')),
      ),
      data: (v) {
        if (v == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('الفاتورة غير موجودة.')),
          );
        }
        final out = outstanding.maybeWhen(data: (o) => o, orElse: () => 0.0);
        return Scaffold(
          appBar: AppBar(title: Text(v.number)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${v.customerName} • ${localInvoiceStatusAr(v.status)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                v.paymentStatus == 'PAID'
                    ? 'مدفوعة بالكامل'
                    : v.paymentStatus == 'PARTIAL'
                    ? 'مدفوعة جزئيا — المتبقي $out'
                    : 'غير مدفوعة (آجل) — المستحق $out',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: paymentStatusColor(v.paymentStatus),
                ),
              ),
              Text(
                'الإجمالي: ${v.grandTotal} • ${v.warehouseName} • ${v.paymentMethodName}',
              ),
              const Divider(height: 24),
              const Text(
                'الأصناف',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              items.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const Text('تعذر تحميل الأصناف.'),
                data: (rows) => Column(
                  children: [
                    for (final it in rows)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(it.name),
                        subtitle: Text(
                          '${it.qty} × ${it.unitPrice}',
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.left,
                        ),
                        trailing: Text(
                          '${it.total}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (v.status == 'DRAFT')
                    FilledButton.icon(
                      onPressed: () => _approve(context, ref),
                      icon: const Icon(Icons.check_outlined),
                      label: const Text('اعتماد'),
                    ),
                  if (v.status == 'APPROVED' && v.paymentStatus != 'PAID')
                    OutlinedButton.icon(
                      onPressed: () => _pay(context, ref, out),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('تسجيل تحصيل'),
                    ),
                  if (v.status == 'APPROVED')
                    OutlinedButton.icon(
                      onPressed: () => items.maybeWhen(
                        data: (rows) => _return(context, ref, rows),
                        orElse: () {},
                      ),
                      icon: const Icon(Icons.undo_outlined),
                      label: const Text('مرتجع مبيعات'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
