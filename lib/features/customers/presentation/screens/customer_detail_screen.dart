import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../payments/data/payments_repository.dart';
import '../../../sales/data/sales_repository.dart';
import '../../data/customers_repository.dart';
import '../../domain/customer.dart';
import '../providers/customers_providers.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState
    extends ConsumerState<CustomerDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final detail =
        ref.watch(customerDetailProvider(widget.customerId));
    final addresses =
        ref.watch(customerAddressesProvider(widget.customerId));
    final canEdit = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.customersEdit),
          orElse: () => false,
        );
    final isManager = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.isCompanyManager,
          orElse: () => false,
        );

    return detail.when(
      loading: () => const LoadingSkeleton(rows: 6),
      error: (_, _) => const ErrorState(),
      data: (c) {
        if (c == null) {
          return const EmptyState(
            icon: Icons.person_outline,
            title: 'العميل غير موجود.',
          );
        }
        return ResponsiveLayout(
          mobile: ListView(
            padding:
                EdgeInsets.all(context.contentPadding),
            children: [
              AppCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          AppColors.primaryContainer,
                      child: Text(
                          c.name.isNotEmpty
                              ? c.name[0]
                              : '?',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight:
                                  FontWeight.w700,
                              fontSize: 20)),
                    ),
                    const SizedBox(
                        width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall),
                          Text(c.code,
                              textDirection:
                                  TextDirection.ltr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                        AppStatus.badge(c.isActive
                            ? 'ACTIVE'
                            : 'INACTIVE'),
                        if (canEdit)
                          IconButton(
                            tooltip: 'تعديل',
                            iconSize: 20,
                            icon: const Icon(
                                Icons.edit_outlined),
                            onPressed: () => context.push(
                                '/customers/${widget.customerId}/edit'),
                          ),
                        if (isManager)
                          IconButton(
                            tooltip: 'حذف العميل',
                            iconSize: 20,
                            icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger),
                            onPressed: () =>
                                _deleteCustomer(
                                    context,
                                    ref,
                                    widget.customerId,
                                    c.name),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(
                  height: AppSpacing.md),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0,
                      label: Text('نظرة عامة')),
                  ButtonSegment(
                      value: 1,
                      label: Text('الفواتير')),
                  ButtonSegment(
                      value: 2,
                      label: Text('العناوين')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) =>
                    setState(() => _tab = s.first),
              ),
              const SizedBox(
                  height: AppSpacing.md),
              if (_tab == 0)
                _Overview(
                    customer: c,
                    customerId: widget.customerId),
              if (_tab == 1)
                _Invoices(
                    customerId: widget.customerId),
              if (_tab == 2)
                _Addresses(
                  addresses: addresses,
                  canEdit: canEdit,
                  onAdd: () => _addressSheet(
                      context, ref, c, null),
                  onEdit: (a) => _addressSheet(
                      context, ref, c, a),
                  onDelete: (id) => _deleteAddress(
                      context, ref, id),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteCustomer(BuildContext context, WidgetRef ref,
      String id, String name) async {
    if (!await confirmDelete(context, 'العميل "$name"')) return;
    try {
      await ref.read(customersRepositoryProvider).deleteCustomer(id);
      ref
        ..invalidate(customersPageProvider)
        ..invalidate(customerDetailProvider(id));
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(deleteErrorMessage(e))));
      }
    }
  }

  Future<void> _deleteAddress(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(customersRepositoryProvider).removeAddress(id);
      ref.invalidate(
          customerAddressesProvider(widget.customerId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ أثناء تنفيذ العملية.')));
      }
    }
  }

  void _addressSheet(BuildContext context, WidgetRef ref, Customer c,
      CustomerAddress? a) {
    final label = TextEditingController(text: a?.label ?? '');
    final line = TextEditingController(text: a?.addressLine ?? '');
    final gov = TextEditingController(text: a?.governorate ?? '');
    final city = TextEditingController(text: a?.city ?? '');
    final area = TextEditingController(text: a?.area ?? '');
    final phone = TextEditingController(text: a?.phone ?? c.phone ?? '');
    bool isDef = a?.isDefault ?? false;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(a == null ? 'عنوان جديد' : 'تعديل عنوان',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                  controller: label,
                  decoration:
                      const InputDecoration(labelText: 'اسم العنوان')),
              TextField(
                  controller: line,
                  decoration:
                      const InputDecoration(labelText: 'العنوان')),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: gov,
                        decoration: const InputDecoration(
                            labelText: 'المحافظة'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: city,
                        decoration: const InputDecoration(
                            labelText: 'المدينة'))),
              ]),
              TextField(
                  controller: area,
                  decoration:
                      const InputDecoration(labelText: 'المنطقة')),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'هاتف التوصيل')),
              SwitchListTile(
                  title: const Text('افتراضي'),
                  value: isDef,
                  onChanged: (v) => setS(() => isDef = v)),
              FilledButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(customersRepositoryProvider)
                        .upsertAddress({
                      if (a != null) 'id': a.id,
                      'customer_id': c.id,
                      'label': label.text.trim().isEmpty
                          ? null
                          : label.text.trim(),
                      'address_line': line.text.trim().isEmpty
                          ? null
                          : line.text.trim(),
                      'governorate': gov.text.trim().isEmpty
                          ? null
                          : gov.text.trim(),
                      'city': city.text.trim().isEmpty
                          ? null
                          : city.text.trim(),
                      'area': area.text.trim().isEmpty
                          ? null
                          : area.text.trim(),
                      'phone': phone.text.trim().isEmpty
                          ? null
                          : phone.text.trim(),
                      'is_default': isDef,
                    });
                    ref.invalidate(
                        customerAddressesProvider(c.id));
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content: Text(e is AppFailure
                                  ? e.messageAr
                                  : 'حدث خطأ أثناء الحفظ.')));
                    }
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  final Customer customer;
  final String customerId;
  const _Overview(
      {required this.customer, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            children: [
              _row(context, 'الهاتف',
                  customer.phone ?? '—'),
              if (customer.company?.isNotEmpty == true)
                _row(context, 'الشركة',
                    customer.company!),
              if (customer.notes != null)
                _row(context, 'ملاحظات',
                    customer.notes!),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FutureBuilder(
          future: ref
              .read(paymentsRepositoryProvider)
              .customerBalance(customer.id),
          builder: (context, snap) {
            final b = snap.data;
            return AppCard(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          AppColors.warningContainer,
                      borderRadius:
                          BorderRadius.circular(8),
                    ),
                    child: const Icon(
                        Icons
                            .account_balance_wallet_outlined,
                        color: Color(0xFFB45309)),
                  ),
                  const SizedBox(
                      width: AppSpacing.sm),
                  Expanded(
                    child: b == null
                        ? Text('جاري حساب الرصيد...',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium)
                        : Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                'مستحق ${AppFormat.money(b.outstanding)}',
                                style: Theme.of(
                                        context)
                                    .textTheme
                                    .titleMedium,
                              ),
                              Text(
                                'إجمالي ${AppFormat.money(b.total)} • مدفوع ${AppFormat.money(b.paid)}',
                                style: Theme.of(
                                        context)
                                    .textTheme
                                    .bodySmall,
                              ),
                              const Text(
                                'المستحق = فواتير الآجل فقط (الكاش مدفوع ولا يظهر هنا)',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs),
      child: Row(children: [
        Expanded(
            child:
                Text(k, style: theme.textTheme.bodyMedium)),
        Flexible(
          child: Text(
            v,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

class _Invoices extends ConsumerWidget {
  final String customerId;
  const _Invoices({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref
          .read(salesRepositoryProvider)
          .list(customerId: customerId, pageSize: 50),
      builder: (context, snap) {
        if (snap.connectionState ==
            ConnectionState.waiting) {
          return const LoadingSkeleton(rows: 4);
        }
        if (snap.hasError) {
          return const ErrorState(
              message: 'تعذر تحميل الفواتير.');
        }
        final rows = snap.data ?? [];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'لا توجد فواتير لهذا العميل',
          );
        }
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                ListTile(
                  dense: true,
                  title: Text(rows[i].number,
                      textDirection:
                          TextDirection.ltr),
                  subtitle: Text(
                      '${AppStatus.labelOf(rows[i].status)} • ${AppFormat.money(rows[i].grandTotal)}'),
                  trailing:
                      AppStatus.badge(rows[i].status),
                  onTap: () => context.push(
                      '/sales/${rows[i].id}'),
                ),
                if (i < rows.length - 1)
                  const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Addresses extends StatelessWidget {
  final AsyncValue<List<CustomerAddress>> addresses;
  final bool canEdit;
  final VoidCallback onAdd;
  final ValueChanged<CustomerAddress> onEdit;
  final ValueChanged<String> onDelete;
  const _Addresses({
    required this.addresses,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canEdit)
          Align(
            alignment:
                AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_outlined,
                  size: 18),
              label: const Text('إضافة عنوان'),
            ),
          ),
        if (canEdit)
          const SizedBox(height: AppSpacing.sm),
        addresses.when(
          loading: () =>
              const LoadingSkeleton(rows: 2),
          error: (_, _) => const ErrorState(
              message: 'تعذر تحميل العناوين.'),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.location_on_outlined,
                title: 'لا توجد عناوين مسجلة.',
              );
            }
            return Column(
              children: [
                for (final a in list)
                  Padding(
                    padding: const EdgeInsets.only(
                        bottom: AppSpacing.sm),
                    child: AppCard(
                      padding: const EdgeInsets.all(
                          AppSpacing.md),
                      child: Row(
                        children: [
                          Icon(a.isDefault
                              ? Icons.star_outlined
                              : Icons
                                  .location_on_outlined),
                          const SizedBox(
                              width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(a.display,
                                    style: Theme.of(
                                            context)
                                        .textTheme
                                        .titleSmall),
                                Text(
                                    '${a.governorate ?? ''} ${a.city ?? ''}${a.isDefault ? ' • افتراضي' : ''}',
                                    style: Theme.of(
                                            context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ),
                          if (canEdit)
                            PopupMenuButton<String>(
                              iconSize: 20,
                              onSelected: (v) {
                                if (v == 'edit') {
                                  onEdit(a);
                                } else {
                                  onDelete(a.id);
                                }
                              },
                              itemBuilder: (_) =>
                                  const [
                                PopupMenuItem(
                                    value: 'edit',
                                    child:
                                        Text('تعديل')),
                                PopupMenuItem(
                                    value: 'del',
                                    child:
                                        Text('حذف')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
