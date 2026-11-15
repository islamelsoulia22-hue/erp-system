import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// PDF طلب توريد للمورد — منتج + كمية فقط.
/// لا يحتوي أي بيانات عن فاتورة المبيعات (المباعة/العميل/الأسعار).
/// نفس تقنية تصوير الويدجت (تشكيل عربي سليم).

class SupplyPdfRow {
  final String name;
  final double qty;
  const SupplyPdfRow({required this.name, required this.qty});
}

class SupplyPdfData {
  final String number;
  final DateTime date;
  final String? supplierName;
  final String? warehouseName;
  final List<SupplyPdfRow> rows;
  const SupplyPdfData({
    required this.number,
    required this.date,
    this.supplierName,
    this.warehouseName,
    required this.rows,
  });
}

final NumberFormat _supplyNum = NumberFormat('#,##0.##', 'en_US');
String _num(double v) => _supplyNum.format(v);

String sanitizeSupplyFilename(String number) {
  var s = number.trim().isEmpty ? 'supply-order' : number.trim();
  s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  s = s.replaceAll(RegExp(r'\s+'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  if (s.length > 80) s = s.substring(0, 80);
  if (s.isEmpty) s = 'supply-order';
  return '$s.pdf';
}

/// تطبيع رقم الهاتف لرابط wa.me (مصر افتراضيا للأرقام المحلية).
String normalizeWhatsPhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('002')) d = d.substring(2);
  if (d.startsWith('20') && d.length >= 12) return d;
  // 01xxxxxxxxx (11 رقم) → 201xxxxxxxxx
  if (d.length == 11 && d.startsWith('0')) {
    return '20${d.substring(1)}';
  }
  // 1xxxxxxxxx (10 أرقام) → 201xxxxxxxxx
  if (d.length == 10 && d.startsWith('1')) return '20$d';
  return d;
}

Future<void> shareSupplyOrderPdf(
    BuildContext context, SupplyPdfData data) async {
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
            child: _SupplyDoc(data: data, logoProvider: logoProvider),
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
      debugPrint('supplyPdf: logo precache timeout, using fallback');
    } catch (e) {
      debugPrint('supplyPdf: logo precache failed: $e');
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;

    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw StateError('تعذر تجهيز طلب التوريد للمشاركة.');
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
      debugPrint('supplyPdf: toImage($pixelRatio) failed: $e, retry 1.0');
      image = await ro.toImage(pixelRatio: 1.0);
    }
    try {
      final pages = await _paginateImage(image);
      if (pages.isEmpty) {
        throw StateError('تعذر تجهيز طلب التوريد للمشاركة.');
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
        filename: sanitizeSupplyFilename(data.number),
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
      ui.Rect.fromLTWH(
          0, dy.toDouble(), image.width.toDouble(), h.toDouble()),
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

class _SupplyDoc extends StatelessWidget {
  final SupplyPdfData data;
  final ImageProvider logoProvider;
  const _SupplyDoc({required this.data, required this.logoProvider});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('d/M/yyyy', 'en_US').format(data.date);
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image(
                    image: logoProvider,
                    width: 64,
                    height: 64,
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.inventory_2_outlined,
                        size: 48)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text('SANAD — سند',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      Text('طلب توريد أصناف',
                          style: TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('رقم الطلب: ${data.number}',
                textDirection: ui.TextDirection.ltr,
                style: const TextStyle(fontSize: 14)),
            Text('التاريخ: $dateStr',
                style: const TextStyle(fontSize: 14)),
            if (data.supplierName?.isNotEmpty == true)
              Text('المورد: ${data.supplierName}',
                  style: const TextStyle(fontSize: 14)),
            if (data.warehouseName?.isNotEmpty == true)
              Text('التسليم لمخزن: ${data.warehouseName}',
                  style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Table(
              border: TableBorder.all(
                  color: Colors.grey.shade400),
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('الصنف',
                          style: TextStyle(
                              fontWeight:
                                  FontWeight.bold)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('الكمية المطلوبة',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight:
                                  FontWeight.bold)),
                    ),
                  ],
                ),
                for (final r in data.rows)
                  TableRow(
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.all(8),
                        child: Text(r.name),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.all(8),
                        child: Text(_num(r.qty),
                            textDirection:
                                ui.TextDirection.ltr,
                            textAlign:
                                TextAlign.center),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'برجاء توريد الأصناف الموضحة بالكميات المطلوبة.',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
