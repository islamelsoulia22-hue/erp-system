import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/procurement_repository.dart';

String prStatusAr(String s) {
  return switch (s) {
    'DRAFT' => 'مسودة',
    'PENDING_APPROVAL' => 'بانتظار الاعتماد',
    'APPROVED' => 'معتمدة',
    'PARTIALLY_RECEIVED' => 'استلام جزئي',
    'RECEIVED' => 'مستلمة',
    'REJECTED' => 'مرفوضة',
    'CANCELLED' => 'ملغاة',
    _ => s,
  };
}

class ProcurementListScreen extends ConsumerStatefulWidget {
  const ProcurementListScreen({super.key});
  @override
  ConsumerState<ProcurementListScreen> createState() =>
      _ProcurementListScreenState();
}

class _ProcurementListScreenState
    extends ConsumerState<ProcurementListScreen> {
  final _scroll = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int p) {
    setState(() => _page = p);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.purchasesCreate),
          orElse: () => false,
        );
    final page = ref.watch(procurementPageProvider(_page));
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () =>
                  context.push('/procurement/new'),
              child: const Icon(Icons.add_outlined))
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref
            .refresh(procurementPageProvider(_page).future),
        child: page.when(
          loading: () => ListView(children: const [
            SizedBox(height: 80),
            Center(child: CircularProgressIndicator()),
          ]),
          error: (e, _) => ListView(children: const [
            SizedBox(height: 80),
            Center(
                child: Text(
                    'حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.')),
          ]),
          data: (paged) => paged.items.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  Center(
                      child: Text(
                          'لا توجد طلبات — أنشئ طلبا عند نقص المخزون'))
                ])
              : ListView.separated(
                  controller: _scroll,
                  itemCount: paged.items.length + 1,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i >= paged.items.length) {
                      return AppPagination(
                        page: _page,
                        total: paged.total,
                        onGo: _go,
                      );
                    }
                    final r = paged.items[i];
                    return ListTile(
                      leading: const Icon(
                          Icons.request_quote_outlined),
                      title: Text(r.number,
                          textDirection:
                              TextDirection.ltr),
                      subtitle: Text(
                          '${r.supplierName ?? 'بدون مورد'} • ${prStatusAr(r.status)}'),
                      onTap: () => context
                          .push('/procurement/${r.id}'),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
