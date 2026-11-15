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
import '../../data/recurring_service.dart';
import '../providers/expenses_providers.dart';

final _dfmt = DateFormat('yyyy/MM/dd');

final _templatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(expensesRepositoryProvider).templates();
});

/// المصروفات المتكررة: قوالب تولد مستحقات تلقائيا.
/// التوليد يعمل عند فتح الشاشة + زرار تحديث.
class RecurringListScreen extends ConsumerStatefulWidget {
  const RecurringListScreen({super.key});

  @override
  ConsumerState<RecurringListScreen> createState() =>
      _RecurringListScreenState();
}

class _RecurringListScreenState
    extends ConsumerState<RecurringListScreen> {
  bool _generating = false;
  int _page = 0;

  void _go(int p) => setState(() => _page = p);

  @override
  void initState() {
    super.initState();
    Future.microtask(_autoGenerate);
  }

  Future<void> _autoGenerate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final n = await generateAllDue(ref);
      ref.invalidate(_templatesProvider);
      if (n > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'اتولد $n مصروف مستحق من القوالب المتكررة.')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _stop(String id) async {
    try {
      await ref
          .read(expensesRepositoryProvider)
          .updateTemplate(id, {'status': 'CANCELLED'});
      ref.invalidate(_templatesProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر إيقاف القالب.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.expensesCreate),
          orElse: () => false,
        );
    final list = ref.watch(_templatesProvider);
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => context
                  .push('/expenses/recurring/new')
                  .then((_) =>
                      ref.invalidate(_templatesProvider)),
              child: const Icon(Icons.add_outlined))
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await _autoGenerate();
          ref.invalidate(_templatesProvider);
        },
        child: list.when(
          loading: () =>
              const LoadingSkeleton(rows: 5),
          error: (_, _) => const ErrorState(),
          data: (rows) {
            if (rows.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Center(
                    child: Text(
                        'لا توجد قوالب — أضف اشتراكك الشهري الأول'))
              ]);
            }
            final items = paginateLocal(
                rows, _page);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(
                  height: AppSpacing.sm),
              itemBuilder: (context, i) {
                if (i >= items.length) {
                  return AppPagination(
                    page: _page,
                    total: rows.length,
                    onGo: _go,
                  );
                }
                final t = items[i];
                final active =
                    (t['status'] as String?) ==
                        'APPROVED';
                final amount = t['amount'] is num
                    ? (t['amount'] as num).toDouble()
                    : 0.0;
                return AppCard(
                  padding: const EdgeInsets.all(
                      AppSpacing.md),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                                (t['title'] as String?) ??
                                    '',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall),
                          ),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2),
                            decoration: BoxDecoration(
                              color: (active
                                      ? Colors.green
                                      : Colors.grey)
                                  .withValues(
                                      alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(
                                      8),
                            ),
                            child: Text(
                                active
                                    ? 'نشط'
                                    : 'موقوف',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: active
                                        ? Colors.green
                                        : Colors.grey,
                                    fontWeight:
                                        FontWeight.bold)),
                          ),
                        ],
                      ),
                      Text(
                        '${AppFormat.money(amount)} • ${Frequencies.labelOf((t['frequency'] as String?) ?? '')} • يوم ${t['day_of_due'] ?? '—'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall,
                      ),
                      Text(
                        'التالي: ${t['next_due_date'] ?? '—'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: Colors.grey),
                        textDirection:
                            TextDirection.ltr,
                      ),
                      if (active && canCreate)
                        Align(
                          alignment:
                              AlignmentDirectional
                                  .centerEnd,
                          child: TextButton(
                            onPressed: () =>
                                _stop(t['id'] as String),
                            child: const Text(
                                'إيقاف القالب',
                                style: TextStyle(
                                    color: Colors.red)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// فورم قالب متكرر جديد.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key});

  @override
  ConsumerState<RecurringFormScreen> createState() =>
      _RecurringFormScreenState();
}

class _RecurringFormScreenState
    extends ConsumerState<RecurringFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _day = TextEditingController(text: '1');
  final _party = TextEditingController();
  final _notes = TextEditingController();
  String? _categoryId;
  String? _paymentId;
  String? _warehouseId;
  String _frequency = Frequencies.monthly;
  DateTime _start = DateTime.now();
  DateTime? _end;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _day.dispose();
    _party.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (p != null && mounted) setState(() => _start = p);
  }

  Future<void> _pickEnd() async {
    final p = await showDatePicker(
      context: context,
      initialDate:
          _end ?? _start.add(const Duration(days: 365)),
      firstDate: _start,
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (p != null && mounted) setState(() => _end = p);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختر التصنيف.')));
      return;
    }
    final day = int.tryParse(_day.text.trim()) ?? 0;
    if (day < 1 || day > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('يوم الاستحقاق من 1 لـ 31.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final s = DateTime(_start.year, _start.month, _start.day);
      await ref.read(expensesRepositoryProvider).createTemplate({
        'category_id': _categoryId,
        'title': _title.text.trim(),
        'amount': double.parse(_amount.text.trim()),
        'frequency': _frequency,
        'day_of_due': day,
        'start_date':
            s.toIso8601String().substring(0, 10),
        'end_date': _end == null
            ? null
            : DateTime(_end!.year, _end!.month, _end!.day)
                .toIso8601String()
                .substring(0, 10),
        'next_due_date':
            s.toIso8601String().substring(0, 10),
        'payment_method_id': _paymentId,
        'party_name': _party.text.trim().isEmpty
            ? null
            : _party.text.trim(),
        'warehouse_id': _warehouseId,
        'notes': _notes.text.trim().isEmpty
            ? null
            : _notes.text.trim(),
      });
      ref.invalidate(_templatesProvider);
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
                controller: _title,
                decoration: const InputDecoration(
                    labelText:
                        'الاسم * (مثال: اشتراك الإنترنت)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'اكتب الاسم'
                        : null),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: cats.when(
                    loading: () => const Center(
                        child:
                            CircularProgressIndicator()),
                    error: (e, _) =>
                        Text('تعذر التحميل: $e'),
                    data: (list) =>
                        DropdownButtonFormField<
                            String>(
                      initialValue: _categoryId,
                      decoration:
                          const InputDecoration(
                              labelText: 'التصنيف *'),
                      items: [
                        for (final c in list)
                          DropdownMenuItem(
                              value: c.id,
                              child: Text(c.display)),
                      ],
                      onChanged: (v) => setState(
                          () => _categoryId = v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType
                          .numberWithOptions(
                              decimal: true),
                      textDirection:
                          TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'المبلغ * (جنيه)'),
                      validator: (v) {
                        final d =
                            double.tryParse(
                                (v ?? '').trim());
                        if (d == null || d <= 0) {
                          return 'رقم غير صالح';
                        }
                        return null;
                      }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                      controller: _day,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'يوم الاستحقاق *'),
                      validator: (v) {
                        final d = int.tryParse(
                            (v ?? '').trim());
                        if (d == null ||
                            d < 1 ||
                            d > 31) {
                          return '1 - 31';
                        }
                        return null;
                      }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                  labelText: 'التكرار *'),
              items: [
                for (final f in Frequencies.all)
                  DropdownMenuItem(
                      value: f,
                      child: Text(
                          Frequencies.labelOf(f))),
              ],
              onChanged: (v) => setState(
                  () => _frequency = v ?? Frequencies.monthly),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickStart,
                    child: Text(
                        'البداية: ${_dfmt.format(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickEnd,
                    child: Text(_end == null
                        ? 'النهاية: مفتوحة'
                        : 'النهاية: ${_dfmt.format(_end!)}'),
                  ),
                ),
              ],
            ),
            if (_end != null)
              TextButton(
                onPressed: () =>
                    setState(() => _end = null),
                child: const Text('إلغاء تاريخ النهاية'),
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
            const SizedBox(height: 8),
            const Text(
              'المستحقات تتولد معتمدة (غير مدفوعة) ولا تعتبر مدفوعة إلا بتسجيل الدفع.',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : const Text('حفظ القالب'),
            ),
          ],
        ),
      ),
    );
  }
}
