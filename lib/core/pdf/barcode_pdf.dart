import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// بيانات ملصق باركود واحد: اسم الصنف + رقم الباركود.
class BarcodeLabelData {
  final String productId;
  final String productName;
  final String barcode;
  const BarcodeLabelData({
    required this.productId,
    required this.productName,
    required this.barcode,
  });
}

/// عدد الملصقات في صفحة A4 (3 أعمدة × 7 صفوف).
const _labelsPerPage = 21;

/// يطبع ملصقات باركود (اسم الصنف + صورة الباركود + الرقم).
/// يستخدم تصوير الويدجت (نفس تقنية الفواتير) عشان الاسم العربي
/// يطلع سليم + الباركود بدقة عالية قابلة للمسح.
Future<void> printBarcodeLabels(
  BuildContext context,
  List<BarcodeLabelData> items, {
  int copies = 1,
}) async {
  final clean = items
      .where((e) => e.barcode.trim().isNotEmpty)
      .toList();
  if (clean.isEmpty) {
    throw StateError('لا توجد باركودات للطباعة.');
  }
  // عدد النسخ مفتوح بدون حد أقصى — المستخدم يحدد الكمية بحرية.
  final n = copies <= 0 ? 1 : copies;
  final expanded = <BarcodeLabelData>[
    for (final it in clean)
      for (var i = 0; i < n; i++) it,
  ];

  final overlay = Overlay.of(context);
  final pdf = pw.Document();
  var pageIndex = 0;
  while (pageIndex * _labelsPerPage < expanded.length) {
    final chunk = expanded.skip(pageIndex * _labelsPerPage).take(
          _labelsPerPage,
        ).toList();
    final key = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: -10000,
        child: Material(
          color: Colors.white,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 720,
              child: _BarcodeSheetPage(items: chunk),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(
        const Duration(milliseconds: 120),
      );
      await WidgetsBinding.instance.endOfFrame;
      final ro = key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        throw StateError('تعذر تجهيز ملصقات الباركود.');
      }
      ui.Image image;
      try {
        // دقة عالية عشان خطوط الباركود تبقى حادة وتتمسح بالسكانر.
        image = await ro.toImage(pixelRatio: 3.0);
      } catch (_) {
        image = await ro.toImage(pixelRatio: 2.0);
      }
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (bytes == null) {
          throw StateError('تعذر تجهيز ملصقات الباركود.');
        }
        final png = bytes.buffer.asUint8List();
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(18),
            build: (_) => pw.Image(
              pw.MemoryImage(png),
              fit: pw.BoxFit.contain,
            ),
          ),
        );
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
    pageIndex++;
  }

  final saved = await pdf.save();
  await Printing.layoutPdf(
    onLayout: (_) async => saved,
    name: 'barcodes.pdf',
  );
}

/// مشاركة ملصقات الباركود كـ PDF (واتساب/حفظ) بدل الطباعة المباشرة.
Future<void> shareBarcodeLabels(
  BuildContext context,
  List<BarcodeLabelData> items, {
  int copies = 1,
}) async {
  final clean = items
      .where((e) => e.barcode.trim().isNotEmpty)
      .toList();
  if (clean.isEmpty) {
    throw StateError('لا توجد باركودات للطباعة.');
  }
  // عدد النسخ مفتوح بدون حد أقصى — المستخدم يحدد الكمية بحرية.
  final n = copies <= 0 ? 1 : copies;
  final expanded = <BarcodeLabelData>[
    for (final it in clean)
      for (var i = 0; i < n; i++) it,
  ];

  final overlay = Overlay.of(context);
  final pdf = pw.Document();
  var pageIndex = 0;
  while (pageIndex * _labelsPerPage < expanded.length) {
    final chunk = expanded.skip(pageIndex * _labelsPerPage).take(
          _labelsPerPage,
        ).toList();
    final key = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: -10000,
        child: Material(
          color: Colors.white,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 720,
              child: _BarcodeSheetPage(items: chunk),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(
        const Duration(milliseconds: 120),
      );
      await WidgetsBinding.instance.endOfFrame;
      final ro = key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        throw StateError('تعذر تجهيز ملصقات الباركود.');
      }
      final image = await ro.toImage(pixelRatio: 3.0);
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (bytes == null) {
          throw StateError('تعذر تجهيز ملصقات الباركود.');
        }
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(18),
            build: (_) => pw.Image(
              pw.MemoryImage(
                bytes.buffer.asUint8List(),
              ),
              fit: pw.BoxFit.contain,
            ),
          ),
        );
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
    pageIndex++;
  }
  final saved = await pdf.save();
  await Printing.sharePdf(
    bytes: saved,
    filename: 'barcodes.pdf',
  );
}

/// صفحة A4 من الملصقات (تتصور كصورة ثم تتحط في PDF).
class _BarcodeSheetPage extends StatelessWidget {
  final List<BarcodeLabelData> items;
  const _BarcodeSheetPage({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.black),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final it in items)
                _BarcodeLabel(item: it),
            ],
          ),
        ),
      ),
    );
  }
}

/// ملصق واحد: اسم الصنف + صورة الباركود + الرقم.
/// ويدجت عامة بعرض متغير — تستخدم في المعاينة والـ PDF
/// والطباعة المباشرة على طابعة الريسيت (576 نقطة = 72مم).
/// ارتفاع الباركود مضغوط (32) عشان الملصق مياخدش مساحة
/// أكبر من الليبل — ويفضل واضحا للسكانر.
class BarcodeLabelWidget extends StatelessWidget {
  final BarcodeLabelData item;
  final double width;
  final double barcodeHeight;
  final double nameFontSize;
  final double codeFontSize;
  /// إخفاء البرواز الأسود (لطباعة الليبل المباشرة TSPL/ESC-POS —
  /// يطبع الباركود والكتابة بسودا على الأبيض بدون بوكس).
  /// المعاينة والـ PDF يفضلوا بالبرواز (القيمة الافتراضية).
  final bool showBorder;
  const BarcodeLabelWidget({
    super.key,
    required this.item,
    this.width = 224,
    this.barcodeHeight = 32,
    this.nameFontSize = 13,
    this.codeFontSize = 12,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: showBorder
          ? BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 1),
              borderRadius: BorderRadius.circular(6),
            )
          : const BoxDecoration(color: Colors.white),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.productName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: nameFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: barcodeHeight,
            width: double.infinity,
            child: bw.BarcodeWidget(
              data: item.barcode.trim(),
              barcode: bw.Barcode.code128(),
              drawText: false,
              color: Colors.black,
              errorBuilder: (_, _) => const Center(
                child: Text(
                  'باركود غير صالح',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.barcode.trim(),
            textDirection: ui.TextDirection.ltr,
            style: TextStyle(
              fontSize: codeFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

/// ملصق واحد: اسم الصنف + صورة الباركود + الرقم.
class _BarcodeLabel extends StatelessWidget {
  final BarcodeLabelData item;
  const _BarcodeLabel({required this.item});

  @override
  Widget build(BuildContext context) {
    // عرض ثابت لثبات الشبكة 3 أعمدة في عرض 720.
    return BarcodeLabelWidget(item: item);
  }
}

/// معاينة ملصق واحد داخل التطبيق (قبل الطباعة).
class BarcodeLabelPreview extends StatelessWidget {
  final BarcodeLabelData item;
  const BarcodeLabelPreview({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return _BarcodeLabel(item: item);
  }
}

/// حوار معاينة: يعرض شكل الملصقات زي ما هتطبع بالظبط
/// (اسم الصنف + صورة الباركود + الرقم) مع زرار طباعة.
/// [copies] عدد النسخ لكل صنف — المعاينة تعرض أول 12 ملصق
/// فقط لو العدد أكبر عشان الحوار ميبقاش تقيل.
/// [onReceiptPrint] اختياري: زرار طباعة ريسيت USB (لينكس).
/// [showPdfButton] إظهار زرار طباعة PDF — شغال على كل
/// المنصات (موبايل/لينكس/ويندوز) عبر حوار الطباعة.
Future<void> showBarcodeLabelsPreview(
  BuildContext context,
  List<BarcodeLabelData> items, {
  int copies = 1,
  Future<void> Function()? onReceiptPrint,
  bool showPdfButton = true,
}) async {
  final clean = items
      .where((e) => e.barcode.trim().isNotEmpty)
      .toList();
  if (clean.isEmpty) return;
  // عدد النسخ مفتوح بدون حد أقصى — المستخدم يحدد الكمية بحرية.
  final n = copies <= 0 ? 1 : copies;
  final expanded = <BarcodeLabelData>[
    for (final it in clean)
      for (var i = 0; i < n; i++) it,
  ];
  const maxShow = 12;
  final shown = expanded.take(maxShow).toList();
  final hidden = expanded.length - shown.length;

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        'معاينة الطباعة (${expanded.length} ملصق)',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ده اللي هيطبع بالظبط — اتأكد إن الباركود واضح والاسم والرقم صح.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              if (onReceiptPrint != null &&
                  showPdfButton) ...[
                const SizedBox(height: 4),
                const Text(
                  'ملحوظة: زرار "طباعة" للطابعات العادية (A4) — '
                  'طابعة الريسيت ليها زرار "ريسيت".',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final it in shown)
                    BarcodeLabelPreview(item: it),
                ],
              ),
              if (hidden > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '... و$hidden ملصق كمان بنفس الشكل (عدد النسخ: $n لكل صنف)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(),
          child: const Text('إغلاق'),
        ),
        if (onReceiptPrint != null)
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(ctx).pop();
              onReceiptPrint();
            },
            icon: const Icon(
              Icons.receipt_long_outlined,
              size: 18,
            ),
            label: const Text('ريسيت'),
          ),
        if (showPdfButton)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              printBarcodeLabels(
                context,
                clean,
                copies: n,
              );
            },
            icon: const Icon(
              Icons.print_outlined,
              size: 18,
            ),
            label: const Text('طباعة'),
          ),
      ],
    ),
  );
}

/// طباعة ملصقات بمقاس XPrinter الحقيقي (ملصق = صفحة PDF).
///
/// كل ملصق يطلع صفحة PDF بمقاس الليبل بالظبط (مثلا 40×30مم) —
/// تختار طابعة XPrinter من حوار الطباعة وتطبع بمقاس فعلي 100%
/// فتطلع ملصقة لكل صنف. شغالة من **كل الأنظمة** (أندرويد/ويندوز/
/// لينكس/macOS/iOS/ويب) لأنها تستخدم تعريف الطابعة الرسمي بدل
/// الأوامر المباشرة.
///
/// طريقة الاستخدام على XPrinter:
/// 1. عرّف الطابعة بتعريفها الرسمي (Seagull/Driver الأصلي).
/// 2. اختر مقاس الورق = مقاس الليبل (مثلا 40×30) في الحوار.
/// 3. اطبع بمقياس 100% (Actual size) بدون Fit-to-page.
Future<void> printBarcodeStickersPdf(
  BuildContext context,
  List<BarcodeLabelData> items, {
  required double widthMm,
  required double heightMm,
  int copies = 1,
}) async {
  final clean =
      items.where((e) => e.barcode.trim().isNotEmpty).toList();
  if (clean.isEmpty) {
    throw StateError('لا توجد باركودات للطباعة.');
  }
  final w = widthMm.clamp(15.0, 110.0);
  final h = heightMm.clamp(10.0, 200.0);
  final n = copies <= 0 ? 1 : copies;
  final expanded = <BarcodeLabelData>[
    for (final it in clean)
      for (var i = 0; i < n; i++) it,
  ];

  // عرض التصوير ≈ دقة 203dpi (8 نقاط/مم) عشان الباركود يبقى حاد.
  final widthDots = (w * 8).round().clamp(160, 880);
  final scale = widthDots / 576.0;
  final nameSize = (28 * scale).clamp(10.0, 30.0);
  final codeSize = (24 * scale).clamp(9.0, 26.0);
  final barH = (90 * scale).clamp(32.0, 110.0);

  final format = PdfPageFormat(
    w * PdfPageFormat.mm,
    h * PdfPageFormat.mm,
  );
  const margin = pw.EdgeInsets.all(1 * PdfPageFormat.mm);

  final overlay = Overlay.of(context);
  final pdf = pw.Document();
  for (final it in expanded) {
    final key = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: -10000,
        child: Material(
          color: Colors.white,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: widthDots.toDouble(),
              child: Directionality(
                textDirection: ui.TextDirection.rtl,
                child: BarcodeLabelWidget(
                  item: it,
                  width: widthDots.toDouble(),
                  barcodeHeight: barH,
                  nameFontSize: nameSize,
                  codeFontSize: codeSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 120));
      await WidgetsBinding.instance.endOfFrame;
      final ro = key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        throw StateError('تعذر تجهيز ملصقات الباركود.');
      }
      ui.Image image;
      try {
        image = await ro.toImage(pixelRatio: 2.0);
      } catch (_) {
        image = await ro.toImage(pixelRatio: 1.0);
      }
      try {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (bytes == null) {
          throw StateError('تعذر تجهيز ملصقات الباركود.');
        }
        final Uint8List png = bytes.buffer.asUint8List();
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: margin,
            build: (_) => pw.Center(
              child: pw.Image(
                pw.MemoryImage(png),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        );
      } finally {
        image.dispose();
      }
    } finally {
      entry.remove();
    }
  }

  final saved = await pdf.save();
  await Printing.layoutPdf(
    onLayout: (_) async => saved,
    name: 'xprinter-stickers.pdf',
  );
}
