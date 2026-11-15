import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_pagination.dart';
import 'local_partners.dart' show LocalPartner;
import 'local_partners_screens.dart' show pickLocalPartner;
import 'local_payments.dart';
import 'local_products.dart' show LocalDataFailure;
import 'local_ui.dart';

/// قايمة المدفوعات اللوكال + تسجيل دفعة عامة.
class LocalPaymentsScreen extends ConsumerStatefulWidget {
  const LocalPaymentsScreen({super.key});

  @override
  ConsumerState<LocalPaymentsScreen> createState() =>
      _LocalPaymentsScreenState();
}

class _LocalPaymentsScreenState extends ConsumerState<LocalPaymentsScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(localPaymentsPageProvider(_page));
    return Scaffold(
      appBar: AppBar(title: const Text('المدفوعات — نسخة الجهاز')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const LocalPaymentFormScreen()),
          );
          if (ok == true) {
            ref.invalidate(localPaymentsPageProvider);
          }
        },
        child: const Icon(Icons.add_outlined),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('تعذر التحميل.')),
        data: (paged) {
          if (paged.items.isEmpty) {
            return const Center(child: Text('لا توجد مدفوعات.'));
          }
          return ListView.separated(
            itemCount: paged.items.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i >= paged.items.length) {
                return AppPagination(
                  page: _page,
                  total: paged.total,
                  pageSize: LocalPaymentsRepository.pageSize,
                  onGo: (p) => setState(() => _page = p),
                );
              }
              final p = paged.items[i];
              final isIn = p.salesInvoiceId != null;
              return ListTile(
                leading: Icon(
                  isIn
                      ? Icons.arrow_downward_outlined
                      : p.purchaseInvoiceId != null
                      ? Icons.arrow_upward_outlined
                      : Icons.swap_horiz_outlined,
                  color: isIn
                      ? Colors.green
                      : p.purchaseInvoiceId != null
                      ? Colors.orange
                      : Colors.blue,
                ),
                title: Text(
                  p.invoiceNumber ?? 'دفعة عامة',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(
                  '${p.methodCode ?? ''} • ${p.date.length >= 10 ? p.date.substring(0, 10) : p.date}',
                ),
                trailing: Text(
                  '${p.amount}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// تسجيل دفعة عامة (تحصيل من عميل / سداد لمورد).
class LocalPaymentFormScreen extends ConsumerStatefulWidget {
  const LocalPaymentFormScreen({super.key});

  @override
  ConsumerState<LocalPaymentFormScreen> createState() =>
      _LocalPaymentFormScreenState();
}

class _LocalPaymentFormScreenState
    extends ConsumerState<LocalPaymentFormScreen> {
  bool _toSupplier = true;
  LocalPartner? _partner;
  String? _methodId;
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_partner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _toSupplier ? 'اختار المورد أولا.' : 'اختار العميل أولا.',
          ),
        ),
      );
      return;
    }
    final amt = parseNum(_amount.text);
    if (amt <= 0 || _methodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ادخل المبلغ واختار طريقة الدفع.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(localPaymentsRepositoryProvider)
          .record(
            customerId: _toSupplier ? null : _partner!.id,
            supplierId: _toSupplier ? _partner!.id : null,
            methodId: _methodId!,
            amount: amt,
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
    final methods = ref.watch(localPaymentMethodsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('دفعة جديدة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('تحصيل من عميل')),
              ButtonSegment(value: true, label: Text('سداد لمورد')),
            ],
            selected: {_toSupplier},
            onSelectionChanged: (s) => setState(() {
              _toSupplier = s.first;
              _partner = null;
            }),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _toSupplier ? Icons.handshake_outlined : Icons.person_outlined,
            ),
            title: Text(
              _partner?.name ??
                  (_toSupplier ? 'اختار المورد *' : 'اختار العميل *'),
            ),
            trailing: TextButton(
              child: const Text('اختيار'),
              onPressed: () async {
                final p = await pickLocalPartner(
                  context,
                  ref,
                  supplier: _toSupplier,
                );
                if (p != null) {
                  setState(() => _partner = p);
                }
              },
            ),
          ),
          methods.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const Text('تعذر تحميل طرق الدفع.'),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _methodId,
              decoration: const InputDecoration(labelText: 'طريقة الدفع *'),
              items: [
                for (final m in list)
                  DropdownMenuItem(value: m.id, child: Text(m.nameAr)),
              ],
              onChanged: (v) => setState(() => _methodId = v),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'المبلغ *',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ الدفعة'),
          ),
        ],
      ),
    );
  }
}
