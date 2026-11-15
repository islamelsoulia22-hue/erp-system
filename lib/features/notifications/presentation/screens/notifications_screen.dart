import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../procurement/data/procurement_repository.dart';
import '../../../../core/widgets/app_pagination.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends ConsumerState<NotificationsScreen> {
  int _page = 0;

  void _go(int p) => setState(() => _page = p);

  void _open(BuildContext context, dynamic n) {
    final entity = (n as dynamic).entityType as String?;
    final id = (n as dynamic).entityId as String?;
    if (entity == 'PROCUREMENT_REQUEST' && id != null) {
      context.push('/procurement/$id');
    } else if (entity == 'STOCK_ALERT') {
      context.push('/stock-alerts');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(notificationsListProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _page = 0);
          ref.invalidate(notificationsListProvider);
          ref.invalidate(unreadCountProvider);
        },
        child: Column(
          children: [
            Align(
              alignment:
                  AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    12, 12, 12, 4),
                child: TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(
                            notificationsRepositoryProvider)
                        .markAllRead();
                    ref.invalidate(
                        notificationsListProvider);
                    ref.invalidate(unreadCountProvider);
                  },
                  icon: const Icon(
                      Icons.done_all_outlined,
                      size: 18),
                  label: const Text(
                      'تعيين الكل كمقروء'),
                ),
              ),
            ),
            Expanded(
              child: list.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('حدث خطأ: $e')),
                data: (rows) {
                  if (rows.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 80),
                      Center(
                          child:
                              Text('لا توجد إشعارات'))
                    ]);
                  }
                  final items =
                      paginateLocal(rows, _page);
                  return Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder:
                              (context, i) {
                            final n =
                                items[i];
                      return ListTile(
                        leading: Icon(n.isRead
                            ? Icons
                                .notifications_none_outlined
                            : Icons
                                .notifications_active_outlined),
                        title: Text(n.title,
                            style: TextStyle(
                                fontWeight: n.isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold)),
                        subtitle:
                            Text(n.message ?? ''),
                        onTap: () async {
                          if (!n.isRead) {
                            await ref
                                .read(
                                    notificationsRepositoryProvider)
                                .markRead(n.id);
                            ref.invalidate(
                                notificationsListProvider);
                            ref.invalidate(
                                unreadCountProvider);
                          }
                          if (context.mounted) {
                            _open(context, n);
                          }
                        },
                      );
                    },
                  ),
                ),
                AppPagination(
                  page: _page,
                  total: rows.length,
                  onGo: _go,
                ),
              ],
            );
          },
          ),
          ),
          ],
        ),
      ),
    );
  }
}
