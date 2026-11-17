import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/pdf/barcode_pdf.dart';
import '../../../../core/printing/usb_receipt_printer.dart';
import '../../../../core/printing/xprinter_service.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/yad_widgets.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../sales/presentation/widgets/barcode_scan_sheet.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';

/// قسم باركود الأصناف:
/// - بحث باسم الصنف (أو SKU) لطباعة الباركود بتاعه.
/// - بحث/إدخال باركود يدوي أو بالسكانر.
/// - كل صنف يطبع ملصق: اسم الصنف + صورة الباركود + الرقم.
/// - لو صنف بدون باركود: إضافة سريعة (يدوي/سكانر) من نفس القسم.
class ProductBarcodesScreen extends ConsumerStatefulWidget {
  const ProductBarcodesScreen({super.key});

  @override
  ConsumerState<ProductBarcodesScreen> createState() =>
      _ProductBarcodesScreenState();
}

class _ProductBarcodesScreenState
    extends ConsumerState<ProductBarcodesScreen> {
  final _search = TextEditingController();
  final _barcodeInput = TextEditingController();
  final _scroll = ScrollController();
  int _page = 0;
  String _query = '';
  String _barcodeQuery = '';
  final Set<String> _selected = {};
  int _copies = 1;
  bool _printing = false;

  @override
  void dispose() {
    _search.dispose();
    _barcodeInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _applySearch() {
    setState(() {
      _query = _search.text.trim();
      _barcodeQuery = _barcodeInput.text.trim();
      _page = 0;
      _selected.clear();
    });
  }

  void _go(int p) {
    setState(() => _page = p);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<({List<Product> items, int total})> _load() {
    final repo = ref.read(productsRepositoryProvider);
    // باركود دقيق أولا (يدوي أو سكانر).
    if (_barcodeQuery.isNotEmpty) {
      return repo.findByBarcode(_barcodeQuery).then((p) {
        if (p == null) return (items: const <Product>[], total: 0);
        return (items: <Product>[p], total: 1);
      });
    }
    return repo.searchPaged(
      query: _query,
      page: _page,
      onlyActive: true,
    );
  }

  Future<void> _scanIntoBarcodeField() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BarcodeScanSheet(),
    );
    if (code == null || code.isEmpty || !mounted) return;
    _barcodeInput.text = code;
    _applySearch();
  }

  Future<void> _scanAndAdd(String productId) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BarcodeScanSheet(),
    );
    if (code == null || code.isEmpty || !mounted) return;
    await _saveBarcode(productId, code);
  }

  Future<void> _saveBarcode(
    String productId,
    String code,
  ) async {
    try {
      await ref.read(productsRepositoryProvider).addBarcode(
            productId: productId,
            barcode: code.trim(),
            isPrimary: true,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الباركود.')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is AppFailure
                ? e.messageAr
                : 'تعذر حفظ الباركود — ربما الرقم مكرر.',
          ),
        ),
      );
    }
  }

  void _addBarcodeSheet(Product p) {
    final ctrl = TextEditingController(
      text: p.primaryBarcode ?? '',
    );
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom:
              MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Text(
              'باركود: ${p.name}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رقم الباركود (يدوي أو مسح)',
                prefixIcon: const Icon(
                  Icons.barcode_reader,
                ),
                suffixIcon: IconButton(
                  tooltip: 'مسح بالكاميرا',
                  icon: const Icon(
                    Icons.qr_code_scanner_outlined,
                  ),
                  onPressed: () async {
                    final code =
                        await showModalBottomSheet<
                            String>(
                      context: ctx,
                      showDragHandle: true,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) =>
                          const BarcodeScanSheet(),
                    );
                    if (code != null &&
                        code.isNotEmpty) {
                      ctrl.text = code;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(ctx).pop();
                await _saveBarcode(
                  p.id,
                  ctrl.text.trim(),
                );
              },
              child: const Text('حفظ الباركود'),
            ),
          ],
        ),
      ),
    );
  }

  List<BarcodeLabelData> _labelsOf(
    List<Product> products,
  ) {
    return [
      for (final p in products)
        if ((p.primaryBarcode ?? '').trim().isNotEmpty)
          BarcodeLabelData(
            productId: p.id,
            productName: p.name,
            barcode: p.primaryBarcode!.trim(),
          ),
    ];
  }

  /// معاينة قبل الطباعة: يعرض شكل الملصق
  /// (الاسم + الباركود + الرقم) زي ما هيطبع بالظبط.
  Future<void> _previewItems(
    List<Product> products, {
    int? copies,
  }) async {
    final labels = _labelsOf(products);
    if (labels.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا توجد باركودات للمعاينة — أضف باركود أولا.',
          ),
        ),
      );
      return;
    }
    final n = await _askCopies(copies ?? _copies);
    if (n == null || !mounted) return;
    setState(() => _copies = n);
    await showBarcodeLabelsPreview(
      context,
      labels,
      copies: n,
      // PDF شغال على كل المنصات + ريسيت مباشر على لينكس.
      showPdfButton: true,
      onReceiptPrint: supportsUsbReceiptPrint
          ? () => _printReceiptUsb(
                products,
                copies: n,
              )
          : null,
    );
  }

  /// مثال تجريبي سريع (سجاير — 62211628) يعرض شكل
  /// الملصق من غير ما تحتاج صنف حقيقي في القاعدة.
  Future<void> _previewDemo() async {
    const demo = BarcodeLabelData(
      productId: 'demo',
      productName: 'سجاير',
      barcode: '62211628',
    );
    final n = await _askCopies(_copies);
    if (n == null || !mounted) return;
    setState(() => _copies = n);
    await showBarcodeLabelsPreview(
      context,
      const [demo],
      copies: n,
    );
  }

  /// حوار XPrinter الموحد — شغال من كل الأنظمة
  /// (شبكة مباشرة + PDF بمقاس الملصق).
  Future<void> _printXPrinter(List<Product> products) async {
    final labels = _labelsOf(products);
    if (labels.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا توجد باركودات للطباعة — أضف باركود أولا.',
          ),
        ),
      );
      return;
    }
    await showXPrinterSheet(
      context,
      labels,
      initialCopies: _copies,
    );
  }

  /// طباعة مباشرة على طابعة الريسيت USB (لينكس) —
  /// من غير حوار الطباعة ومن غير CUPS.
  Future<void> _printReceiptUsb(
    List<Product> products, {
    int? copies,
  }) async {
    final labels = _labelsOf(products);
    if (labels.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا توجد باركودات للطباعة — أضف باركود أولا.',
          ),
        ),
      );
      return;
    }
    final n = copies ?? await _askCopies(_copies);
    if (n == null || !mounted) return;
    setState(() {
      _printing = true;
      _copies = n;
    });
    try {
      await printLabelsUsbReceipt(
        context,
        labels,
        copies: n,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اتطبعت على الريسيت.'),
        ),
      );
    } on UsbPrinterException catch (e) {
      if (!mounted) return;
      await showUsbPrinterError(context, e);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر الطباعة: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _printing = false);
      }
    }
  }

  /// طباعة PDF عبر حوار الطباعة — شغالة على كل المنصات
  /// (موبايل/لينكس/ويندوز) عكس الريسيت المباشر (لينكس فقط).
  Future<void> _printPdf(
    List<Product> products, {
    int? copies,
  }) async {
    final labels = _labelsOf(products);
    if (labels.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا توجد باركودات للطباعة — أضف باركود أولا.',
          ),
        ),
      );
      return;
    }
    final n = copies ?? await _askCopies(_copies);
    if (n == null || !mounted) return;
    setState(() {
      _printing = true;
      _copies = n;
    });
    try {
      await printBarcodeLabels(
        context,
        labels,
        copies: n,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر الطباعة: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _printing = false);
      }
    }
  }

  /// حوار عدد النسخ لكل ملصق (مفتوح بدون حد أقصى).
  Future<int?> _askCopies(int initial) async {
    final ctrl = TextEditingController(
      text: '$initial',
    );
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('عدد النسخ'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'نسخة لكل صنف (أي عدد)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(
                    ctrl.text.trim(),
                  ) ??
                  0;
              if (v < 1) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(
                  const SnackBar(
                    content: Text(
                      'ادخل رقما أكبر من صفر.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('طباعة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const PermissionSet({}),
        );
    final canEdit = perms.can(Permissions.productsEdit) ||
        perms.can(Permissions.productsCreate);

    return ResponsiveLayout(
      mobile: ListView(
        controller: _scroll,
        padding:
            EdgeInsets.all(context.contentPadding),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _search,
                  textInputAction:
                      TextInputAction.search,
                  onSubmitted: (_) => _applySearch(),
                  decoration: InputDecoration(
                    labelText:
                        'ابحث باسم الصنف أو SKU',
                    prefixIcon: const Icon(
                      Icons.search_outlined,
                    ),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.clear_outlined,
                            ),
                            onPressed: () {
                              _search.clear();
                              _applySearch();
                            },
                          ),
                  ),
                  onChanged: (_) =>
                      setState(() {}),
                ),
                const SizedBox(
                  height: AppSpacing.sm,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _barcodeInput,
                        textDirection:
                            TextDirection.ltr,
                        textInputAction:
                            TextInputAction.search,
                        onSubmitted: (_) =>
                            _applySearch(),
                        decoration:
                            const InputDecoration(
                          labelText:
                              'باركود (يدوي)',
                          prefixIcon: Icon(
                            Icons
                                .barcode_reader,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: AppSpacing.sm,
                    ),
                    IconButton.filledTonal(
                      tooltip:
                          'مسح باركود بالكاميرا',
                      icon: const Icon(
                        Icons
                            .qr_code_scanner_outlined,
                      ),
                      onPressed:
                          _scanIntoBarcodeField,
                    ),
                  ],
                ),
                const SizedBox(
                  height: AppSpacing.sm,
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _applySearch,
                        icon: const Icon(
                          Icons.search_outlined,
                          size: 18,
                        ),
                        label:
                            const Text('بحث'),
                      ),
                    ),
                    const SizedBox(
                      width: AppSpacing.sm,
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _search.clear();
                        _barcodeInput.clear();
                        _applySearch();
                      },
                      icon: const Icon(
                        Icons.clear_all_outlined,
                        size: 18,
                      ),
                      label:
                          const Text('مسح'),
                    ),
                  ],
                ),
                const SizedBox(
                  height: AppSpacing.sm,
                ),
                OutlinedButton.icon(
                  onPressed: _previewDemo,
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'معاينة مثال: سجاير — 62211628',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FutureBuilder<
              ({
                List<Product> items,
                int total
              })>(
            future: _load(),
            builder: (ctx, snap) {
              if (snap.connectionState ==
                  ConnectionState.waiting) {
                return const LoadingSkeleton(
                  rows: 4,
                );
              }
              if (snap.hasError) {
                final e = snap.error;
                return ErrorState(
                  message: e is AppFailure
                      ? e.messageAr
                      : 'تعذر تحميل الأصناف.',
                  onRetry: () =>
                      setState(() {}),
                );
              }
              final data = snap.data ??
                  (items: const <Product>[],
                      total: 0);
              if (data.items.isEmpty) {
                return const EmptyState(
                  icon: Icons
                      .barcode_reader,
                  title:
                      'لا توجد أصناف مطابقة',
                  subtitle:
                      'ابحث بالاسم أو ادخل/امسح الباركود',
                );
              }
              final printable = data.items
                  .where(
                    (p) =>
                        (p.primaryBarcode ?? '')
                            .trim()
                            .isNotEmpty,
                  )
                  .toList();
              final selectedPrintable = data.items
                  .where(
                    (p) =>
                        _selected.contains(p.id) &&
                        (p.primaryBarcode ?? '')
                            .trim()
                            .isNotEmpty,
                  )
                  .toList();
              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    padding:
                        const EdgeInsets.all(
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .stretch,
                      children: [
                        Text(
                          'النتائج: ${data.total} • بباركود: ${printable.length} • محدد: ${_selected.length}',
                          style: Theme.of(
                            context,
                          )
                              .textTheme
                              .labelLarge,
                        ),
                        if (printable.isNotEmpty ||
                            selectedPrintable
                                .isNotEmpty) ...[
                          const SizedBox(
                            height:
                                AppSpacing.sm,
                          ),
                          Wrap(
                            spacing:
                                AppSpacing.sm,
                            runSpacing:
                                AppSpacing.sm,
                            children: [
                              FilledButton.icon(
                                onPressed: _printing
                                    ? null
                                    : () => _printXPrinter(
                                          selectedPrintable
                                                  .isNotEmpty
                                              ? selectedPrintable
                                              : printable,
                                        ),
                                icon: const Icon(
                                  Icons
                                      .label_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  selectedPrintable
                                          .isNotEmpty
                                      ? 'XPrinter المحدد (${selectedPrintable.length})'
                                      : 'XPrinter',
                                ),
                              ),
                              if (supportsUsbReceiptPrint)
                                FilledButton.icon(
                                  onPressed: _printing
                                      ? null
                                      : () =>
                                          _printReceiptUsb(
                                    selectedPrintable
                                            .isNotEmpty
                                        ? selectedPrintable
                                        : printable,
                                  ),
                                  icon: _printing
                                      ? const SizedBox(
                                          width: 16,
                                          height:
                                              16,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth:
                                                2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons
                                              .receipt_long_outlined,
                                          size:
                                              18,
                                        ),
                                  label: Text(
                                    selectedPrintable
                                            .isNotEmpty
                                        ? 'ريسيت المحدد (${selectedPrintable.length})'
                                        : 'ريسيت الكل',
                                  ),
                                ),
                              FilledButton.icon(
                                onPressed: _printing
                                    ? null
                                    : () => _printPdf(
                                          selectedPrintable
                                                  .isNotEmpty
                                              ? selectedPrintable
                                              : printable,
                                        ),
                                icon: _printing
                                    ? const SizedBox(
                                        width: 16,
                                        height:
                                            16,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth:
                                              2,
                                          color:
                                              Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons
                                            .print_outlined,
                                        size:
                                            18,
                                      ),
                                label: Text(
                                  selectedPrintable
                                          .isNotEmpty
                                      ? 'طباعة المحدد (${selectedPrintable.length})'
                                      : 'طباعة الكل',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _previewItems(
                                  selectedPrintable
                                          .isNotEmpty
                                      ? selectedPrintable
                                      : printable,
                                ),
                                icon: const Icon(
                                  Icons
                                      .visibility_outlined,
                                  size: 18,
                                ),
                                label: const Text(
                                  'معاينة',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: AppSpacing.sm,
                  ),
                  for (final p in data.items)
                    _ProductBarcodeCard(
                      product: p,
                      selected:
                          _selected.contains(p.id),
                      canEdit: canEdit,
                      onToggle: (v) => setState(
                        () {
                          if (v == true) {
                            _selected.add(p.id);
                          } else {
                            _selected.remove(
                              p.id,
                            );
                          }
                        },
                      ),
                      onPreview: () =>
                          _previewItems([p]),
                      onPrint: () => _printPdf([p]),
                      onXPrinter: () =>
                          _printXPrinter([p]),
                      onReceipt:
                          supportsUsbReceiptPrint
                              ? () =>
                                  _printReceiptUsb(
                                    [p],
                                  )
                              : null,
                      onAdd: () =>
                          _addBarcodeSheet(p),
                      onScanAdd: () =>
                          _scanAndAdd(p.id),
                      onOpen: () => context.push(
                        '/products/${p.id}',
                      ),
                    ),
                  AppPagination(
                    page: _page,
                    total: data.total,
                    onGo: _go,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductBarcodeCard extends StatelessWidget {
  final Product product;
  final bool selected;
  final bool canEdit;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onPreview;
  final VoidCallback onPrint;
  final VoidCallback onXPrinter;
  final VoidCallback? onReceipt;
  final VoidCallback onAdd;
  final VoidCallback onScanAdd;
  final VoidCallback onOpen;
  const _ProductBarcodeCard({
    required this.product,
    required this.selected,
    required this.canEdit,
    required this.onToggle,
    required this.onPreview,
    required this.onPrint,
    required this.onXPrinter,
    required this.onReceipt,
    required this.onAdd,
    required this.onScanAdd,
    required this.onOpen,
  });

  Widget _tonal(BuildContext context, String label, VoidCallback? onTap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TapScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark
              ? AppColors.indigo.withValues(alpha: .22)
              : AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: onTap == null
                    ? AppColors.mutedText
                    : (dark ? AppColors.darkPrimary : AppColors.indigoDeep))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final code = (product.primaryBarcode ?? '').trim();
    final hasCode = code.isNotEmpty;
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (hasCode)
                Checkbox(
                  value: selected,
                  onChanged: onToggle,
                  visualDensity: VisualDensity.compact,
                ),
              Expanded(
                child: Text(
                  product.name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canEdit)
                TapScale(
                  onTap: onAdd,
                  semanticLabel:
                      hasCode ? 'تعديل الباركود' : 'إضافة باركود',
                  child: YadIconTile(
                    icon: hasCode
                        ? Icons.edit_outlined
                        : Icons.add_circle_outline,
                    size: 38,
                    radius: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dark ? AppColors.darkBackground : AppColors.mist,
              borderRadius: BorderRadius.circular(18),
            ),
            child: hasCode
                ? Column(
                    children: [
                      SizedBox(
                        height: 60,
                        child: bw.BarcodeWidget(
                          data: code,
                          barcode: bw.Barcode.code128(),
                          drawText: false,
                          color: dark ? Colors.white : AppColors.ink,
                          errorBuilder: (_, _) => const Icon(
                              Icons.qr_code_2_outlined,
                              size: 40),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(code,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.titleSmall?.copyWith(
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700)),
                    ],
                  )
                : Column(
                    children: [
                      Text(
                        'بدون باركود — أضف رقما يدويا أو بالسكانر',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.danger),
                      ),
                      if (canEdit) ...[
                        const SizedBox(height: 10),
                        _tonal(context, 'مسح سكانر', onScanAdd),
                      ],
                    ],
                  ),
          ),
          if (hasCode) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _tonal(context, 'ريسيت', onReceipt)),
                const SizedBox(width: 8),
                Expanded(child: _tonal(context, 'A4', onPrint)),
                const SizedBox(width: 8),
                Expanded(child: _tonal(context, 'XPrinter', onXPrinter)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: 'طباعة XPrinter',
                    height: 46,
                    expand: true,
                    onPressed: onXPrinter,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: onPreview,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('معاينة'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
