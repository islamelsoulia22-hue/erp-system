import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// سطر صنف في الفاتورة.
class InvoicePdfRow {
  final String name;
  final double qty;
  final double price;
  final double discount;
  final double taxRate;
  final double total;
  const InvoicePdfRow({
    required this.name,
    required this.qty,
    required this.price,
    this.discount = 0,
    this.taxRate = 0,
    required this.total,
  });
}

/// بيانات الفاتورة المطلوبة للـ PDF (مبيعات أو مشتريات).
class InvoicePdfData {
  final String title;
  final String number;
  final DateTime date;
  final String partnerLabel;
  final String partnerName;
  final String? warehouseName;
  final String? paymentLabel;
  final String? referenceNumber;
  final String? statusAr;
  final List<InvoicePdfRow> rows;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final String? notes;
  const InvoicePdfData({
    required this.title,
    required this.number,
    required this.date,
    required this.partnerLabel,
    required this.partnerName,
    this.warehouseName,
    this.paymentLabel,
    this.referenceNumber,
    this.statusAr,
    required this.rows,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    this.notes,
  });
}

// أرقام لاتينية للفواتير الرسمية (أوضح من الأرقام المشرقية).
final NumberFormat _invoiceMoney = NumberFormat('#,##0.##', 'en_US');
String _money(double v) => _invoiceMoney.format(v);

/// اسم ملف آمن: يشيل / \ : * ? " < > | و المسافات الزائدة.
String sanitizeInvoiceFilename(String number, {String ext = '.pdf'}) {
  var s = number.trim().isEmpty ? 'invoice' : number.trim();
  s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  s = s.replaceAll(RegExp(r'\s+'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  if (s.length > 80) s = s.substring(0, 80);
  if (s.isEmpty) s = 'invoice';
  return '$s$ext';
}

/// يبني الفاتورة كويدجت فلاتر (عربي سليم + لوجو + جدول) ويصورها
/// كصورة ثم يقسمها على صفحات A4 متعددة ويرجع بايتات الـ PDF.
///
/// التصوير من الويدجت يضمن تشكيل الحروف العربية صحيحا
/// (مكتبة pdf لا تدعم تشكيل العربي).
/// مشتركة بين المشاركة (واتساب/حفظ) والطباعة (حوار الطباعة)
/// عشان الزرارين يطلعوا نفس الشكل بالظبط على كل المنصات.
Future<Uint8List> buildInvoicePdfBytes(
    BuildContext context, InvoicePdfData data) async {
  final overlay = Overlay.of(context);
  final boundaryKey = GlobalKey();
  const logoProvider = AssetImage('assets/logo.png');
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      // خارج الشاشة لكن بحد معقول حتى لا يفشل layout على بعض المنصات.
      top: -10000,
      child: Material(
        color: Colors.white,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 720,
            child: _InvoiceDoc(data: data, logoProvider: logoProvider),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // نضمن تحميل اللوجو قبل الالتقاط، مع تجاهل الفشل (يوجد fallback).
    try {
      await precacheImage(logoProvider, context)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      debugPrint('invoicePdf: logo precache timeout, using fallback');
    } catch (e) {
      debugPrint('invoicePdf: logo precache failed: $e');
    }
    // إطار إضافي بعد التحميل حتى تستقر الخطوط والصور.
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;

    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw StateError('تعذر تجهيز الفاتورة للمشاركة.');
    }
    // pixelRatio تكيفي: الفواتير الطويلة تقلل الدقة لتفادي تجاوز
    // حد الـ GPU texture وحجم PNG الضخم.
    final pixelRatio = data.rows.length <= 20
        ? 2.5
        : data.rows.length <= 50
            ? 2.0
            : 1.5;
    ui.Image image;
    try {
      image = await ro.toImage(pixelRatio: pixelRatio);
    } catch (e) {
      // محاولة أخيرة بدقة أقل قبل الاستسلام.
      debugPrint('invoicePdf: toImage($pixelRatio) failed: $e, retry 1.0');
      image = await ro.toImage(pixelRatio: 1.0);
    }
    try {
      final pages = await _paginateImage(image);
      if (pages.isEmpty) {
        throw StateError('تعذر تجهيز الفاتورة للمشاركة.');
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
      return saved;
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// مشاركة الفاتورة كـ PDF (واتساب/حفظ) — نفس شكل الطباعة.
Future<void> shareInvoicePdf(
    BuildContext context, InvoicePdfData data) async {
  final saved = await buildInvoicePdfBytes(context, data);
  await Printing.sharePdf(
    bytes: saved,
    filename: sanitizeInvoiceFilename(data.number),
  );
}

/// طباعة الفاتورة عبر حوار الطباعة — شغالة على كل المنصات
/// (موبايل/لينكس/ويندوز) عكس الريسيت المباشر (لينكس فقط).
Future<void> printInvoicePdf(
    BuildContext context, InvoicePdfData data) async {
  final saved = await buildInvoicePdfBytes(context, data);
  await Printing.layoutPdf(
    onLayout: (_) async => saved,
    name: sanitizeInvoiceFilename(data.number, ext: ''),
  );
}

/// يقسم صورة الفاتورة الكاملة على شرائح كل منها بنسبة أبعاد
/// منطقة الكتابة في A4، حتى لا تنضغط الفاتورة الطويلة في صفحة واحدة.
Future<List<Uint8List>> _paginateImage(ui.Image image) async {
  const marginPt = 24.0;
  final usableW = PdfPageFormat.a4.width - marginPt * 2;
  final usableH = PdfPageFormat.a4.height - marginPt * 2;
  final sliceAspect = usableW / usableH;

  // عرض الشريحة = عرض الصورة كاملا، وارتفاعها بنسبة الصفحة.
  final sliceSrcH = (image.width / sliceAspect).round().clamp(1, image.height);
  final pages = <Uint8List>[];
  var dy = 0;
  while (dy < image.height) {
    final h =
        (dy + sliceSrcH > image.height) ? image.height - dy : sliceSrcH;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // خلفية بيضاء حتى لا تظهر مناطق شفافة سوداء في الـ PDF.
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

class _InvoiceDoc extends StatelessWidget {
  final InvoicePdfData data;
  final ImageProvider logoProvider;
  const _InvoiceDoc({required this.data, required this.logoProvider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        // لون الخط أسود ثابت في الـ PDF مهما كان ثيم التطبيق
        // (الدارك مود كان بيخلي الكتابة بيضا على خلفية بيضا).
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.black),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // الترويسة: اللوجو + الشركة + عنوان الفاتورة.
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
                    Text(data.number,
                        textDirection: ui.TextDirection.ltr,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    // تاريخ لاتيني الأرقام حتى لا يلتبس مع الأرقام المشرقية.
                    Text(
                      DateFormat('yyyy/MM/dd').format(data.date),
                      textDirection: ui.TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.black87),
                    ),
                    if (data.statusAr != null)
                      Text(data.statusAr!,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black87)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // بيانات الطرفين.
            _MetaRow(label: data.partnerLabel, value: data.partnerName),
            if (data.referenceNumber?.isNotEmpty == true)
              _MetaRow(label: 'مرجع', value: data.referenceNumber!),
            if (data.warehouseName != null)
              _MetaRow(label: 'المخزن', value: data.warehouseName!),
            if (data.paymentLabel != null)
              _MetaRow(label: 'الدفع', value: data.paymentLabel!),
            const SizedBox(height: 16),
            // جدول الأصناف بخلايا (شبه الإكسل).
            Table(
              border: TableBorder.all(color: Colors.grey.shade400),
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.2),
                4: FlexColumnWidth(1),
                5: FlexColumnWidth(1.4),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade200),
                  children: const [
                    _Cell('الصنف', header: true),
                    _Cell('الكمية', header: true),
                    _Cell('السعر', header: true),
                    _Cell('الخصم', header: true),
                    _Cell('ضريبة %', header: true),
                    _Cell('الإجمالي', header: true),
                  ],
                ),
                if (data.rows.isEmpty)
                  const TableRow(children: [
                    _Cell('لا توجد أصناف'),
                    _Cell('-'),
                    _Cell('-'),
                    _Cell('-'),
                    _Cell('-'),
                    _Cell('-'),
                  ]),
                for (final r in data.rows)
                  TableRow(children: [
                    _Cell(r.name),
                    _Cell(_money(r.qty)),
                    _Cell(_money(r.price)),
                    _Cell(_money(r.discount)),
                    _Cell(_money(r.taxRate)),
                    _Cell(_money(r.total)),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            // الإجماليات.
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                width: 260,
                child: Column(
                  children: [
                    _TotalRow(
                        label: 'الإجمالي الفرعي',
                        value: _money(data.subtotal)),
                    _TotalRow(
                        label: 'الخصم', value: _money(data.discount)),
                    _TotalRow(
                        label: 'الضريبة', value: _money(data.taxAmount)),
                    const Divider(),
                    _TotalRow(
                        label: 'الإجمالي الكلي',
                        value: _money(data.total),
                        bold: true),
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

/// نفس شكل الفاتورة المستخدم في الـ PDF لكن كويدجت عام
/// للعرض داخل التطبيق (مثل معاينة مركز الموافقات).
class InvoicePreview extends StatelessWidget {
  final InvoicePdfData data;
  const InvoicePreview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return _InvoiceDoc(
      data: data,
      logoProvider: const AssetImage('assets/logo.png'),
    );
  }
}
