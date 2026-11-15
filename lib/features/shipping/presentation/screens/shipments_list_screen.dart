import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/shipping_repository.dart';

String shipStatusAr(String s) {
  return switch (s) {
    'PREPARING' => 'تجهيز',
    'SHIPPED' => 'تم الشحن',
    'DELIVERED' => 'تم التوصيل',
    'CANCELLED' => 'ملغاة',
    _ => s,
  };
}

class ShipmentsListScreen extends ConsumerStatefulWidget {
  const ShipmentsListScreen({super.key});
  @override
  ConsumerState<ShipmentsListScreen> createState() =>
      _ShipmentsListScreenState();
}

class _ShipmentsListScreenState
    extends ConsumerState<ShipmentsListScreen> {
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
          data: (p) => p.can(Permissions.salesCreate),
          orElse: () => false,
        );
    final page = ref.watch(shipmentsPageProvider(_page));
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () =>
                  context.push('/shipping/new'),
              child: const Icon(Icons.add_outlined))
          : null,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(shipmentsPageProvider(_page).future),
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
                  Center(child: Text('لا توجد شحنات'))
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
                    final s = paged.items[i];
                    return ListTile(
                      leading: const Icon(
                          Icons.local_shipping_outlined),
                      title: Text(s.number,
                          textDirection:
                              TextDirection.ltr),
                      subtitle: Text(
                          '${s.invoiceNumber ?? ''} • ${shipStatusAr(s.status)}'),
                      onTap: () => context
                          .push('/shipping/${s.id}'),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
