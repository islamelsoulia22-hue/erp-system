import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/expenses_repository.dart';
import '../../domain/expense.dart';
import '../providers/expenses_providers.dart';

final _dfmt = DateFormat('yyyy/MM/dd');

final _installmentsProvider =
    FutureProvider.autoDispose<List<Expense>>((ref) {
  return ref.watch(expensesRepositoryProvider).installments();
});

String _groupBase(String title) {
  final i = title.lastIndexOf(' — قسط ');
  return i < 0 ? title : title.substring(0, i);
}

/// الأقساط: الالتزامات القادمة والمستحقة + إنشاء التزام جديد.
class InstallmentsScreen extends ConsumerStatefulWidget {
  const InstallmentsScreen({super.key});

  @override
  ConsumerState<InstallmentsScreen> createState() =>
      _InstallmentsScreenState();
}

class _InstallmentsScreenState
    extends ConsumerState<InstallmentsScreen> {
  int _page = 0;

  void _go(int p) => setState(() => _page = p);

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.expensesCreate),
          orElse: () => false,
        );
    final list = ref.watch(_installmentsProvider);
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => context
                  .push('/expenses/installments/new')
                  .then((_) =>
                      ref.invalidate(_installmentsProvider)),
              child: const Icon(Icons.add_outlined))
          : null,
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(_installmentsProvider),
        child: list.when(
          loading: () =>
              const LoadingSkeleton(rows: 5),
          error: (_, _) => const ErrorState(),
          data: (rows) {
            final today = DateTime(DateTime.now().year,
                DateTime.now().month, DateTime.now().day);
            final due = rows
                .where((e) =>
                    !e.isPaid &&
                    !e.expenseDate.isAfter(today))
                .toList();
            if (rows.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Center(
                    child: Text(
                        'لا توجد أقساط — أنشئ أول التزام'))
              ]);
            }
            // تجميع حسب group_id (أو الاسم للقديم).
            final groups = <String, List<Expense>>{};
            final names = <String, String>{};
            for (final e in rows) {
              final key = e.groupId ?? 'n:${_groupBase(e.title)}';
              groups.putIfAbsent(key, () => []).add(e);
              names.putIfAbsent(
                  key, () => _groupBase(e.title));
            }
            final entries = paginateLocal(
                groups.entries.toList(), _page);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (due.isNotEmpty)
                  AppCard(
                    padding: const EdgeInsets.all(
                        AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(
                            Icons.warning_amber_outlined,
                            color: Colors.red),
                        const SizedBox(
                            width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                              'مستحق الآن: ${due.length} قسط بإجمالي ${AppFormat.money(due.fold(0.0, (s, e) => s + e.amount))}'),
                        ),
                      ],
                    ),
                  ),
                if (due.isNotEmpty)
                  const SizedBox(
                      height: AppSpacing.sm),
                for (final entry in entries)
                  _GroupCard(
                      name: names[entry.key] ?? entry.key,
                      items: entry.value),
                AppPagination(
                  page: _page,
                  total: groups.length,
                  onGo: _go,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String name;
  final List<Expense> items;
  const _GroupCard(
      {required this.name, required this.items});

  @override
  Widget build(BuildContext context) {
    items.sort((a, b) =>
        a.expenseDate.compareTo(b.expenseDate));
    final total =
        items.fold(0.0, (s, e) => s + e.amount);
    final paid =
        items.where((e) => e.isPaid).fold(0.0, (s, e) => s + e.amount);
    final today = DateTime(DateTime.now().year,
        DateTime.now().month, DateTime.now().day);
    Expense? next;
    for (final e in items) {
      if (!e.isPaid) {
        next = e;
        break;
      }
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall),
          Text(
            'الإجمالي ${AppFormat.money(total)} • مدفوع ${AppFormat.money(paid)} • متبقي ${AppFormat.money(total - paid)}',
            style:
                Theme.of(context).textTheme.bodySmall,
          ),
          if (next != null)
            Text(
              'القسط القادم: ${_dfmt.format(next.expenseDate)} • ${AppFormat.money(next.amount)}${!next.expenseDate.isAfter(today) ? ' • مستحق' : ''}',
              style: TextStyle(
                  fontSize: 12,
                  color: !next.expenseDate
                          .isAfter(today)
                      ? Colors.red
                      : Colors.grey,
                  fontWeight: FontWeight.bold),
            ),
          const Divider(height: 16),
          for (final e in items)
            _InstallRow(expense: e, today: today),
        ],
      ),
    );
  }
}

class _InstallRow extends StatelessWidget {
  final Expense expense;
  final DateTime today;
  const _InstallRow(
      {required this.expense, required this.today});

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final overdue = !e.isPaid && !e.expenseDate.isAfter(today);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
          e.isPaid
              ? Icons.check_circle_outline
              : Icons.schedule_outlined,
          size: 20,
          color: e.isPaid
              ? Colors.green
              : overdue
                  ? Colors.red
                  : Colors.grey),
      title: Text(
          '${_dfmt.format(e.expenseDate)} • ${AppFormat.money(e.amount)}',
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
          e.isPaid ? 'مدفوعة' : overdue ? 'مستحق' : 'قادم',
          style: TextStyle(
              fontSize: 11,
              color: e.isPaid
                  ? Colors.green
                  : overdue
                      ? Colors.red
                      : Colors.grey)),
      trailing: const Icon(Icons.chevron_left_outlined,
          size: 20),
      onTap: () =>
          context.push('/expenses/${e.id}'),
    );
  }
}

/// فورم التزام جديد بالتقسيط.
class InstallmentFormScreen extends ConsumerStatefulWidget {
  const InstallmentFormScreen({super.key});

  @override
  ConsumerState<InstallmentFormScreen> createState() =>
      _InstallmentFormScreenState();
}

class _InstallmentFormScreenState
    extends ConsumerState<InstallmentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _total = TextEditingController();
  final _count = TextEditingController(text: '12');
  final _party = TextEditingController();
  final _notes = TextEditingController();
  String? _categoryId;
  DateTime _first = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _total.dispose();
    _count.dispose();
    _party.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _per {
    final t = double.tryParse(_total.text.trim()) ?? 0;
    final n = int.tryParse(_count.text.trim()) ?? 0;
    if (t <= 0 || n <= 0) return 0;
    return t / n;
  }

  Future<void> _pickFirst() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _first,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (p != null && mounted) setState(() => _first = p);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختر التصنيف.')));
      return;
    }
    final total = double.parse(_total.text.trim());
    final n = int.parse(_count.text.trim());
    if (n <= 0 || n > 120) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('عدد الأقساط من 1 لـ 120.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(expensesRepositoryProvider);
      final gid =
          'INST-${DateTime.now().millisecondsSinceEpoch}';
      final per = (total / n * 100).round() / 100;
      for (var i = 0; i < n; i++) {
        final date =
            DateTime(_first.year, _first.month + i, _first.day);
        final amount =
            i == n - 1 ? total - per * (n - 1) : per;
        await repo.createInstallment({
          'category_id': _categoryId,
          'title': '${_name.text.trim()} — قسط ${i + 1}/$n',
          'amount': amount,
          'expense_date':
              date.toIso8601String().substring(0, 10),
          'party_name': _party.text.trim().isEmpty
              ? null
              : _party.text.trim(),
          'notes': _notes.text.trim().isEmpty
              ? null
              : _notes.text.trim(),
          'group_id': gid,
          'installment_no': i + 1,
          'total_installments': n,
        });
      }
      ref.invalidate(_installmentsProvider);
      ref.invalidate(expensesPageProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء الحفظ.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(expenseCategoriesProvider);
    return Scaffold(
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText:
                        'الاسم * (مثال: قسط سيارة نقل)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'اكتب الاسم'
                        : null),
            const SizedBox(height: 12),
            cats.when(
              loading: () => const Center(
                  child: CircularProgressIndicator()),
              error: (e, _) =>
                  Text('تعذر التحميل: $e'),
              data: (list) =>
                  DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                    labelText: 'التصنيف *'),
                items: [
                  for (final c in list)
                    DropdownMenuItem(
                        value: c.id,
                        child: Text(c.display)),
                ],
                onChanged: (v) =>
                    setState(() => _categoryId = v),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                      controller: _total,
                      keyboardType: const TextInputType
                          .numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'إجمالي الالتزام *'),
                      validator: (v) {
                        final d = double.tryParse(
                            (v ?? '').trim());
                        if (d == null || d <= 0) {
                          return 'رقم غير صالح';
                        }
                        return null;
                      },
                      onChanged: (_) =>
                          setState(() {})),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'عدد الأقساط *'),
                      validator: (v) {
                        final d = int.tryParse(
                            (v ?? '').trim());
                        if (d == null ||
                            d <= 0 ||
                            d > 120) {
                          return '1-120';
                        }
                        return null;
                      },
                      onChanged: (_) =>
                          setState(() {})),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'قيمة القسط: ${AppFormat.money(_per)} شهريا',
              style:
                  const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _pickFirst,
              child: Text(
                  'تاريخ أول قسط: ${_dfmt.format(_first)}'),
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _party,
                decoration: const InputDecoration(
                    labelText: 'الجهة (اختياري)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : const Text('إنشاء الأقساط'),
            ),
          ],
        ),
      ),
    );
  }
}
