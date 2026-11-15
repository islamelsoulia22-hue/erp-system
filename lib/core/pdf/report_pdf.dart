import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// سطر في جدول التقرير (بيان + تفاصيل + مبلغ).
class ReportPdfRow {
  final String label;
  final String sub;
  final double amount;
  const ReportPdfRow({
    required this.label,
    this.sub = '',
    required this.amount,
  });
}

/// إجمالي في صندوق الملخص.
class ReportPdfTotal {
  final String label;
  final double amount;
  final bool bold;
  const ReportPdfTotal({
    required this.label,
    required this.amount,
    this.bold = false,
  });
}

/// بيانات تقرير بنفس هوية الفاتورة (لوجو + ترويسة + جدول + إجماليات).
class ReportPdfData {
  final String title;
  final String rangeLabel;
  final DateTime generatedAt;
  final String? partnerLabel;
  final String? partnerName;
  final List<ReportPdfRow> rows;
  final List<ReportPdfTotal> totals;
  final String? notes;
  const ReportPdfData({
    required this.title,
    required this.rangeLabel,
    required this.generatedAt,
    this.partnerLabel,
    this.partnerName,
    required this.rows,
    required this.totals,
    this.notes,
  });
}

final NumberFormat _reportMoney = NumberFormat('#,##0.##', 'en_US');
String _money(double v) => _reportMoney.format(v);

String sanitizeReportFilename(String title) {
  var s = title.trim().isEmpty ? 'report' : title.trim();
  s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  s = s.replaceAll(RegExp(r'\s+'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  if (s.length > 80) s = s.substring(0, 80);
  if (s.isEmpty) s = 'report';
  return '$s.pdf';
}

/// معاينة التقرير بنفس شكل الفاتورة داخل التطبيق.
class ReportPreview extends StatelessWidget {
  final ReportPdfData data;
  const ReportPreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return _ReportDoc(
      data: data,
      logoProvider: const AssetImage('assets/logo.png'),
    );
  }
}

/// مشاركة التقرير PDF بنفس آلية الفاتورة (تصوير الويدجت عربي سليم).
Future<void> shareReportPdf(
    BuildContext context, ReportPdfData data) async {
  final overlay = Overlay.of(context);
  final boundaryKey = GlobalKey();
  const logoProvider = AssetImage('assets/logo.png');
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      top: -10000,
      child: Material(
        color: Colors.white,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 720,
            child: _ReportDoc(
                data: data, logoProvider: logoProvider),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    try {
      await precacheImage(logoProvider, context)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      debugPrint('reportPdf: logo precache timeout');
    } catch (e) {
      debugPrint('reportPdf: logo precache failed: $e');
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;

    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw StateError('تعذر تجهيز التقرير للمشاركة.');
    }
    final pixelRatio = data.rows.length <= 20
        ? 2.5
        : data.rows.length <= 50
            ? 2.0
            : 1.5;
    ui.Image image;
    try {
      image = await ro.toImage(pixelRatio: pixelRatio);
    } catch (e) {
      debugPrint('reportPdf: toImage failed: $e, retry 1.0');
      image = await ro.toImage(pixelRatio: 1.0);
    }
    try {
      final pages = await _paginateImage(image);
      if (pages.isEmpty) {
        throw StateError('تعذر تجهيز التقرير للمشاركة.');
      }
      final pdf = pw.Document();
      for (final pageBytes in pages) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            build: (_) => pw.Image(
              pw.MemoryImage(pageBytes),
              fit: pw.BoxFit.contain,
            ),
          ),
        );
      }
      final saved = await pdf.save();
      await Printing.sharePdf(
        bytes: saved,
        filename: sanitizeReportFilename(
            '${data.title}_${data.rangeLabel}'),
      );
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

Future<List<Uint8List>> _paginateImage(ui.Image image) async {
  const marginPt = 24.0;
  final usableW = PdfPageFormat.a4.width - marginPt * 2;
  final usableH = PdfPageFormat.a4.height - marginPt * 2;
  final sliceAspect = usableW / usableH;
  final sliceSrcH =
      (image.width / sliceAspect).round().clamp(1, image.height);
  final pages = <Uint8List>[];
  var dy = 0;
  while (dy < image.height) {
    final h =
        (dy + sliceSrcH > image.height) ? image.height - dy : sliceSrcH;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, dy.toDouble(), image.width.toDouble(), h.toDouble()),
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), h.toDouble()),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final slice = await picture.toImage(image.width, h);
    final bytes = await slice.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    slice.dispose();
    if (bytes != null) {
      pages.add(bytes.buffer.asUint8List());
    }
    dy += h;
  }
  return pages;
}

class _ReportDoc extends StatelessWidget {
  final ReportPdfData data;
  final ImageProvider logoProvider;
  const _ReportDoc({required this.data, required this.logoProvider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        // لون الخط أسود ثابت في الـ PDF مهما كان ثيم التطبيق.
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.black),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image(
                    image: logoProvider,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.business_outlined,
                      size: 36,
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SANAD — سند',
                          textDirection: ui.TextDirection.ltr,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(data.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(data.rangeLabel,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(
                      DateFormat('yyyy/MM/dd').format(data.generatedAt),
                      textDirection: ui.TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.black87),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (data.partnerName != null)
              _MetaRow(
                  label: data.partnerLabel ?? 'الطرف',
                  value: data.partnerName!),
            const SizedBox(height: 16),
            Table(
              border: TableBorder.all(color: Colors.grey.shade400),
              columnWidths: const {
                0: FlexColumnWidth(2.4),
                1: FlexColumnWidth(2.2),
                2: FlexColumnWidth(1.4),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade200),
                  children: const [
                    _Cell('البيان', header: true),
                    _Cell('التفاصيل', header: true),
                    _Cell('المبلغ', header: true),
                  ],
                ),
                if (data.rows.isEmpty)
                  const TableRow(children: [
                    _Cell('لا توجد حركات في الفترة'),
                    _Cell('-'),
                    _Cell('-'),
                  ]),
                for (final r in data.rows)
                  TableRow(children: [
                    _Cell(r.label),
                    _Cell(r.sub.isEmpty ? '-' : r.sub),
                    _Cell(_money(r.amount)),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                width: 260,
                child: Column(
                  children: [
                    for (final t in data.totals) ...[
                      _TotalRow(
                          label: t.label,
                          value: _money(t.amount),
                          bold: t.bold),
                      if (t != data.totals.last)
                        const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ),
            if (data.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text('ملاحظات: ${data.notes}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.black87)),
            ],
            const SizedBox(height: 16),
            Center(
              child: Text('SANAD — سند',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey)),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13), softWrap: true)),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool header;
  const _Cell(this.text, {this.header = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        softWrap: true,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: header ? 12 : 11,
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _TotalRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value,
              textDirection: ui.TextDirection.ltr, style: style),
        ],
      ),
    );
  }
}
