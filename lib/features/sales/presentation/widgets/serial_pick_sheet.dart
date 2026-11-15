import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../products/data/products_repository.dart';

/// شيت اختيار سيريالات صنف إلكتروني طالع للعميل.
/// يعرض سيريالات المخزون للاختيار + إدخال يدوي، بعدد = الكمية.
Future<List<String>?> showSerialPickSheet(
  BuildContext context, {
  required String productId,
  required double qty,
  List<String> initial = const [],
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SerialPickSheet(
      productId: productId,
      qty: qty,
      initial: initial,
    ),
  );
}

class _SerialPickSheet extends ConsumerStatefulWidget {
  final String productId;
  final double qty;
  final List<String> initial;
  const _SerialPickSheet({
    required this.productId,
    required this.qty,
    required this.initial,
  });

  @override
  ConsumerState<_SerialPickSheet> createState() =>
      _SerialPickSheetState();
}

class _SerialPickSheetState
    extends ConsumerState<_SerialPickSheet> {
  final _manual = TextEditingController();
  bool _loading = true;
  List<String> _stock = [];
  late List<String> _picked;

  @override
  void initState() {
    super.initState();
    _picked = [...widget.initial];
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(productsRepositoryProvider)
          .serialsOf(widget.productId);
      if (!mounted) return;
      // المستبعد: المتسجل بيع قبل كده مش هيظهر (خرج من المخزون).
      setState(() {
        _stock = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _need => widget.qty.toInt();

  void _toggle(String s) {
    setState(() {
      if (_picked.contains(s)) {
        _picked.remove(s);
      } else {
        if (_picked.length >= _need) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'الكمية $_need — شيل واحد الأول لو عايز تبدل.')));
          return;
        }
        _picked.add(s);
      }
    });
  }

  void _addManual() {
    final s = _manual.text.trim();
    if (s.isEmpty) return;
    if (_picked.contains(s)) return;
    if (_picked.length >= _need) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('الكمية $_need — شيل واحد الأول.')));
      return;
    }
    setState(() {
      _picked.add(s);
      _manual.clear();
    });
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
            Text(
                'سيريالات العميل (${_picked.length}/$_need)',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text(
              'اختار من المخزون أو اكتب يدوي — هيتسجلوا للعميل عند اعتماد الفاتورة.',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _manual,
                      textDirection:
                          TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'سيريال يدوي',
                              isDense: true),
                      onSubmitted: (_) =>
                          _addManual())),
              IconButton(
                icon: const Icon(Icons.add_outlined),
                onPressed: _addManual,
              ),
            ]),
            if (_loading)
              const Center(
                  child: CircularProgressIndicator()),
            if (!_loading && _stock.isEmpty)
              const Text(
                  'لا توجد سيريالات في المخزون — اكتب يدوي.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey)),
            if (!_loading && _stock.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in _stock)
                    FilterChip(
                      label: Text(s,
                          textDirection:
                              TextDirection.ltr,
                          style: const TextStyle(
                              fontSize: 12)),
                      selected:
                          _picked.contains(s),
                      visualDensity:
                          VisualDensity.compact,
                      onSelected: (_) =>
                          _toggle(s),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_picked),
              child: Text(
                  'تأكيد (${_picked.length}/$_need)'),
            ),
          ],
        ),
      ),
    );
  }
}
