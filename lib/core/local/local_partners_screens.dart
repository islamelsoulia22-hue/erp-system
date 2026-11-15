import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_pagination.dart';
import 'local_partners.dart';
import 'local_payments.dart';
import 'local_products.dart' show LocalDataFailure;
import 'local_ui.dart';

/// شيت اختيار عميل/مورد لوكال (بحث).
Future<LocalPartner?> pickLocalPartner(
  BuildContext context,
  WidgetRef ref, {
  required bool supplier,
}) async {
  final q = TextEditingController();
  var query = '';
  final title = supplier ? 'اختار المورد' : 'اختار العميل';
  return showModalBottomSheet<LocalPartner>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: q,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'بحث بالاسم / الهاتف',
                    ),
                    onSubmitted: (_) => setS(() => query = q.text.trim()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () => setS(() => query = q.text.trim()),
                ),
              ],
            ),
            Flexible(
              child: Consumer(
                builder: (ctx2, ref2, _) {
                  final data = supplier
                      ? ref2.watch(
                          localSuppliersPageProvider((query: query, page: 0)),
                        )
                      : ref2.watch(
                          localCustomersPageProvider((query: query, page: 0)),
                        );
                  return data.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                    error: (_, _) => const Text('تعذر البحث.'),
                    data: (paged) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in paged.items.take(8))
                          ListTile(
                            dense: true,
                            title: Text(p.name),
                            subtitle: p.phone.isEmpty
                                ? null
                                : Text(
                                    p.phone,
                                    textDirection: TextDirection.ltr,
                                  ),
                            trailing: const Text('اختار'),
                            onTap: () => Navigator.of(ctx).pop(p),
                          ),
                        if (paged.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('لا توجد نتائج مطابقة'),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// قايمة عملاء أو موردين لوكال.
class LocalPartnersScreen extends ConsumerStatefulWidget {
  final bool supplier;
  const LocalPartnersScreen({super.key, required this.supplier});

  @override
  ConsumerState<LocalPartnersScreen> createState() =>
      _LocalPartnersScreenState();
}

class _LocalPartnersScreenState extends ConsumerState<LocalPartnersScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _kind => widget.supplier ? 'الموردين' : 'العملاء';
  String get _one => widget.supplier ? 'مورد' : 'عميل';

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$_one جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'الهاتف (اختياري)'),
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
    if (ok != true || !mounted) return;
    try {
      if (widget.supplier) {
        await ref
            .read(localSuppliersRepositoryProvider)
            .create(name: name.text, phone: phone.text);
        ref.invalidate(localSuppliersPageProvider);
      } else {
        await ref
            .read(localCustomersRepositoryProvider)
            .create(name: name.text, phone: phone.text);
        ref.invalidate(localCustomersPageProvider);
      }
    } on LocalDataFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.messageAr)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.supplier
        ? ref.watch(localSuppliersPageProvider((query: _query, page: _page)))
        : ref.watch(localCustomersPageProvider((query: _query, page: _page)));
    return Scaffold(
      appBar: AppBar(title: Text(_kind)),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
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
                      labelText: 'بحث',
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
                  return Center(child: Text('لا يوجد $_kind بعد.'));
                }
                return ListView.separated(
                  itemCount: paged.items.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i >= paged.items.length) {
                      return AppPagination(
                        page: _page,
                        total: paged.total,
                        pageSize: 20,
                        onGo: (p) => setState(() => _page = p),
                      );
                    }
                    final p = paged.items[i];
                    return ListTile(
                      leading: Icon(
                        widget.supplier
                            ? Icons.handshake_outlined
                            : Icons.person_outlined,
                      ),
                      title: Text(p.name),
                      subtitle: p.phone.isEmpty
                          ? null
                          : Text(p.phone, textDirection: TextDirection.ltr),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LocalPartnerDetailScreen(
                              supplier: widget.supplier,
                              partner: p,
                            ),
                          ),
                        );
                        if (widget.supplier) {
                          ref.invalidate(localSuppliersPageProvider);
                        } else {
                          ref.invalidate(localCustomersPageProvider);
                        }
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

/// تفاصيل عميل/مورد: بيانات + المستحق + إيقاف/حذف.
class LocalPartnerDetailScreen extends ConsumerWidget {
  final bool supplier;
  final LocalPartner partner;
  const LocalPartnerDetailScreen({
    super.key,
    required this.supplier,
    required this.partner,
  });

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (supplier) {
      await ref
          .read(localSuppliersRepositoryProvider)
          .setActive(partner.id, !partner.isActive);
      ref.invalidate(localSuppliersPageProvider);
    } else {
      await ref
          .read(localCustomersRepositoryProvider)
          .setActive(partner.id, !partner.isActive);
      ref.invalidate(localCustomersPageProvider);
    }
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirmLocalDelete(context, 'حذف؟', partner.name);
    if (!ok) return;
    if (supplier) {
      await ref.read(localSuppliersRepositoryProvider).remove(partner.id);
      ref.invalidate(localSuppliersPageProvider);
    } else {
      await ref.read(localCustomersRepositoryProvider).remove(partner.id);
      ref.invalidate(localCustomersPageProvider);
    }
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(partner.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('الاسم'),
                  subtitle: Text(partner.name),
                ),
                ListTile(
                  title: const Text('الهاتف'),
                  subtitle: Text(
                    partner.phone.isEmpty ? '—' : partner.phone,
                    textDirection: TextDirection.ltr,
                  ),
                ),
                FutureBuilder(
                  future: ref
                      .read(localPaymentsRepositoryProvider)
                      .partnerOutstanding(
                        customerId: supplier ? null : partner.id,
                        supplierId: supplier ? partner.id : null,
                      ),
                  builder: (context, snap) {
                    final v = snap.data ?? 0.0;
                    return ListTile(
                      title: Text(
                        supplier ? 'المستحق للمورد' : 'مستحقات العميل',
                      ),
                      subtitle: Text(
                        '$v',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: v > 0 ? Colors.orange : Colors.green,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _toggle(context, ref),
            icon: Icon(
              partner.isActive
                  ? Icons.pause_outlined
                  : Icons.play_arrow_outlined,
            ),
            label: Text(partner.isActive ? 'إيقاف' : 'تفعيل'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _remove(context, ref),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
