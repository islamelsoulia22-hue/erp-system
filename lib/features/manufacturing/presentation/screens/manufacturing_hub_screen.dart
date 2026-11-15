import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/manufacturing_providers.dart';

String czStatusAr(String s) {
  return switch (s) {
    'DRAFT' => 'مسودة',
    'PENDING_APPROVAL' => 'بانتظار الاعتماد',
    'APPROVED' => 'معتمدة',
    'MANUFACTURING' => 'قيد التصنيع',
    'READY' => 'جاهزة',
    'REJECTED' => 'مرفوضة',
    'CANCELLED' => 'ملغاة',
    _ => s,
  };
}

String moStatusAr(String s) {
  return switch (s) {
    'DRAFT' => 'مسودة',
    'IN_PROGRESS' => 'قيد التنفيذ',
    'COMPLETED' => 'مكتملة',
    'CANCELLED' => 'ملغاة',
    _ => s,
  };
}

class ManufacturingHubScreen extends ConsumerWidget {
  const ManufacturingHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.salesCreate),
          orElse: () => false,
        );
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'منتجات مخصصة'),
                Tab(text: 'أوامر الإنتاج')
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                const TabBarView(
                  children: [_CzTab(), _MoTab()],
                ),
                if (canCreate)
                  PositionedDirectional(
                    bottom: 16,
                    end: 16,
                    child: Builder(builder: (ctx) {
                      return FloatingActionButton(
                        child: const Icon(
                            Icons.add_outlined),
                        onPressed: () {
                          final tab =
                              DefaultTabController.of(
                                      ctx)
                                  .index;
                          context.push(tab == 0
                              ? '/customized/new'
                              : '/manufacturing-orders/new');
                        },
                      );
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CzTab extends ConsumerStatefulWidget {
  const _CzTab();
  @override
  ConsumerState<_CzTab> createState() => _CzTabState();
}

class _CzTabState extends ConsumerState<_CzTab> {
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
    final page = ref.watch(czPageProvider(_page));
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(czPageProvider(_page).future),
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
                    child: Text('لا توجد أصناف مخصصة'))
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
                  final c = paged.items[i];
                  return ListTile(
                    leading: const Icon(
                        Icons.handyman_outlined),
                    title: Text(c.name),
                    subtitle: Text(
                        '${c.code} • ${czStatusAr(c.status)}\n${c.totalPrice.toStringAsFixed(2)} ج.م'),
                    isThreeLine: true,
                    onTap: () => context
                        .push('/customized/${c.id}'),
                  );
                },
              ),
      ),
    );
  }
}

class _MoTab extends ConsumerStatefulWidget {
  const _MoTab();
  @override
  ConsumerState<_MoTab> createState() => _MoTabState();
}

class _MoTabState extends ConsumerState<_MoTab> {
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
    final page = ref.watch(moPageProvider(_page));
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(moPageProvider(_page).future),
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
                    child: Text('لا توجد أوامر إنتاج'))
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
                  final o = paged.items[i];
                  return ListTile(
                    leading: const Icon(
                        Icons.factory_outlined),
                    title: Text(o.number,
                        textDirection:
                            TextDirection.ltr),
                    subtitle:
                        Text(moStatusAr(o.status)),
                    onTap: () => context.push(
                        '/manufacturing-orders/${o.id}'),
                  );
                },
              ),
      ),
    );
  }
}
