import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/errors/failures.dart';
import '../../../../core/pdf/report_pdf.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/date_filter.dart';
import '../../../customers/data/customers_repository.dart';
import '../../../shipping/domain/shipping.dart' show Payment;
import '../../../suppliers/data/suppliers_repository.dart';
import '../../data/reports_repository.dart';

final _dfmt = DateFormat('yyyy/MM/dd');

enum ReportPeriod { day, week, month, quarter, year, custom }

String _periodName(ReportPeriod p) {
  return switch (p) {
    ReportPeriod.day => 'يومي',
    ReportPeriod.week => 'أسبوعي',
    ReportPeriod.month => 'شهري',
    ReportPeriod.quarter => 'ربع سنوي',
    ReportPeriod.year => 'سنوي',
    ReportPeriod.custom => 'مخصص',
  };
}

/// [from, to] شاملين. الأسبوع يبدأ السبت.
({DateTime from, DateTime to, String label}) rangeFor(
    ReportPeriod p, DateTime anchor) {
  final a = DateTime(anchor.year, anchor.month, anchor.day);
  switch (p) {
    case ReportPeriod.day:
      return (from: a, to: a, label: _dfmt.format(a));
    case ReportPeriod.week:
      final start = a.subtract(Duration(days: (a.weekday + 1) % 7));
      final end = start.add(const Duration(days: 6));
      return (
        from: start,
        to: end,
        label: '${_dfmt.format(start)} → ${_dfmt.format(end)}'
      );
    case ReportPeriod.month:
      final start = DateTime(a.year, a.month, 1);
      final end = DateTime(a.year, a.month + 1, 0);
      return (
        from: start,
        to: end,
        label: '${a.year}/${a.month.toString().padLeft(2, '0')}'
      );
    case ReportPeriod.quarter:
      final q = (a.month - 1) ~/ 3;
      final start = DateTime(a.year, q * 3 + 1, 1);
      final end = DateTime(a.year, q * 3 + 4, 0);
      return (
        from: start,
        to: end,
        label: 'ربع ${q + 1} • ${a.year}'
      );
    case ReportPeriod.year:
      return (
        from: DateTime(a.year, 1, 1),
        to: DateTime(a.year, 12, 31),
        label: '${a.year}'
      );
    case ReportPeriod.custom:
      return (from: a, to: a, label: _dfmt.format(a));
  }
}

DateTime shiftAnchor(ReportPeriod p, DateTime anchor, int dir) {
  switch (p) {
    case ReportPeriod.day:
    case ReportPeriod.custom:
      return anchor.add(Duration(days: dir));
    case ReportPeriod.week:
      return anchor.add(Duration(days: 7 * dir));
    case ReportPeriod.month:
      return DateTime(anchor.year, anchor.month + dir, 1);
    case ReportPeriod.quarter:
      return DateTime(anchor.year, anchor.month + 3 * dir, 1);
    case ReportPeriod.year:
      return DateTime(anchor.year + dir, 1, 1);
  }
}

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'مالية'),
                Tab(text: 'الأرباح'),
                Tab(text: 'عميل'),
                Tab(text: 'مورد'),
                Tab(text: 'عام'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _FinanceTab(),
                _ProfitsTab(),
                _CustomerTab(),
                _SupplierTab(),
                _GeneralTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- مشترك: اختيار الفترة ----------

class _PeriodBar extends StatelessWidget {
  final ReportPeriod period;
  final DateTime anchor;
  final String label;
  final ValueChanged<ReportPeriod> onPeriod;
  final ValueChanged<DateTime> onAnchor;
  final List<ReportPeriod> periods;
  const _PeriodBar({
    required this.period,
    required this.anchor,
    required this.label,
    required this.onPeriod,
    required this.onAnchor,
    this.periods = const [
      ReportPeriod.day,
      ReportPeriod.week,
      ReportPeriod.month,
      ReportPeriod.quarter,
      ReportPeriod.year,
      ReportPeriod.custom,
    ],
  });

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) onAnchor(picked);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in periods)
                ChoiceChip(
                  label: Text(_periodName(p)),
                  selected: period == p,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onPeriod(p),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IconButton(
                tooltip: 'السابق',
                icon: const Icon(Icons.chevron_right_outlined),
                onPressed: () =>
                    onAnchor(shiftAnchor(period, anchor, -1)),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(context),
                  child: Text(label,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              IconButton(
                tooltip: 'التالي',
                icon: const Icon(Icons.chevron_left_outlined),
                onPressed: () =>
                    onAnchor(shiftAnchor(period, anchor, 1)),
              ),
              TextButton(
                onPressed: () => onAnchor(DateTime.now()),
                child: const Text('اليوم'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SumCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _SumCard(
      {required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(height: 4),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
            Text(AppFormat.money(value),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall),
          ],
        ),
      ),
    );
  }
}

class _PdfButtons extends StatelessWidget {
  final VoidCallback onPreview;
  final VoidCallback onShare;
  const _PdfButtons(
      {required this.onPreview, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.visibility_outlined,
                size: 18),
            label: const Text('معاينة'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.picture_as_pdf_outlined,
                size: 18),
            label: const Text('PDF'),
          ),
        ),
      ],
    );
  }
}

void showReportPreview(
    BuildContext context, ReportPdfData data) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(data.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium),
                  ),
                  IconButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.grey.shade300),
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ReportPreview(data: data),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------- تبويب مالية ----------

class _FinData {
  final List<ReportInvoice> sales;
  final List<ReportInvoice> purch;
  final List<Payment> payments;
  final double paidIn;
  final double paidOut;
  final List<Map<String, dynamic>> returns;
  final double returnsTotal;
  const _FinData({
    required this.sales,
    required this.purch,
    required this.payments,
    required this.paidIn,
    required this.paidOut,
    this.returns = const [],
    this.returnsTotal = 0,
  });

  List<Payment> get collections =>
      payments.where((p) => p.salesInvoiceId != null).toList();
  List<Payment> get payouts =>
      payments.where((p) => p.purchaseInvoiceId != null).toList();
}

class _FinanceTab extends ConsumerStatefulWidget {
  const _FinanceTab();
  @override
  ConsumerState<_FinanceTab> createState() =>
      _FinanceTabState();
}

class _FinanceTabState
    extends ConsumerState<_FinanceTab> {
  ReportPeriod _period = ReportPeriod.day;
  DateTime _anchor = DateTime.now();
  bool _loading = true;
  _FinData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = rangeFor(_period, _anchor);
      final repo = ref.read(reportsRepositoryProvider);
      final sales =
          await repo.approvedSales(from: r.from, to: r.to);
      final purch = await repo.approvedPurchases(
          from: r.from, to: r.to);
      final pays = await repo.paymentsInRange(
          from: r.from, to: r.to);
      final rets = await repo.salesReturnDocs(
          from: r.from, to: r.to);
      var paidIn = 0.0;
      var paidOut = 0.0;
      for (final p in pays) {
        if (p.salesInvoiceId != null) {
          paidIn += p.amount;
        } else if (p.purchaseInvoiceId != null) {
          paidOut += p.amount;
        }
      }
      var returnsTotal = 0.0;
      for (final x in rets) {
        final v = x['grand_total'];
        returnsTotal +=
            v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _data = _FinData(
            sales: sales,
            purch: purch,
            payments: pays,
            paidIn: paidIn,
            paidOut: paidOut,
            returns: rets,
            returnsTotal: returnsTotal);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppFailure
            ? e.messageAr
            : 'تعذر تحميل التقرير.';
        _loading = false;
      });
    }
  }

  void _reload() => _load();

  double _sum(List<ReportInvoice> l) =>
      l.fold(0, (s, e) => s + e.total);

  static double _retVal(Map<String, dynamic> x) {
    final v = x['grand_total'];
    return v is num
        ? v.toDouble()
        : double.tryParse('$v') ?? 0;
  }

  ReportPdfData _pdfData() {
    final r = rangeFor(_period, _anchor);
    final d = _data;
    final salesTotal = d == null ? 0.0 : _sum(d.sales);
    final purchTotal = d == null ? 0.0 : _sum(d.purch);
    final returnsTotal = d?.returnsTotal ?? 0;
    final netSales = salesTotal - returnsTotal;
    final rows = <ReportPdfRow>[];
    double retInRange(DateTime f, DateTime t) =>
        (d?.returns ?? [])
            .where((x) {
              final dt = DateTime.tryParse(
                      '${x['created_at']}') ??
                  DateTime.now();
              return !dt.isBefore(f) && dt.isBefore(t);
            })
            .fold(0.0, (s, x) => s + _retVal(x));
    double payInRange(DateTime f, DateTime t) =>
        (d?.payments ?? [])
            .where((p) =>
                p.salesInvoiceId != null &&
                !p.date.isBefore(f) &&
                p.date.isBefore(t))
            .fold(0.0, (s, e) => s + e.amount);
    double payOutRange(DateTime f, DateTime t) =>
        (d?.payments ?? [])
            .where((p) =>
                p.purchaseInvoiceId != null &&
                !p.date.isBefore(f) &&
                p.date.isBefore(t))
            .fold(0.0, (s, e) => s + e.amount);
    if (_period == ReportPeriod.day) {
      for (final s in d?.sales ?? []) {
        rows.add(ReportPdfRow(
            label: 'مبيعات ${s.number}',
            sub: s.partner,
            amount: s.total));
      }
      for (final s in d?.purch ?? []) {
        rows.add(ReportPdfRow(
            label: 'مشتريات ${s.number}',
            sub: s.partner,
            amount: s.total));
      }
      for (final x in d?.returns ?? []) {
        final c = x['customers'];
        rows.add(ReportPdfRow(
            label: 'مرتجع ${x['return_number'] ?? ''}',
            sub: c is Map
                ? ('${c['name'] ?? ''}')
                : '',
            amount: -(_retVal(x))));
      }
      for (final p in d?.collections ?? []) {
        rows.add(ReportPdfRow(
            label: 'تحصيل ${p.number}',
            sub:
                '${p.partnerName ?? ''} • ${p.invoiceNumber ?? ''} • ${p.methodCode ?? ''}',
            amount: p.amount));
      }
      for (final p in d?.payouts ?? []) {
        rows.add(ReportPdfRow(
            label: 'مدفوعة ${p.number}',
            sub:
                '${p.partnerName ?? ''} • ${p.invoiceNumber ?? ''} • ${p.methodCode ?? ''}',
            amount: p.amount));
      }
    } else if (_period == ReportPeriod.week) {
      for (var i = 0; i < 7; i++) {
        final day = r.from.add(Duration(days: i));
        final next = day.add(const Duration(days: 1));
        final ds = (d?.sales ?? [])
            .where((e) => _sameDay(e.date, day))
            .fold(0.0, (s, e) => s + e.total);
        final dp = (d?.purch ?? [])
            .where((e) => _sameDay(e.date, day))
            .fold(0.0, (s, e) => s + e.total);
        final pi = payInRange(day, next);
        final po = payOutRange(day, next);
        final rt = retInRange(day, next);
        rows.add(ReportPdfRow(
            label: _dfmt.format(day),
            sub:
                'مبيعات ${ds.toStringAsFixed(0)} • مرتجع ${rt.toStringAsFixed(0)} • مشتريات ${dp.toStringAsFixed(0)} • تحصيل ${pi.toStringAsFixed(0)} • مدفوع ${po.toStringAsFixed(0)}',
            amount: ds - rt - dp));
      }
    } else {
      var start = r.from;
      var w = 1;
      while (!start.isAfter(r.to)) {
        var end = start.add(const Duration(days: 6));
        if (end.isAfter(r.to)) end = r.to;
        final lim = end.add(const Duration(days: 1));
        final ds = (d?.sales ?? [])
            .where((e) =>
                !e.date.isBefore(start) && e.date.isBefore(lim))
            .fold(0.0, (s, e) => s + e.total);
        final dp = (d?.purch ?? [])
            .where((e) =>
                !e.date.isBefore(start) && e.date.isBefore(lim))
            .fold(0.0, (s, e) => s + e.total);
        final pi = payInRange(start, lim);
        final po = payOutRange(start, lim);
        final rt = retInRange(start, lim);
        rows.add(ReportPdfRow(
            label: 'الأسبوع $w',
            sub:
                '${_dfmt.format(start)} → ${_dfmt.format(end)} • مرتجع ${rt.toStringAsFixed(0)} • تحصيل ${pi.toStringAsFixed(0)} • مدفوع ${po.toStringAsFixed(0)}',
            amount: ds - rt - dp));
        start = end.add(const Duration(days: 1));
        w++;
      }
    }
    return ReportPdfData(
      title: 'تقرير مالي ${_periodName(_period)}',
      rangeLabel: r.label,
      generatedAt: DateTime.now(),
      rows: rows,
      totals: [
        ReportPdfTotal(
            label: 'إجمالي المبيعات (قبل المرتجع)',
            amount: salesTotal),
        ReportPdfTotal(
            label: 'المرتجعات',
            amount: returnsTotal),
        ReportPdfTotal(
            label: 'صافي المبيعات',
            amount: netSales,
            bold: true),
        ReportPdfTotal(
            label: 'إجمالي المشتريات',
            amount: purchTotal),
        ReportPdfTotal(label: 'المحصل', amount: d?.paidIn ?? 0),
        ReportPdfTotal(
            label: 'المدفوع للموردين',
            amount: d?.paidOut ?? 0),
        ReportPdfTotal(
            label: 'الصافي',
            amount: netSales - purchTotal,
            bold: true),
      ],
      notes: 'الفواتير المعتمدة فقط. المرتجعات مخصومة من المبيعات والصافي.',
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final r = rangeFor(_period, _anchor);
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding:
            EdgeInsets.all(context.contentPadding),
        children: [
          _PeriodBar(
            period: _period,
            anchor: _anchor,
            label: r.label,
            periods: const [
              ReportPeriod.day,
              ReportPeriod.week,
              ReportPeriod.month
            ],
            onPeriod: (p) => setState(() {
              _period = p;
              _reload();
            }),
            onAnchor: (a) => setState(() {
              _anchor = a;
              _reload();
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const LoadingSkeleton(rows: 5)
          else if (_error != null)
            ErrorState(message: _error!)
          else ...[
            Row(
              children: [
                _SumCard(
                    label: 'مبيعات (صافي)',
                    value: _sum(_data!.sales) -
                        _data!.returnsTotal,
                    color: AppColors.success),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'مشتريات',
                    value: _sum(_data!.purch),
                    color: AppColors.info),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'الصافي',
                    value: _sum(_data!.sales) -
                        _data!.returnsTotal -
                        _sum(_data!.purch),
                    color: AppColors.primary),
              ],
            ),
            if (_data!.returnsTotal > 0)
              Padding(
                padding:
                    const EdgeInsets.only(top: 4),
                child: Text(
                  'شامل خصم مرتجعات: ${AppFormat.money(_data!.returnsTotal)}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _SumCard(
                    label: 'محصل',
                    value: _data!.paidIn,
                    color: Colors.teal),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'مدفوع للموردين',
                    value: _data!.paidOut,
                    color: Colors.orange),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'فواتير',
                    value: (_data!.sales.length +
                            _data!.purch.length)
                        .toDouble(),
                    color: Colors.grey),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _PdfButtons(
              onPreview: () =>
                  showReportPreview(context, _pdfData()),
              onShare: () => shareReportPdf(
                  context, _pdfData()),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_period == ReportPeriod.day) ...[
              const SectionHeader(title: 'فواتير المبيعات'),
              for (final s in _data!.sales)
                _InvTile(
                  number: s.number,
                  sub:
                      '${s.partner} • ${_dfmt.format(s.date)}',
                  total: s.total,
                  route: '/sales/${s.id}',
                ),
              if (_data!.sales.isEmpty)
                const Text('لا توجد مبيعات في اليوم.',
                    style: TextStyle(color: Colors.grey)),
              const SizedBox(height: AppSpacing.sm),
              const SectionHeader(
                  title: 'مرتجعات المبيعات'),
              for (final x in _data!.returns)
                _InvTile(
                  number:
                      '${x['return_number'] ?? ''}',
                  sub:
                      '${(x['customers'] is Map ? (x['customers'] as Map)['name'] ?? '' : '')} • ${_dfmt.format(DateTime.tryParse('${x['created_at']}') ?? DateTime.now())}',
                  total: -_retVal(x),
                  route: '/sales-returns/${x['id']}',
                ),
              if (_data!.returns.isEmpty)
                const Text('لا توجد مرتجعات في اليوم.',
                    style: TextStyle(color: Colors.grey)),
              const SizedBox(height: AppSpacing.sm),
              const SectionHeader(
                  title: 'فواتير المشتريات'),
              for (final s in _data!.purch)
                _InvTile(
                  number: s.number,
                  sub:
                      '${s.partner} • ${_dfmt.format(s.date)}',
                  total: s.total,
                  route: '/purchase-invoices/${s.id}',
                ),
              if (_data!.purch.isEmpty)
                const Text(
                    'لا توجد مشتريات في اليوم.',
                    style: TextStyle(color: Colors.grey)),
              const SizedBox(height: AppSpacing.sm),
              const SectionHeader(title: 'التحصيلات'),
              for (final p in _data!.collections)
                _PayTile(payment: p),
              if (_data!.collections.isEmpty)
                const Text('لا توجد تحصيلات في اليوم.',
                    style: TextStyle(color: Colors.grey)),
              const SizedBox(height: AppSpacing.sm),
              const SectionHeader(
                  title: 'المدفوعات للموردين'),
              for (final p in _data!.payouts)
                _PayTile(payment: p),
              if (_data!.payouts.isEmpty)
                const Text(
                    'لا توجد مدفوعات في اليوم.',
                    style: TextStyle(color: Colors.grey)),
            ] else ...[
              SectionHeader(
                  title: _period == ReportPeriod.week
                      ? 'التفصيل اليومي'
                      : 'التفصيل الأسبوعي'),
              for (final row
                  in _pdfData().rows.take(31))
                AppCard(
                  padding: const EdgeInsets.all(
                      AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(row.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall),
                            Text(row.sub,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall),
                          ],
                        ),
                      ),
                      Text(AppFormat.money(row.amount),
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PayTile extends StatelessWidget {
  final Payment payment;
  const _PayTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final isIn = payment.salesInvoiceId != null;
    final sub = [
      _dfmt.format(payment.date),
      if ((payment.partnerName ?? '').isNotEmpty)
        payment.partnerName!,
      if ((payment.invoiceNumber ?? '').isNotEmpty)
        'فاتورة ${payment.invoiceNumber}',
      if ((payment.methodCode ?? '').isNotEmpty)
        payment.methodCode!,
    ].join(' • ');
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(
              isIn
                  ? Icons.arrow_downward_outlined
                  : Icons.arrow_upward_outlined,
              color: isIn ? Colors.green : Colors.orange,
              size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(payment.number,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall),
                Text(sub,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(AppFormat.money(payment.amount),
              style:
                  Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _InvTile extends StatelessWidget {  final String number;
  final String sub;
  final double total;
  final String route;
  const _InvTile({
    required this.number,
    required this.sub,
    required this.total,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push(route),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(number,
                    textDirection:
                        TextDirection.ltr,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall),
                Text(sub,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(AppFormat.money(total),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge),
        ],
      ),
    );
  }
}

// ---------- تبويب عميل ----------

class _StmtData {
  final List<ReportInvoice> invoices;
  final Map<String, double> paidByInvoice;
  final List<Payment> payments;
  const _StmtData(
      {required this.invoices,
      required this.paidByInvoice,
      required this.payments});

  double get invoiced =>
      invoices.fold(0, (s, e) => s + e.total);
  double get paid =>
      paidByInvoice.values.fold(0, (s, e) => s + e);
  double get remaining => invoiced - paid;
}

class _CustomerTab extends ConsumerStatefulWidget {
  const _CustomerTab();
  @override
  ConsumerState<_CustomerTab> createState() =>
      _CustomerTabState();
}

class _CustomerTabState
    extends ConsumerState<_CustomerTab> {
  ReportPeriod _period = ReportPeriod.month;
  DateTime _anchor = DateTime.now();
  String? _customerId;
  String? _customerName;
  bool _loading = false;
  _StmtData? _data;
  String? _error;

  Future<void> _pickCustomer() async {
    final q = TextEditingController();
    List<dynamic> results = [];
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom +
                      16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختيار عميل',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration:
                            const InputDecoration(
                                labelText: 'بحث'))),
                IconButton(
                  icon:
                      const Icon(Icons.search_outlined),
                  onPressed: () async {
                    results = await ref
                        .read(customersRepositoryProvider)
                        .search(
                            query: q.text, pageSize: 20);
                    setS(() {});
                  },
                ),
              ]),
              for (final c in results)
                ListTile(
                  title: Text(c.name),
                  subtitle: Text(c.code),
                  onTap: () {
                    setState(() {
                      _customerId = c.id as String;
                      _customerName = c.name as String;
                    });
                    Navigator.of(ctx).pop();
                    _load();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    if (_customerId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = rangeFor(_period, _anchor);
      final repo = ref.read(reportsRepositoryProvider);
      final inv = await repo.approvedSales(
          from: r.from, to: r.to, customerId: _customerId);
      final pays = await repo.paymentsForSales(
          [for (final i in inv) i.id]);
      final map = <String, double>{};
      for (final p in pays) {
        final id = p.salesInvoiceId;
        if (id == null) continue;
        map[id] = (map[id] ?? 0) + p.amount;
      }
      if (!mounted) return;
      setState(() {
        _data = _StmtData(
            invoices: inv,
            paidByInvoice: map,
            payments: pays);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppFailure
            ? e.messageAr
            : 'تعذر تحميل الكشف.';
        _loading = false;
      });
    }
  }

  ReportPdfData _pdfData() {
    final r = rangeFor(_period, _anchor);
    final d = _data;
    return ReportPdfData(
      title: 'كشف حساب عميل ${_periodName(_period)}',
      rangeLabel: r.label,
      generatedAt: DateTime.now(),
      partnerLabel: 'العميل',
      partnerName: _customerName ?? '—',
      rows: [
        for (final s in d?.invoices ?? [])
          ReportPdfRow(
              label: s.number,
              sub:
                  '${_dfmt.format(s.date)} • مدفوع ${(d?.paidByInvoice[s.id] ?? 0).toStringAsFixed(0)}',
              amount: s.total),
        for (final p in d?.payments ?? [])
          ReportPdfRow(
              label: 'تحصيل ${p.number}',
              sub:
                  '${_dfmt.format(p.date)} • ${p.invoiceNumber ?? ''} • ${p.methodCode ?? ''}',
              amount: p.amount),
      ],
      totals: [
        ReportPdfTotal(
            label: 'إجمالي الفواتير',
            amount: d?.invoiced ?? 0),
        ReportPdfTotal(
            label: 'المدفوع', amount: d?.paid ?? 0),
        ReportPdfTotal(
            label: 'المتبقي',
            amount: d?.remaining ?? 0,
            bold: true),
      ],
      notes: 'الفواتير المعتمدة في الفترة + إجمالي المدفوع عليها.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rangeFor(_period, _anchor);
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding:
            EdgeInsets.all(context.contentPadding),
        children: [
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.person_outline,
                  size: 20),
              title: Text(_customerName ?? 'اختيار العميل'),
              trailing: TextButton(
                  onPressed: _pickCustomer,
                  child: const Text('اختيار')),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _PeriodBar(
            period: _period,
            anchor: _anchor,
            label: r.label,
            periods: const [
              ReportPeriod.day,
              ReportPeriod.week,
              ReportPeriod.month,
              ReportPeriod.quarter,
              ReportPeriod.year,
            ],
            onPeriod: (p) => setState(() {
              _period = p;
              _load();
            }),
            onAnchor: (a) => setState(() {
              _anchor = a;
              _load();
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_customerId == null)
            const EmptyState(
              icon: Icons.person_search_outlined,
              title: 'اختر عميلا لعرض كشفه',
            )
          else if (_loading)
            const LoadingSkeleton(rows: 5)
          else if (_error != null)
            ErrorState(message: _error!)
          else ...[
            Row(
              children: [
                _SumCard(
                    label: 'الفواتير',
                    value: _data!.invoiced,
                    color: AppColors.info),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'المدفوع',
                    value: _data!.paid,
                    color: AppColors.success),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'المتبقي',
                    value: _data!.remaining,
                    color: AppColors.primary),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _PdfButtons(
              onPreview: () =>
                  showReportPreview(context, _pdfData()),
              onShare: () => shareReportPdf(
                  context, _pdfData()),
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionHeader(title: 'الفواتير'),
            for (final s in _data!.invoices)
              _InvTile(
                number: s.number,
                sub:
                    '${_dfmt.format(s.date)} • مدفوع ${AppFormat.money(_data!.paidByInvoice[s.id] ?? 0)} • متبقي ${AppFormat.money(s.total - (_data!.paidByInvoice[s.id] ?? 0))}',
                total: s.total,
                route: '/sales/${s.id}',
              ),
            if (_data!.invoices.isEmpty)
              const Text('لا توجد فواتير في الفترة.',
                  style: TextStyle(color: Colors.grey)),
            const SizedBox(height: AppSpacing.sm),
            const SectionHeader(title: 'التحصيلات'),
            for (final p in _data!.payments)
              _PayTile(payment: p),
            if (_data!.payments.isEmpty)
              const Text('لا توجد تحصيلات.',
                  style: TextStyle(color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

// ---------- تبويب مورد ----------

class _SupplierTab extends ConsumerStatefulWidget {
  const _SupplierTab();
  @override
  ConsumerState<_SupplierTab> createState() =>
      _SupplierTabState();
}

class _SupplierTabState
    extends ConsumerState<_SupplierTab> {
  ReportPeriod _period = ReportPeriod.month;
  DateTime _anchor = DateTime.now();
  String? _supplierId;
  String? _supplierName;
  bool _loading = false;
  _StmtData? _data;
  String? _error;

  // ignore: duplicate_code
  Future<void> _pickSupplier() async {
    final q = TextEditingController();
    List<dynamic> results = [];
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom +
                      16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختيار مورد',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration:
                            const InputDecoration(
                                labelText: 'بحث'))),
                IconButton(
                  icon:
                      const Icon(Icons.search_outlined),
                  onPressed: () async {
                    results = await ref
                        .read(suppliersRepositoryProvider)
                        .search(
                            query: q.text, pageSize: 20);
                    setS(() {});
                  },
                ),
              ]),
              for (final s in results)
                ListTile(
                  title: Text(s.name as String),
                  onTap: () {
                    setState(() {
                      _supplierId = s.id as String;
                      _supplierName = s.name as String;
                    });
                    Navigator.of(ctx).pop();
                    _load();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    if (_supplierId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = rangeFor(_period, _anchor);
      final repo = ref.read(reportsRepositoryProvider);
      final inv = await repo.approvedPurchases(
          from: r.from, to: r.to, supplierId: _supplierId);
      final pays = await repo.paymentsForPurchases(
          [for (final i in inv) i.id]);
      final map = <String, double>{};
      for (final p in pays) {
        final id = p.purchaseInvoiceId;
        if (id == null) continue;
        map[id] = (map[id] ?? 0) + p.amount;
      }
      if (!mounted) return;
      setState(() {
        _data = _StmtData(
            invoices: inv,
            paidByInvoice: map,
            payments: pays);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppFailure
            ? e.messageAr
            : 'تعذر تحميل الكشف.';
        _loading = false;
      });
    }
  }

  ReportPdfData _pdfData() {
    final r = rangeFor(_period, _anchor);
    final d = _data;
    return ReportPdfData(
      title: 'كشف حساب مورد ${_periodName(_period)}',
      rangeLabel: r.label,
      generatedAt: DateTime.now(),
      partnerLabel: 'المورد',
      partnerName: _supplierName ?? '—',
      rows: [
        for (final s in d?.invoices ?? [])
          ReportPdfRow(
              label: s.number,
              sub:
                  '${_dfmt.format(s.date)} • مدفوع ${(d?.paidByInvoice[s.id] ?? 0).toStringAsFixed(0)}',
              amount: s.total),
        for (final p in d?.payments ?? [])
          ReportPdfRow(
              label: 'مدفوعة ${p.number}',
              sub:
                  '${_dfmt.format(p.date)} • ${p.invoiceNumber ?? ''} • ${p.methodCode ?? ''}',
              amount: p.amount),
      ],
      totals: [
        ReportPdfTotal(
            label: 'إجمالي الفواتير',
            amount: d?.invoiced ?? 0),
        ReportPdfTotal(
            label: 'المدفوع', amount: d?.paid ?? 0),
        ReportPdfTotal(
            label: 'المتبقي',
            amount: d?.remaining ?? 0,
            bold: true),
      ],
      notes: 'الفواتير المعتمدة في الفترة + إجمالي المدفوع عليها.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rangeFor(_period, _anchor);
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding:
            EdgeInsets.all(context.contentPadding),
        children: [
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(
                  Icons.handshake_outlined,
                  size: 20),
              title:
                  Text(_supplierName ?? 'اختيار المورد'),
              trailing: TextButton(
                  onPressed: _pickSupplier,
                  child: const Text('اختيار')),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _PeriodBar(
            period: _period,
            anchor: _anchor,
            label: r.label,
            periods: const [
              ReportPeriod.day,
              ReportPeriod.week,
              ReportPeriod.month,
              ReportPeriod.quarter,
              ReportPeriod.year,
            ],
            onPeriod: (p) => setState(() {
              _period = p;
              _load();
            }),
            onAnchor: (a) => setState(() {
              _anchor = a;
              _load();
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_supplierId == null)
            const EmptyState(
              icon: Icons.person_search_outlined,
              title: 'اختر موردا لعرض كشفه',
            )
          else if (_loading)
            const LoadingSkeleton(rows: 5)
          else if (_error != null)
            ErrorState(message: _error!)
          else ...[
            Row(
              children: [
                _SumCard(
                    label: 'الفواتير',
                    value: _data!.invoiced,
                    color: AppColors.info),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'المدفوع',
                    value: _data!.paid,
                    color: AppColors.success),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'المتبقي',
                    value: _data!.remaining,
                    color: AppColors.primary),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _PdfButtons(
              onPreview: () =>
                  showReportPreview(context, _pdfData()),
              onShare: () => shareReportPdf(
                  context, _pdfData()),
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionHeader(title: 'الفواتير'),
            for (final s in _data!.invoices)
              _InvTile(
                number: s.number,
                sub:
                    '${_dfmt.format(s.date)} • مدفوع ${AppFormat.money(_data!.paidByInvoice[s.id] ?? 0)} • متبقي ${AppFormat.money(s.total - (_data!.paidByInvoice[s.id] ?? 0))}',
                total: s.total,
                route: '/purchase-invoices/${s.id}',
              ),
            if (_data!.invoices.isEmpty)
              const Text('لا توجد فواتير في الفترة.',
                  style: TextStyle(color: Colors.grey)),
            const SizedBox(height: AppSpacing.sm),
            const SectionHeader(title: 'المدفوعات'),
            for (final p in _data!.payments)
              _PayTile(payment: p),
            if (_data!.payments.isEmpty)
              const Text('لا توجد مدفوعات.',
                  style: TextStyle(color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

// ---------- تبويب الأرباح ----------

class _BucketProfit {
  final String label;
  final String sub;
  final ProfitReport p;
  const _BucketProfit(
      {required this.label, required this.sub, required this.p});
}

class _ProfitsTab extends ConsumerStatefulWidget {
  const _ProfitsTab();
  @override
  ConsumerState<_ProfitsTab> createState() =>
      _ProfitsTabState();
}

class _ProfitsTabState
    extends ConsumerState<_ProfitsTab> {
  ReportPeriod _period = ReportPeriod.month;
  DateTime _anchor = DateTime.now();
  DateTime? _customFrom;
  DateTime? _customTo;
  bool _loading = true;
  ProfitReport? _data;
  List<_BucketProfit> _buckets = const [];
  String? _error;

  ({DateTime from, DateTime to, String label}) get _range {
    if (_period == ReportPeriod.custom) {
      final f = _customFrom ?? DateTime.now();
      final t = _customTo ?? f;
      final from = DateTime(f.year, f.month, f.day);
      final to = DateTime(t.year, t.month, t.day);
      final a = from.isAfter(to) ? to : from;
      final b = from.isAfter(to) ? from : to;
      return (
        from: a,
        to: b,
        label: '${_dfmt.format(a)} → ${_dfmt.format(b)}'
      );
    }
    return rangeFor(_period, _anchor);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = _range;
      final repo = ref.read(reportsRepositoryProvider);
      final data =
          await repo.profitRange(from: r.from, to: r.to);
      final buckets = await _loadBuckets(repo, r);
      if (!mounted) return;
      setState(() {
        _data = data;
        _buckets = buckets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppFailure
            ? e.messageAr
            : 'تعذر تحميل تقرير الأرباح.';
        _loading = false;
      });
    }
  }

  /// تقسيم المدى لوحدات (يوم/أسبوع/شهر) بحد أقصى 31 وحدة.
  Future<List<_BucketProfit>> _loadBuckets(
      ReportsRepository repo,
      ({DateTime from, DateTime to, String label}) r) async {
    final spans = <(DateTime, DateTime, String)>[];
    if (_period == ReportPeriod.day) return const [];
    if (_period == ReportPeriod.week ||
        (_period == ReportPeriod.custom &&
            r.to.difference(r.from).inDays < 14)) {
      var d = r.from;
      while (!d.isAfter(r.to)) {
        spans.add((d, d, _dfmt.format(d)));
        d = d.add(const Duration(days: 1));
      }
    } else if (_period == ReportPeriod.month ||
        (_period == ReportPeriod.custom &&
            r.to.difference(r.from).inDays < 100)) {
      var s = r.from;
      var w = 1;
      while (!s.isAfter(r.to)) {
        var e = s.add(const Duration(days: 6));
        if (e.isAfter(r.to)) e = r.to;
        spans.add((s, e, 'الأسبوع $w'));
        s = e.add(const Duration(days: 1));
        w++;
      }
    } else {
      var s = DateTime(r.from.year, r.from.month, 1);
      while (!s.isAfter(r.to)) {
        final e = DateTime(s.year, s.month + 1, 0);
        final ee = e.isAfter(r.to) ? r.to : e;
        final ss = s.isBefore(r.from) ? r.from : s;
        spans.add((
          ss,
          ee,
          '${ss.year}/${ss.month.toString().padLeft(2, '0')}'
        ));
        s = DateTime(s.year, s.month + 1, 1);
      }
    }
    final out = <_BucketProfit>[];
    for (final sp in spans.take(31)) {
      final p =
          await repo.profitRange(from: sp.$1, to: sp.$2);
      out.add(_BucketProfit(
          label: sp.$3,
          sub:
              'مبيعات ${p.salesTotal.toStringAsFixed(0)} • مرتجع ${p.returnsTotal.toStringAsFixed(0)} • تكلفة ${p.cogs.toStringAsFixed(0)} • مصروفات ${p.expenses.toStringAsFixed(0)}',
          p: p));
      if (!mounted) break;
    }
    return out;
  }

  ReportPdfData _pdfData() {
    final r = _range;
    final d = _data;
    return ReportPdfData(
      title: 'تقرير الأرباح ${_periodName(_period)}',
      rangeLabel: r.label,
      generatedAt: DateTime.now(),
      rows: [
        for (final b in _buckets)
          ReportPdfRow(
              label: b.label,
              sub: b.sub,
              amount: b.p.net),
      ],
      totals: [
        ReportPdfTotal(
            label: 'إجمالي المبيعات (قبل المرتجع)',
            amount: d?.salesTotal ?? 0),
        ReportPdfTotal(
            label: 'المرتجعات',
            amount: d?.returnsTotal ?? 0),
        ReportPdfTotal(
            label: 'الإيراد (الصافي)',
            amount: d?.revenue ?? 0,
            bold: true),
        ReportPdfTotal(
            label: 'تكلفة البضاعة المباعة',
            amount: d?.cogs ?? 0),
        ReportPdfTotal(
            label: 'صافي ربح المبيعات (بيع - شراء)',
            amount: d?.gross ?? 0,
            bold: true),
        ReportPdfTotal(
            label: 'المصروفات التشغيلية (مدفوعة)',
            amount: d?.expenses ?? 0),
        ReportPdfTotal(
            label: 'الصافي بعد المصاريف',
            amount: d?.net ?? 0,
            bold: true),
      ],
      notes:
          'صافي ربح المبيعات = (سعر البيع - الخصم) - تكلفة الشراء، بدون ضريبة وبدون مصاريف. الإيراد = المعتمد (بدون ضريبة) − المرتجع (بدون ضريبة). التكلفة = المتوسط المرجح مع رد تكلفة الراجع.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _range;
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding:
            EdgeInsets.all(context.contentPadding),
        children: [
          _PeriodBar(
            period: _period,
            anchor: _anchor,
            label: r.label,
            onPeriod: (p) => setState(() {
              _period = p;
              _load();
            }),
            onAnchor: (a) => setState(() {
              _anchor = a;
              _load();
            }),
          ),
          if (_period == ReportPeriod.custom) ...[
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: DateFilterRow(
                from: _customFrom,
                to: _customTo,
                onFrom: (v) => setState(() {
                  _customFrom = v;
                  _load();
                }),
                onTo: (v) => setState(() {
                  _customTo = v;
                  _load();
                }),
                onClear: () => setState(() {
                  _customFrom = null;
                  _customTo = null;
                  _load();
                }),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const LoadingSkeleton(rows: 5)
          else if (_error != null)
            ErrorState(message: _error!)
          else ...[
            Row(
              children: [
                _SumCard(
                    label: 'الإيراد (بدون ضريبة)',
                    value: _data!.revenue,
                    color: AppColors.success),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'التكلفة (شراء)',
                    value: _data!.cogs,
                    color: AppColors.info),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'صافي ربح المبيعات',
                    value: _data!.gross,
                    color: AppColors.primary),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _SumCard(
                    label: 'المصروفات',
                    value: _data!.expenses,
                    color: Colors.orange),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'الصافي بعد المصاريف',
                    value: _data!.net,
                    color: _data!.net >= 0
                        ? Colors.green
                        : AppColors.danger),
                const SizedBox(
                    width: AppSpacing.sm),
                _SumCard(
                    label: 'فواتير',
                    value: _data!.invoicesCount
                        .toDouble(),
                    color: Colors.grey),
              ],
            ),
            if (_data!.returnsTotal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'مرتجعات في الفترة: ${AppFormat.money(_data!.returnsTotal)} بدون ضريبة (مخصومة من الإيراد + تكلفتها راجعة للمخزن)',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            _PdfButtons(
              onPreview: () =>
                  showReportPreview(context, _pdfData()),
              onShare: () => shareReportPdf(
                  context, _pdfData()),
            ),
            if (_buckets.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const SectionHeader(title: 'التفصيل'),
              for (final b in _buckets)
                AppCard(
                  padding: const EdgeInsets.all(
                      AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(b.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall),
                            Text(b.sub,
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
                          Text(
                              AppFormat.money(b.p.gross),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                      color: b.p.gross >=
                                              0
                                          ? Colors.green
                                          : AppColors
                                              .danger)),
                          const Text('ربح المبيعات',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------- تبويب عام (المحتوى القديم) ----------

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(managerStatsProvider);
    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(managerStatsProvider),
      child: ListView(
        padding: EdgeInsets.all(context.contentPadding),
        children: [
          stats.when(
            loading: () => const LoadingSkeleton(rows: 3),
            error: (_, _) => const ErrorState(),
            data: (s) => Column(
              children: [
                Row(children: [
                  Expanded(
                      child: _tile('إجمالي المبيعات المعتمدة',
                          s.salesTotal)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _tile('إجمالي المشتريات المعتمدة',
                          s.purchasesTotal)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _count('مبيعات بانتظار الاعتماد',
                          s.pendingSales)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _count('مشتريات بانتظار الاعتماد',
                          s.pendingPurchases)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _count('أصناف منخفضة المخزون',
                          s.lowStockCount)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _count('شحنات قيد التجهيز',
                          s.pendingShipments)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(
              title: 'الأصناف منخفضة المخزون'),
          FutureBuilder(
            future:
                ref.read(reportsRepositoryProvider).lowStock(),
            builder: (context, snap) {
              final rows = snap.data ?? [];
              if (rows.isEmpty) {
                return const AppCard(
                    child: ListTile(
                        title: Text(
                            'لا توجد أصناف تحت الحد الأدنى')));
              }
              return Column(
                children: [
                  for (final r in rows)
                    AppCard(
                      child: ListTile(
                        title: Text(
                            (r['product_name'] ?? '')
                                .toString()),
                        subtitle: Text(
                            '${r['warehouse_name']} • متاح ${r['available_quantity']} / حد ${r['minimum_stock']}'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tile(String title, double value) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('${value.toStringAsFixed(2)} ج.م',
              style: const TextStyle(
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _count(String title, int value) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('$value',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}
