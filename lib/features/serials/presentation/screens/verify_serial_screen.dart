import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customers/data/customers_repository.dart';
import '../../../products/data/products_repository.dart';
import '../../../products/domain/product.dart';
import '../../../sales/data/sales_repository.dart';
import '../../data/serials_repository.dart';

/// كارد تحقق من السيريال (المدير + المبيعات فقط).
/// تدخل سيريال طابعة مباعة فيظهر ملفها كامل:
/// الجهاز، العميل وملفه، الفاتورة، تاريخ وسعر البيع، الربح، وواخد إيه معاها.
class VerifySerialScreen extends ConsumerStatefulWidget {
  const VerifySerialScreen({super.key});

  @override
  ConsumerState<VerifySerialScreen> createState() =>
      _VerifySerialScreenState();
}

class _VerifySerialScreenState
    extends ConsumerState<VerifySerialScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  bool _searched = false;
  SerialSale? _found;
  Map<String, dynamic>? _inStock;
  List<String> _suggestions = [];
  bool _suggesting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// اقتراحات أول بأول مع كل حرف (debounce 300ms).
  void _onTyping() {
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 300), _loadSuggestions);
  }

  Future<void> _loadSuggestions() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    setState(() => _suggesting = true);
    try {
      final list = await ref
          .read(serialsRepositoryProvider)
          .suggest(q);
      if (!mounted) return;
      // تجاهل نتيجة قديمة لو المستخدم كمل كتابة.
      if (_ctrl.text.trim() != q) return;
      setState(() => _suggestions = list);
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Future<void> _search() async {
    final s = _ctrl.text.trim();
    if (s.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اكتب السيريال الأول.')));
      return;
    }
    setState(() {
      _searching = true;
      _searched = false;
    });
    try {
      final repo = ref.read(serialsRepositoryProvider);
      final r = await repo.verify(s);
      Map<String, dynamic>? stock;
      if (r == null) {
        // مش متباع: يمكن لسه في المخزون ولا مجهول تماما؟
        stock = await repo.stockLookup(s);
      }
      if (!mounted) return;
      setState(() {
        _found = r;
        _inStock = stock;
        _searched = true;
        _suggestions = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searched = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر التحقق.')));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canVerify = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) =>
              p.can(Permissions.serialsVerify) ||
              p.isCompanyManager,
          orElse: () => false,
        );
    if (!canVerify) {
      return const ResponsiveLayout(
        mobile: EmptyState(
          icon: Icons.lock_outline,
          title: 'التحقق للمدير والمبيعات فقط.',
          subtitle:
              'المدير يقدر يسند الصلاحية من شاشة المستخدمين.',
        ),
      );
    }
    return ResponsiveLayout(
      mobile: ListView(
        padding: EdgeInsets.all(context.contentPadding),
        children: [
          AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        textDirection:
                            TextDirection.ltr,
                        decoration: InputDecoration(
                            labelText:
                                'سيريال الطابعة *',
                            suffixIcon: _suggesting
                                ? const Padding(
                                    padding:
                                        EdgeInsets.all(
                                            12),
                                    child: SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth:
                                                2)),
                                  )
                                : (_ctrl.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons
                                            .clear_outlined),
                                        onPressed: () {
                                          _ctrl
                                              .clear();
                                          setState(() {
                                            _suggestions =
                                                [];
                                            _searched =
                                                false;
                                            _found =
                                                null;
                                          });
                                        },
                                      ))),
                        onChanged: (_) {
                          setState(() {});
                          _onTyping();
                        },
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(
                        width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _searching
                          ? null
                          : _search,
                      icon: const Icon(
                          Icons.verified_outlined,
                          size: 18),
                      label:
                          const Text('تحقق'),
                    ),
                  ],
                ),
                if (_suggestions.isNotEmpty)
                  ...[
                    const SizedBox(height: 4),
                    for (final s
                        in _suggestions)
                      ListTile(
                        dense: true,
                        contentPadding:
                            EdgeInsets.zero,
                        leading: const Icon(
                            Icons
                                .barcode_reader,
                            size: 20),
                        title: Text(s,
                            textDirection:
                                TextDirection
                                    .ltr),
                        onTap: () {
                          _debounce?.cancel();
                          _ctrl.text = s;
                          setState(() =>
                              _suggestions =
                                  []);
                          _search();
                        },
                      ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_searching)
            const LoadingSkeleton(rows: 4)
          else if (_searched && _found == null && _inStock == null)
            _NotFoundCard(
              serial: _ctrl.text.trim(),
              onRegistered: _search,
            )
          else if (_searched &&
              _found == null &&
              _inStock != null)
            _InStockCard(stock: _inStock!)
          else if (_found != null)
            _Dossier(sale: _found!),
        ],
      ),
    );
  }
}

class _Dossier extends StatelessWidget {
  final SerialSale sale;
  const _Dossier({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'الجهاز'),
              _Row(
                  label: 'الصنف',
                  value: sale.productName ?? '—'),
              if ((sale.brand ?? '').isNotEmpty)
                _Row(
                    label: 'الماركة',
                    value: sale.brand!),
              if ((sale.model ?? '').isNotEmpty)
                _Row(
                    label: 'الموديل',
                    value: sale.model!),
              _Row(
                  label: 'السيريال',
                  value: sale.serial,
                  ltr: true),
              if (sale.productId != null) ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                      '/products/${sale.productId}'),
                  icon: const Icon(
                      Icons.inventory_2_outlined,
                      size: 18),
                  label: const Text('فتح الصنف'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'العميل'),
              _Row(
                  label: 'الاسم',
                  value: sale.customerName ??
                      'عميل نقدي'),
              if ((sale.customerPhone ?? '')
                  .isNotEmpty)
                _Row(
                    label: 'الهاتف',
                    value: sale.customerPhone!,
                    ltr: true),
              if (sale.customerId != null) ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                      '/customers/${sale.customerId}'),
                  icon: const Icon(
                      Icons.person_outline,
                      size: 18),
                  label:
                      const Text('عرض ملف العميل'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'البيع'),
              _Row(
                  label: 'الفاتورة',
                  value: sale.invoiceNumber ?? '—',
                  ltr: true),
              if (sale.soldAt != null)
                _Row(
                    label: 'تاريخ البيع',
                    value: AppFormat.date(
                        sale.soldAt!)),
              _Row(
                  label: 'اتباعت بكام',
                  value: AppFormat.money(
                      sale.unitPrice),
                  bold: true),
              _Row(
                  label: 'التكلفة',
                  value: AppFormat.money(
                      sale.unitCost)),
              _Row(
                  label: 'الربح',
                  value: AppFormat.money(
                      sale.profit),
                  bold: true),
              if (sale.invoiceId != null) ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                      '/sales/${sale.invoiceId}'),
                  icon: const Icon(
                      Icons.receipt_long_outlined,
                      size: 18),
                  label:
                      const Text('فتح الفاتورة'),
                ),
              ],
            ],
          ),
        ),
        if (sale.invoiceId != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InvoiceItemsCard(
              invoiceId: sale.invoiceId!),
        ],
      ],
    );
  }
}

/// السيريال مش متباع ومش في المخزون: مجهول.
/// مع زرار تسجيل بيع يدوي (مبيعات قديمة بدون فاتورة نظام).
class _NotFoundCard extends ConsumerWidget {
  final String serial;
  final VoidCallback onRegistered;
  const _NotFoundCard(
      {required this.serial, required this.onRegistered});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRegister =
        ref.watch(myPermissionsProvider).maybeWhen(
              data: (p) =>
                  p.can(Permissions.salesCreate) ||
                  p.can(Permissions.salesEdit),
              orElse: () => false,
            );
    return Column(
      children: [
        const EmptyState(
          icon: Icons.search_off_outlined,
          title: 'السيريال ده مش متسجل بيع.',
          subtitle:
              'لو اتباع قبل النظام سجله يدويا من هنا.',
        ),
        if (canRegister)
          FilledButton.tonalIcon(
            onPressed: () async {
              final ok = await showModalBottomSheet<bool>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) =>
                    _ManualSaleSheet(serial: serial),
              );
              if (ok == true) onRegistered();
            },
            icon: const Icon(Icons.add_outlined, size: 18),
            label: const Text('تسجيل بيع يدوي'),
          ),
      ],
    );
  }
}

/// السيريال موجود في المخزون: متباعش (أو متسجلش بيعه).
class _InStockCard extends ConsumerWidget {
  final Map<String, dynamic> stock;
  const _InStockCard({required this.stock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pid = stock['product_id'] as String?;
    final serial = '${stock['serial'] ?? ''}';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.blue),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text('السيريال ده في المخزون',
                        style: TextStyle(
                            fontWeight:
                                FontWeight.bold)),
                    Text(
                      '${stock['product_name'] ?? 'صنف'} • $serial',
                      textDirection:
                          TextDirection.ltr,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'متباعش — اختاره من فورم فاتورة البيع وهيتسجل للعميل عند الاعتماد.',
            style:
                TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          if (pid != null) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () =>
                  context.push('/products/$pid'),
              icon: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18),
              label: const Text('فتح الصنف'),
            ),
          ],
        ],
      ),
    );
  }
}
/// تسجيل بيع يدوي لسيريال (مبيعات قديمة بدون فاتورة نظام).
class _ManualSaleSheet extends ConsumerStatefulWidget {
  final String serial;
  const _ManualSaleSheet({required this.serial});

  @override
  ConsumerState<_ManualSaleSheet> createState() =>
      _ManualSaleSheetState();
}

class _ManualSaleSheetState
    extends ConsumerState<_ManualSaleSheet> {
  late final TextEditingController _serial;
  final _prodQuery = TextEditingController();
  final _price = TextEditingController();
  final _custQuery = TextEditingController();
  final _walkName = TextEditingController();
  final _walkPhone = TextEditingController();
  final _notes = TextEditingController();
  DateTime _soldAt = DateTime.now();
  bool _saving = false;
  String? _elecCatId;
  List<Product> _prodResults = [];
  String? _productId;
  String? _productName;
  double _productCost = 0;
  List<dynamic> _custResults = [];
  String? _customerId;
  String? _customerName;

  @override
  void initState() {
    super.initState();
    _serial = TextEditingController(text: widget.serial);
    Future.microtask(_loadElec);
  }

  Future<void> _loadElec() async {
    try {
      final cats = await ref
          .read(productsRepositoryProvider)
          .categories();
      for (final c in cats) {
        if (isElectronicsCategory(c)) {
          if (mounted) {
            setState(() => _elecCatId = c.id);
          }
          break;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _serial.dispose();
    _prodQuery.dispose();
    _price.dispose();
    _custQuery.dispose();
    _walkName.dispose();
    _walkPhone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _searchProducts() async {
    try {
      final res = await ref
          .read(productsRepositoryProvider)
          .search(
              query: '',
              categoryId: _elecCatId,
              pageSize: 8);
      if (mounted) {
        final q = _prodQuery.text.trim().toLowerCase();
        setState(() => _prodResults = q.isEmpty
            ? res
            : res
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.sku.toLowerCase().contains(q))
                .toList());
      }
    } catch (_) {}
  }

  Future<void> _searchCustomers() async {
    try {
      final res = await ref
          .read(customersRepositoryProvider)
          .search(query: _custQuery.text, pageSize: 8);
      if (mounted) setState(() => _custResults = res);
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _soldAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
    );
    if (d != null && mounted) setState(() => _soldAt = d);
  }

  Future<void> _submit() async {
    final s = _serial.text.trim();
    if (s.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتب السيريال.')));
      return;
    }
    final price = double.tryParse(_price.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      await ref.read(serialsRepositoryProvider).registerManualSale(
            serial: s,
            productId: _productId,
            productName: _productName,
            customerId: _customerId,
            customerName:
                _customerId != null ? _customerName : _walkName.text.trim().isEmpty ? null : _walkName.text.trim(),
            customerPhone:
                _customerId != null ? null : _walkPhone.text.trim().isEmpty ? null : _walkPhone.text.trim(),
            unitPrice: price,
            unitCost: _productCost,
            soldAt: _soldAt,
            notes: _notes.text.trim().isEmpty
                ? 'تسجيل يدوي'
                : _notes.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اتسجل البيع.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر التسجيل.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تسجيل بيع يدوي',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _serial,
              textDirection: TextDirection.ltr,
              decoration:
                  const InputDecoration(labelText: 'السيريال *'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('الجهاز (طابعات)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (_productName != null)
              Chip(
                label: Text(_productName!),
                onDeleted: () => setState(() {
                  _productId = null;
                  _productName = null;
                  _productCost = 0;
                }),
              )
            else ...[
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _prodQuery,
                        decoration:
                            const InputDecoration(
                                labelText: 'بحث طابعة',
                                isDense: true),
                        onSubmitted: (_) =>
                            _searchProducts())),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: _searchProducts,
                ),
              ]),
              for (final p in _prodResults)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name),
                  subtitle: Text(
                      '${p.sku} • بيع ${p.salePrice}',
                      textDirection:
                          TextDirection.ltr),
                  onTap: () => setState(() {
                    _productId = p.id;
                    _productName = p.name;
                    _productCost = p.purchasePrice;
                    _prodResults = [];
                    if (_price.text.trim().isEmpty &&
                        p.salePrice > 0) {
                      _price.text =
                          p.salePrice.toString();
                    }
                  }),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            const Text('العميل',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (_customerName != null)
              Chip(
                label: Text(_customerName!),
                onDeleted: () => setState(() {
                  _customerId = null;
                  _customerName = null;
                }),
              )
            else ...[
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _custQuery,
                        decoration:
                            const InputDecoration(
                                labelText:
                                    'بحث عميل مسجل',
                                isDense: true),
                        onSubmitted: (_) =>
                            _searchCustomers())),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: _searchCustomers,
                ),
              ]),
              for (final c in _custResults)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text((c as dynamic).name as String),
                  onTap: () => setState(() {
                    _customerId = (c as dynamic).id as String;
                    _customerName =
                        (c as dynamic).name as String;
                    _custResults = [];
                  }),
                ),
              TextField(
                controller: _walkName,
                decoration: const InputDecoration(
                    labelText:
                        'أو اسم عميل نقدي (بدون ملف)',
                    isDense: true),
              ),
              TextField(
                controller: _walkPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'هاتف العميل',
                    isDense: true),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  textDirection: TextDirection.ltr,
                  decoration:
                      const InputDecoration(
                          labelText:
                              'اتباعت بكام *',
                          isDense: true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(
                      Icons.date_range_outlined,
                      size: 18),
                  label: Text(
                      AppFormat.date(_soldAt)),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  isDense: true),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Text('تسجيل البيع'),
            ),
          ],
        ),
      ),
    );
  }
}

/// واخد مني إيه معاها: باقي بنود نفس الفاتورة.
class _InvoiceItemsCard extends ConsumerWidget {
  final String invoiceId;
  const _InvoiceItemsCard({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref
          .read(salesRepositoryProvider)
          .itemsOf(invoiceId),
      builder: (context, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) {
          return const SizedBox.shrink();
        }
        return AppCard(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                  title: 'واخد إيه معاها (نفس الفاتورة)'),
              for (final it in rows)
                ListTile(
                  dense: true,
                  contentPadding:
                      EdgeInsets.zero,
                  title: Text(
                      '${it.isCustom ? '🔧 ' : ''}${it.itemName}'),
                  subtitle: Text(
                      '${it.quantity} × ${AppFormat.money(it.unitPrice)}'),
                  trailing: Text(AppFormat.money(
                      it.total)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool ltr;
  const _Row(
      {required this.label,
      required this.value,
      this.bold = false,
      this.ltr = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: bold
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.bodyMedium)),
          Flexible(
            child: Text(
              value,
              textDirection:
                  ltr ? TextDirection.ltr : null,
              style: bold
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
