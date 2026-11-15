import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../products/data/products_repository.dart';
import '../../../products/domain/product.dart';
import '../../../sales/data/sales_repository.dart';
import '../../../sales/domain/sales.dart';
import '../../data/serials_repository.dart';

/// شيت تسجيل سيريالات البيع من فاتورة معتمدة.
/// يعرض بنود الإلكترونيات فقط (فئة إلكترونيات)، بعدد حقول = الكمية،
/// مع اقتراحات من سيريالات المخزون — والسيريال المتباع بيخرج من المخزون.
Future<int?> showRegisterSerialSheet(
    BuildContext context, String invoiceId) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _RegisterSerialSheet(invoiceId: invoiceId),
  );
}

class _ElecLine {
  final SalesInvoiceItem item;
  final List<TextEditingController> ctrls;
  final List<String> stock;
  _ElecLine(
      {required this.item,
      required this.ctrls,
      required this.stock});
}

class _RegisterSerialSheet extends ConsumerStatefulWidget {
  final String invoiceId;
  const _RegisterSerialSheet({required this.invoiceId});

  @override
  ConsumerState<_RegisterSerialSheet> createState() =>
      _RegisterSerialSheetState();
}

class _RegisterSerialSheetState
    extends ConsumerState<_RegisterSerialSheet> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<_ElecLine> _lines = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final l in _lines) {
      for (final c in l.ctrls) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final salesRepo = ref.read(salesRepositoryProvider);
      final prodRepo = ref.read(productsRepositoryProvider);
      final items =
          await salesRepo.itemsOf(widget.invoiceId);
      final std = [
        for (final it in items)
          if (!it.isCustom && it.productId != null) it
      ];
      if (std.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'لا توجد أصناف مخزنية في الفاتورة.';
          });
        }
        return;
      }
      final products = await prodRepo.getMany(
          [for (final it in std) it.productId!]);
      final byId = {for (final p in products) p.id: p};
      final cats = await prodRepo.categories();
      ProductCategory? elec;
      for (final c in cats) {
        if (isElectronicsCategory(c)) {
          elec = c;
          break;
        }
      }
      final lines = <_ElecLine>[];
      for (final it in std) {
        final p = byId[it.productId];
        if (elec == null || p?.categoryId != elec.id) continue;
        final n = it.quantity
            .clamp(1, 100)
            .toInt();
        final stock = await prodRepo.serialsOf(it.productId!);
        lines.add(_ElecLine(
          item: it,
          ctrls: [
            for (var i = 0; i < n; i++)
              TextEditingController()
          ],
          stock: stock,
        ));
      }
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loading = false;
        if (lines.isEmpty) {
          _error =
              'لا توجد أصناف إلكترونيات (طابعات) في الفاتورة.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AppFailure
            ? e.messageAr
            : 'تعذر تحميل بنود الفاتورة.';
      });
    }
  }

  Future<void> _submit() async {
    final jobs = <(String, String)>[];
    for (final l in _lines) {
      for (final c in l.ctrls) {
        final s = c.text.trim();
        if (s.isNotEmpty) jobs.add((l.item.id, s));
      }
    }
    if (jobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اكتب سيريال واحد على الأقل.')));
      return;
    }
    setState(() => _saving = true);
    var ok = 0;
    final dup = <String>[];
    try {
      final repo = ref.read(serialsRepositoryProvider);
      for (final (itemId, serial) in jobs) {
        try {
          await repo.registerSale(
              itemId: itemId, serial: serial);
          ok++;
        } catch (e) {
          final msg = e is AppFailure ? e.messageAr : '';
          if (msg.contains('ALREADY_SOLD')) {
            dup.add(serial);
          } else {
            dup.add('$serial ($msg)');
          }
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok > 0
            ? 'اتسجل $ok سيريال بيع.${dup.isNotEmpty ? ' متكرر: ${dup.join('، ')}' : ''}'
            : 'تعذر التسجيل: ${dup.join('، ')}')));
    if (ok > 0) Navigator.of(context).pop(ok);
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
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text('تسجيل سيريالات البيع',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text(
              'سيريال لكل جهاز مباع — المتباع بيخرج من مخزون السيريالات، والتحقق بيظهر ملف العميل كامل.',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Center(
                  child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.grey)),
            for (final l in _lines) ...[
              Text(l.item.itemName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold)),
              Text(
                'الكمية: ${l.item.quantity}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
              if (l.stock.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in l.stock)
                      ActionChip(
                        label: Text(s,
                            textDirection:
                                TextDirection.ltr,
                            style: const TextStyle(
                                fontSize: 12)),
                        visualDensity:
                            VisualDensity.compact,
                        onPressed: () {
                          for (final c
                              in l.ctrls) {
                            if (c.text
                                .trim()
                                .isEmpty) {
                              setState(() =>
                                  c.text = s);
                              break;
                            }
                          }
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              for (var i = 0;
                  i < l.ctrls.length;
                  i++)
                Padding(
                  padding: const EdgeInsets.only(
                      bottom: 8),
                  child: TextField(
                    controller: l.ctrls[i],
                    textDirection:
                        TextDirection.ltr,
                    decoration: InputDecoration(
                        labelText:
                            'سيريال ${i + 1}',
                        isDense: true),
                  ),
                ),
              const Divider(height: 20),
            ],
            if (_lines.isNotEmpty)
              FilledButton(
                onPressed:
                    _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(
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
