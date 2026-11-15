import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

import '../pdf/barcode_pdf.dart';

/// طباعة مباشرة على طابعة ريسيت USB (ESC/POS) من لينكس —
/// من غير CUPS ومن غير ما الطابعة تظهر في حوار الطباعة.
///
/// الفكرة: طابعات الريسيت الرخيصة (زي EUCCOI) النواة بتشوفها
/// كـ `/dev/usb/lp0` لكن CUPS مبيعرفش يعرّفها صح، فبنبعت
/// أوامر ESC/POS مباشرة لملف الجهاز:
/// - اسم الصنف (عربي) يتصور كصورة نقطية (raster) عشان
///   خطوط الطابعة المدمجة مبتدعمش العربي.
/// - الباركود يتصور مع الملصق بدقة 203dpi فيبقى واضح للسكانر.
///
/// متطلبات التشغيل (مرة واحدة):
/// 1. الطابعة موصلة بكابل USB ومنورة.
/// 2. صلاحية الكتابة على الجهاز — نفذ في الترمينال:
///    sudo usermod -aG lp $USER
///    وبعدها لوج آوت ولوج إن (أو ريستارت).

/// عرض الطباعة بالنقاط: 72مم على ورق 80مم بدقة 203dpi.
const kReceiptDotsWidth = 576;

/// خط الطباعة الثابت (Cairo مضمّن في التطبيق — يعمل أوفلاين):
/// يغلف محتوى التصوير عشان العربي ميطلعش مربعات لو خط
/// السيستم ناقص (خصوصا نسخة الجهاز).
const kPrintBaseStyle = TextStyle(fontFamily: 'Cairo');

/// خطأ طابعة الـ USB برسالة عربية جاهزة للعرض.
class UsbPrinterException implements Exception {
  final String messageAr;
  final String? fixCommand;
  const UsbPrinterException(this.messageAr, [this.fixCommand]);

  @override
  String toString() => messageAr;
}

String get _currentUserName {
  try {
    final env = Platform.environment;
    return env['USER'] ?? env['LOGNAME'] ?? env['SUDO_USER'] ?? r'$USER';
  } catch (_) {
    return r'$USER';
  }
}

String lpGroupFixForCurrentUser() =>
    'sudo usermod -aG lp $_currentUserName';

/// هل المنصة تدعم الطباعة المباشرة (لينكس ديسكتوب فقط)؟
bool get supportsUsbReceiptPrint {
  try {
    return Platform.isLinux;
  } catch (_) {
    return false;
  }
}

/// كل أجهزة طابعات USB المتاحة (`/dev/usb/lp*` أو `/dev/lp*`).
Future<List<String>> findUsbReceiptPrinters() async {
  try {
    final out = <String>[];
    final usbDir = Directory('/dev/usb');
    if (await usbDir.exists()) {
      await for (final e in usbDir.list()) {
        final p = e.path;
        if (p.contains('lp')) out.add(p);
      }
    }
    // بعض الأنظمة تظهر الطابعة كـ /dev/lp0 مباشرة.
    final devDir = Directory('/dev');
    try {
      await for (final e in devDir.list()) {
        final p = e.path;
        final name = p.split('/').last;
        if (name.startsWith('lp')) out.add(p);
      }
    } catch (_) {}
    out.sort();
    return out.toSet().toList()..sort();
  } catch (_) {
    return [];
  }
}

/// مفاتيح حفظ اختيار الطابعة لكل نوع (ريسيت 80مم / ملصقات).
/// مهمة لأن أول جهاز مكتشف تلقائيا قد يكون النوع الغلط
/// (مثلا XPrinter للملصقات بدل الريسيت) فيطبع على طابعة غلط.
const _kSavedReceiptPath = 'usb_receipt_path';
const _kSavedLabelPath = 'usb_label_path';

/// يحل مسار جهاز USB للغرض المطلوب:
/// [forReceipt] true = فاتورة ريسيت 80مم، false = ملصقات.
/// - مسار محدد صراحة ([overridePath]) يكسب دائما.
/// - ثم المحفوظ سابقا (لو لسه متوصل).
/// - ثم الوحيد المتاح (لو طابعة واحدة فقط).
/// - ثم حوار اختيار (لو أكتر من طابعة) مع زرار تست لكل جهاز.
Future<String> resolveUsbPrinterPath(
  BuildContext context, {
  required bool forReceipt,
  String? overridePath,
}) async {
  if (overridePath != null && overridePath.isNotEmpty) {
    return overridePath;
  }
  final found = await findUsbReceiptPrinters();
  if (found.isEmpty) {
    throw const UsbPrinterException(
      'لا توجد طابعة USB متصلة.\n'
      'اتأكد إن الطابعة موصلة بالكابل ومنورة.',
    );
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved =
        prefs.getString(forReceipt ? _kSavedReceiptPath : _kSavedLabelPath);
    if (saved != null && saved.isNotEmpty && found.contains(saved)) {
      return saved;
    }
  } catch (_) {}
  if (found.length == 1) return found.first;
  if (!context.mounted) return found.first;
  final picked = await showUsbPrinterPicker(
    context,
    found: found,
    forReceipt: forReceipt,
  );
  if (picked == null || picked.isEmpty) {
    throw const UsbPrinterException(
      'ملغية — اختار طابعة USB للمتابعة.',
    );
  }
  return picked;
}

/// يحفظ اختيار الطابعة الافتراضي لنوع معين.
Future<void> saveUsbPrinterPath(
  bool forReceipt,
  String path,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      forReceipt ? _kSavedReceiptPath : _kSavedLabelPath,
      path,
    );
  } catch (_) {}
}

/// حوار اختيار طابعة USB (لما يبقى فيه أكتر من طابعة متوصلة —
/// مثلا ريسيت + XPrinter) مع زرار تست لكل جهاز.
/// يرجع المسار المختار (ويحفظه) أو null لو اتلغى.
Future<String?> showUsbPrinterPicker(
  BuildContext context, {
  required List<String> found,
  required bool forReceipt,
}) async {
  var selected = found.first;
  var remember = true;
  String? testing;
  String? testError;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        Future<void> doTest(String path) async {
          setSt(() {
            testing = path;
            testError = null;
          });
          try {
            if (forReceipt) {
              await writeBytesToUsbDevice(path, [
                0x1B, 0x40, // تهيئة
                ...'RECEIPT OK\r\n'.codeUnits,
                0x1B, 0x64, 0x04, // تغذية
                0x1D, 0x56, 0x01, // قص
              ]);
            } else {
              // تست ملصق بدون تغيير SIZE (يستخدم ضبط الطابعة الحالي).
              await writeBytesToUsbDevice(path, [
                ...'CLS\r\nTEXT 10,10,"3",0,1,1,"LABEL OK"\r\nPRINT 1,1\r\n'
                    .codeUnits,
              ]);
            }
            setSt(() => testing = null);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('تست اتبعت على $path')),
              );
            }
          } on UsbPrinterException catch (e) {
            setSt(() {
              testing = null;
              testError = e.messageAr;
            });
          } catch (e) {
            setSt(() {
              testing = null;
              testError = 'تعذر التست: $e';
            });
          }
        }

        return AlertDialog(
          title: Text(
            forReceipt ? 'اختار طابعة الريسيت' : 'اختار طابعة الملصقات',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    forReceipt
                        ? 'متصل ${found.length} طابعات — اختار الريسيت (80مم) عشان الفاتورة متروحش على طابعة الملصقات.'
                        : 'متصل ${found.length} طابعات — اختار XPrinter عشان الملصق ميروحش على الريسيت.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  for (final p in found)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: RadioListTile<String>(
                        dense: true,
                        value: p,
                        // ignore: avoid_redundant_argument_values
                        groupValue: selected,
                        title: Text(
                          p,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        secondary: testing == p
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                tooltip: 'تست',
                                icon: const Icon(
                                  Icons.print_outlined,
                                  size: 20,
                                ),
                                onPressed: () => doTest(p),
                              ),
                        onChanged: (v) =>
                            setSt(() => selected = v ?? p),
                      ),
                    ),
                  if (testError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      testError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                  ],
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'حفظ كاختيار دائم',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: remember,
                    onChanged: (v) =>
                        setSt(() => remember = v ?? true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (remember) {
                  await saveUsbPrinterPath(forReceipt, selected);
                }
                if (ctx.mounted) Navigator.of(ctx).pop(selected);
              },
              child: const Text('طباعة'),
            ),
          ],
        );
      },
    ),
  );
}

/// تشخيص سريع للطباعة: الأجهزة + الصلاحيات + المجموعات.
/// يتنفذ من التطبيق (لينكس فقط) لعرضه في حوار الخطأ
/// بدل ما المستخدم يجري في الترمينال أعمى.
Future<String> getUsbReceiptDiagnostics([String? devicePath]) async {
  final buf = StringBuffer();
  try {
    final found = await findUsbReceiptPrinters();
    buf.writeln(
        'الأجهزة المكتشفة: ${found.isEmpty ? 'لا يوجد' : found.join(', ')}');
    if (devicePath != null && devicePath.isNotEmpty) {
      buf.writeln('الجهاز المستخدم: $devicePath');
    }
    try {
      final id = await Process.run('id', []);
      final idOut =
          (id.stdout.toString() + id.stderr.toString()).trim();
      if (idOut.isNotEmpty) buf.writeln('id: $idOut');
    } catch (_) {}
    try {
      final lsTargets = <String>[
        if (devicePath != null && devicePath.isNotEmpty)
          devicePath,
        '/dev/usb/lp0',
        '/dev/usb',
        '/dev/lp0',
      ];
      final ls =
          await Process.run('ls', ['-l', ...lsTargets]);
      final lsOut =
          (ls.stdout.toString() + ls.stderr.toString()).trim();
      if (lsOut.isNotEmpty) buf.writeln(lsOut);
    } catch (_) {}
    try {
      final groups = await Process.run('groups', []);
      final gOut =
          (groups.stdout.toString() + groups.stderr.toString())
              .trim();
      if (gOut.isNotEmpty) buf.writeln('groups: $gOut');
    } catch (_) {}
  } catch (e) {
    buf.writeln('تعذر التشخيص: $e');
  }
  return buf.toString().trim();
}

/// يطبع ملصقات باركود على طابعة الريسيت مباشرة.
/// [copies] مفتوح بدون حد أقصى — كل نسخة ملصق + قص.
Future<void> printLabelsUsbReceipt(
  BuildContext context,
  List<BarcodeLabelData> items, {
  int copies = 1,
  String? devicePath,
}) async {
  final clean = items
      .where((e) => e.barcode.trim().isNotEmpty)
      .toList();
  if (clean.isEmpty) {
    throw const UsbPrinterException(
      'لا توجد باركودات للطباعة — أضف باركود أولا.',
    );
  }
  var path = await resolveUsbPrinterPath(
    context,
    forReceipt: true,
    overridePath: devicePath,
  );
  final n = copies <= 0 ? 1 : copies;
  final out = <int>[0x1B, 0x40]; // ESC @ تهيئة
  for (final it in clean) {
    final raster = await renderLabelEscPosRaster(context, it);
    for (var i = 0; i < n; i++) {
      out.addAll(raster);
      // سطور تغذية + قص جزئي (لو مفيش قاطع الأمر يتجاهل).
      out.addAll([0x1B, 0x64, 0x04]); // ESC d 4
      out.addAll([0x1D, 0x56, 0x01]); // GS V 1
    }
  }
  await _writeToDevice(path, out);
}

/// يصور الملصق كصورة ثم يحوله لأوامر raster (GS v 0).
/// يرجع بايتات جاهزة للإضافة في ستريم الطباعة (بدون قص).
/// عامة عشان الاختبارات تقدر تتحقق من الناتج.
Future<List<int>> renderLabelEscPosRaster(
  BuildContext context,
  BarcodeLabelData item,
) async {
  final overlay = Overlay.of(context);
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
          child: DefaultTextStyle(
            style: kPrintBaseStyle,
            child: SizedBox(
              width: kReceiptDotsWidth.toDouble(),
              child: BarcodeLabelWidget(
                item: item,
                width: kReceiptDotsWidth.toDouble(),
                // نص الارتفاع القديم (180→90) عشان الباركود
                // مياخدش مساحة أكبر من الليبل — ويفضل
                // واضحا للسكانر على 203dpi (~11مم).
                barcodeHeight: 90,
                nameFontSize: 28,
                codeFontSize: 24,
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
    await Future.delayed(
      const Duration(milliseconds: 150),
    );
    await WidgetsBinding.instance.endOfFrame;
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw const UsbPrinterException(
        'تعذر تجهيز الملصق للطباعة.',
      );
    }
    final image = await ro.toImage(pixelRatio: 1.0);
    try {
      return _imageToEscPosRaster(image);
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// يحول صورة Flutter لأوامر (GS v 0) نقطية أحادية بالأبيض والأسود.
/// الفواتير الطويلة تتقسم شرائح (كل شريحة ≤ 1000 نقطة) لأن ذاكرة
/// طابعة الريسيت محدودة — الشرائح تتبعت ورا بعض وتطلع كفاتورة واحدة.
Future<List<int>> _imageToEscPosRaster(
  ui.Image image,
) async {
  final w = image.width;
  final h = image.height;
  if (w <= 0 || h <= 0 || h > 15000) {
    throw const UsbPrinterException(
      'تعذر تجهيز الملصق للطباعة.',
    );
  }
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) {
    throw const UsbPrinterException(
      'تعذر تجهيز الملصق للطباعة.',
    );
  }
  final px = data.buffer.asUint8List();
  final rowBytes = (w + 7) ~/ 8;
  final xL = rowBytes & 0xFF;
  final xH = (rowBytes >> 8) & 0xFF;
  final out = <int>[0x1B, 0x61, 0x01]; // توسيط
  const maxStripH = 1000;
  var y0 = 0;
  while (y0 < h) {
    final stripH =
        (y0 + maxStripH > h) ? h - y0 : maxStripH;
    final body = <int>[];
    for (var y = y0; y < y0 + stripH; y++) {
      var byte = 0;
      var bits = 0;
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        final r = px[o];
        final g = px[o + 1];
        final b = px[o + 2];
        final lum = (0.299 * r + 0.587 * g + 0.114 * b);
        byte = (byte << 1) | (lum < 128 ? 1 : 0);
        bits++;
        if (bits == 8) {
          body.add(byte);
          byte = 0;
          bits = 0;
        }
      }
      if (bits > 0) {
        body.add(byte << (8 - bits));
      }
    }
    final yL = stripH & 0xFF;
    final yH = (stripH >> 8) & 0xFF;
    out.addAll([
      0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH,
      ...body,
    ]);
    y0 += stripH;
  }
  return out;
}

/// يصور أي ويدجت ريسيت (عرض 576) كأوامر raster.
/// يستخدم للملصقات والفواتير — العربي يتصور كصورة فبيطلع سليم.
Future<List<int>> renderReceiptWidgetRaster(
  BuildContext context,
  Widget widget,
) async {
  final overlay = Overlay.of(context);
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
          child: DefaultTextStyle(
            style: kPrintBaseStyle,
            child: SizedBox(
              width: kReceiptDotsWidth.toDouble(),
              child: widget,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(
      const Duration(milliseconds: 150),
    );
    await WidgetsBinding.instance.endOfFrame;
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw const UsbPrinterException(
        'تعذر تجهيز الفاتورة للطباعة.',
      );
    }
    final image = await ro.toImage(pixelRatio: 1.0);
    try {
      return _imageToEscPosRaster(image);
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// سطر صنف في ريسيت الفاتورة الحراري.
/// إجمالي الصف المعروض هو الصافي بدون ضريبة (الكمية × السعر
/// − الخصم)، والضريبة تتجمع تحت في الفاتورة حسب نسبتها.
class ReceiptInvoiceRow {
  final String name;
  final double qty;
  final double price;
  final double total;
  final double discount;
  final double taxRate;
  const ReceiptInvoiceRow({
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
    this.discount = 0,
    this.taxRate = 0,
  });

  /// صافي الصف بدون ضريبة.
  double get netTotal => qty * price - discount;
}

/// تجميع الضريبة حسب النسبة: {النسبة: مبلغ الضريبة}.
/// محسوبة على صافي الصفوف (بدون ضريبة) عشان تتوافق مع
/// إجمالي الصفوف المعروض.
Map<double, double> groupReceiptTaxes(
    List<ReceiptInvoiceRow> rows) {
  final out = <double, double>{};
  for (final r in rows) {
    if (r.taxRate <= 0) continue;
    out[r.taxRate] =
        (out[r.taxRate] ?? 0) + r.netTotal * r.taxRate / 100;
  }
  return out;
}

/// نسبة بدون أصفار زائدة (14.0 → 14).
String receiptRateStr(double v) {
  var s = v.toString();
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

/// بيانات فاتورة (مبيعات أو مشتريات) للطباعة على ريسيت 80مم.
class ReceiptInvoiceData {
  final String title;
  final String number;
  final DateTime date;
  final String partnerLabel;
  final String partnerName;
  final String? paymentLabel;
  final List<ReceiptInvoiceRow> rows;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;
  final String? notes;
  const ReceiptInvoiceData({
    required this.title,
    required this.number,
    required this.date,
    required this.partnerLabel,
    required this.partnerName,
    this.paymentLabel,
    required this.rows,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
    this.notes,
  });
}

String _receiptMoney(double v) =>
    intl.NumberFormat('#,##0.##', 'en_US').format(v);

/// شكل فاتورة الريسيت الحراري (عرض 576 نقطة = 72مم).
/// يتصور كصورة فالعربي يطلع سليم على الطابعة.
class InvoiceReceiptWidget extends StatelessWidget {
  final ReceiptInvoiceData data;
  const InvoiceReceiptWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final dateStr =
        intl.DateFormat('yyyy/MM/dd HH:mm').format(data.date);
    final taxes = groupReceiptTaxes(data.rows);
    return Container(
      width: kReceiptDotsWidth.toDouble(),
      color: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 16,
      ),
      child: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.black),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Text(
                'SANAD — سند',
                textAlign: TextAlign.center,
                textDirection: ui.TextDirection.ltr,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                  height: 2, color: Colors.black),
              const SizedBox(height: 8),
              Text(
                data.number,
                textAlign: TextAlign.center,
                textDirection: ui.TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Text(
                dateStr,
                textAlign: TextAlign.center,
                textDirection: ui.TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${data.partnerLabel}: ${data.partnerName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.black,
                ),
              ),
              if (data.paymentLabel != null)
                Text(
                  'الدفع: ${data.paymentLabel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.black,
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                  height: 2, color: Colors.black),
              const SizedBox(height: 8),
              // جدول الأصناف: الصنف | الكمية | السعر | الإجمالي.
              Table(
                border: TableBorder.all(
                  color: Colors.black,
                  width: 2,
                ),
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.4),
                  3: FlexColumnWidth(1.4),
                },
                defaultVerticalAlignment:
                    TableCellVerticalAlignment.middle,
                children: [
                  const TableRow(
                    children: [
                      _ReceiptCell('الصنف',
                          header: true),
                      _ReceiptCell('الكمية',
                          header: true),
                      _ReceiptCell('السعر',
                          header: true),
                      _ReceiptCell('الإجمالي',
                          header: true),
                    ],
                  ),
                  for (final r in data.rows)
                    TableRow(
                      children: [
                        _ReceiptCell(r.name),
                        _ReceiptCell(
                          _receiptMoney(r.qty),
                          ltr: true,
                        ),
                        _ReceiptCell(
                          _receiptMoney(r.price),
                          ltr: true,
                        ),
                        _ReceiptCell(
                          _receiptMoney(r.netTotal),
                          ltr: true,
                          bold: true,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                  height: 2, color: Colors.black),
              const SizedBox(height: 8),
              _receiptTotalRow(
                  'الفرعي', _receiptMoney(data.subtotal)),
              if (data.discount != 0)
                _receiptTotalRow(
                    'الخصم', _receiptMoney(data.discount)),
              // الضريبة مجمعة حسب النسبة مع كتابة النسبة
              // صراحة (مثال: ضريبة 14%).
              for (final e in taxes.entries)
                _receiptTotalRow(
                    'ضريبة ${receiptRateStr(e.key)}%',
                    _receiptMoney(e.value)),
              if (taxes.isEmpty && data.taxAmount != 0)
                _receiptTotalRow(
                    'الضريبة', _receiptMoney(data.taxAmount)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'الإجمالي',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Text(
                    _receiptMoney(data.total),
                    textDirection:
                        ui.TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              if (data.notes?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  data.notes!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.black,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                  height: 2, color: Colors.black),
              const SizedBox(height: 8),
              const Text(
                'شكرا لتعاملكم معنا',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptTotalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 24,
                color: Colors.black,
              ),
            ),
          ),
          Text(
            value,
            textDirection: ui.TextDirection.ltr,
            style: const TextStyle(
              fontSize: 24,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

/// خلية جدول الريسيت: حدود واضحة وخط يناسب الورق الحراري.
class _ReceiptCell extends StatelessWidget {
  final String text;
  final bool header;
  final bool bold;
  final bool ltr;
  const _ReceiptCell(
    this.text, {
    this.header = false,
    this.bold = false,
    this.ltr = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 6,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        softWrap: true,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textDirection:
            ltr ? ui.TextDirection.ltr : null,
        style: TextStyle(
          fontSize: header ? 20 : 19,
          fontWeight:
              (header || bold) ? FontWeight.bold : FontWeight.normal,
          color: Colors.black,
        ),
      ),
    );
  }
}

/// يطبع فاتورة (مبيعات/مشتريات) على طابعة الريسيت مباشرة.
/// الفاتورة الطويلة تتقسم شرائح تلقائيا وتطلع كفاتورة واحدة + قص.
Future<void> printInvoiceUsbReceipt(
  BuildContext context,
  ReceiptInvoiceData data, {
  int copies = 1,
  String? devicePath,
}) async {
  if (data.rows.isEmpty) {
    throw const UsbPrinterException(
      'لا توجد أصناف في الفاتورة للطباعة.',
    );
  }
  var path = await resolveUsbPrinterPath(
    context,
    forReceipt: true,
    overridePath: devicePath,
  );
  final raster = await renderReceiptWidgetRaster(
    context,
    InvoiceReceiptWidget(data: data),
  );
  final n = copies <= 0 ? 1 : copies;
  final out = <int>[0x1B, 0x40]; // ESC @ تهيئة
  for (var i = 0; i < n; i++) {
    out.addAll(raster);
    out.addAll([0x1B, 0x64, 0x06]); // ESC d 6 تغذية
    out.addAll([0x1D, 0x56, 0x01]); // GS V 1 قص
  }
  await _writeToDevice(path, out);
}

/// كتابة بايتات خام (ESC/POS أو TSPL) لملف جهاز USB.
/// عامة لخدمة XPrinter (ملصقات TSPL على لينكس) — الأخطاء
/// هي نفس [UsbPrinterException] برسائل عربية جاهزة للعرض.
Future<void> writeBytesToUsbDevice(
  String path,
  List<int> bytes,
) =>
    _writeToDevice(path, bytes);

/// يكتب بايتات ESC/POS مباشرة لملف جهاز USB.
/// ملحوظة: نستخدم writeOnly (من غير truncate) لأن أجهزة
/// `/dev/usb/lp*` ملفات أجهزة وليست ملفات عادية.
Future<void> _writeToDevice(
  String path,
  List<int> bytes,
) async {
  try {
    final raf =
        await File(path).open(mode: FileMode.writeOnly);
    try {
      raf.writeFromSync(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }
  } on FileSystemException catch (e) {
    final code = e.osError?.errorCode;
    if (code == 13) {
      // أشهر سبب لاستمرار الخطأ بعد تنفيذ الأمر:
      // 1) الأمر اتنفذ ليوزر غلط (مثلا root بدل اسمك).
      // 2) الجلسة لسه بالجروبات القديمة — لازم reboot كامل
      //    مش لوج آوت بس، أو تشغيل التطبيق من تفس الترمينال
      //    بعد `newgrp lp`.
      // 3) ملف الجهاز مملوك لجروب غير lp (مثلا root) —
      //    ساعتها الحل المؤقت chmod أو قاعدة udev دائمة.
      final user = _currentUserName;
      throw UsbPrinterException(
        'مفيش صلاحية للكتابة على الطابعة ($path).\n'
        'الأمر اللي نفذته غالبا ما اتطبقش على جلستك الحالية.\n\n'
        'جرب بالترتيب:\n'
        '1) اتأكد إنك في جروب lp (الأمر groups لازم يطلع فيه lp).\n'
        '2) اعمل reboot كامل (اللوج آوت لوحده ساعات مبيكفيش).\n'
        '3) للتجربة السريعة نفذ أمر chmod المؤقت تحت.',
        'sudo usermod -aG lp $user',
      );
    }
    if (code == 16) {
      throw UsbPrinterException(
        'الطابعة مشغولة ($path) — غالبا CUPS ماسك الجهاز.\n'
        'وقف طابور CUPS أو امسح تعريف الطابعة من الإعدادات '
        'وجرب تاني، أو افصلها ووصلها.',
      );
    }
    if (code == 2) {
      throw UsbPrinterException(
        'الجهاز ($path) مش موجود.\n'
        'افصل الطابعة ووصلها تاني، ثم دوس طباعة من جديد '
        'عشان يدور على جهاز جديد.',
      );
    }
    throw UsbPrinterException(
      'تعذر الوصول للطابعة ($path) [كود $code: ${e.osError?.message ?? e.message}].\n'
      'افصلها ووصلها تاني وحاول مجددا.',
    );
  } catch (_) {
    throw UsbPrinterException(
      'تعذر الطباعة على ($path).\n'
      'اتأكد إن الطابعة موصلة ومنورة.',
    );
  }
}

String? _deviceFromMessage(String msg) {
  final m = RegExp(r'\((/dev/[^)]+)\)').firstMatch(msg);
  return m?.group(1);
}

/// حوار خطأ طابعة USB مع التشخيص وأزرار نسخ أوامر الإصلاح.
/// يعرض:
/// - أمر الجروب الدائم (usermod)
/// - أمر التجربة المؤقتة (chmod — يثبت إن المشكلة صلاحيات)
/// - قاعدة udev الدائمة (لو الجهاز مملوك لجروب غير lp)
/// - ناتج التشخيص (id / ls -l / groups)
Future<void> showUsbPrinterError(
  BuildContext context,
  UsbPrinterException e,
) async {
  String diagnostics = '';
  try {
    diagnostics = await getUsbReceiptDiagnostics(
      _deviceFromMessage(e.messageAr),
    );
  } catch (_) {}
  if (!context.mounted) return;
  final device = _deviceFromMessage(e.messageAr);
  final tempFix =
      device != null ? 'sudo chmod 666 $device' : null;
  const udevFix =
      'echo \'SUBSYSTEM=="usb", MODE="0666"\' | sudo tee /etc/udev/rules.d/99-receipt-printer.rules && sudo udevadm control --reload-rules && sudo udevadm trigger';
  const checkCmd = 'groups; id; ls -l /dev/usb/lp* /dev/lp* 2>&1';

  void copyCmd(String cmd, String doneMsg) {
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(doneMsg)),
    );
  }

  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تعذر الطباعة على الريسيت'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Text(e.messageAr),
              if (e.fixCommand != null) ...[
                const SizedBox(height: 12),
                const Text(
                  '1) حل دائم (جروب lp):',
                  style: TextStyle(
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius:
                        BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    e.fixCommand!,
                    textDirection:
                        TextDirection.ltr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'بعد الأمر: اعمل reboot كامل (مش لوج آوت بس)، '
                  'ثم نفذ groups ولازم تشوف lp.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              if (tempFix != null) ...[
                const SizedBox(height: 12),
                const Text(
                  '2) تجربة مؤقتة (تثبت إنها صلاحيات):',
                  style: TextStyle(
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius:
                        BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    tempFix,
                    textDirection:
                        TextDirection.ltr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                const Text(
                  'لو الطباعة اشتغلت بعد chmod يبقى المشكلة '
                  '100% صلاحيات والجروب لسه ما اتطبقش.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                '3) حل دائم بديل (udev — لو الجهاز مش بجروب lp):',
                style: TextStyle(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  udevFix,
                  textDirection:
                      TextDirection.ltr,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'أوامر الفحص (ابعت ناتجها لو المشكلة مستمرة):',
                style: TextStyle(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: const SelectableText(
                  checkCmd,
                  textDirection:
                      TextDirection.ltr,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              if (diagnostics.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'تشخيص تلقائي من التطبيق:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F1F1),
                    borderRadius:
                        BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    diagnostics,
                    textDirection:
                        TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (e.fixCommand != null)
          TextButton.icon(
            onPressed: () =>
                copyCmd(e.fixCommand!, 'اتنسخ أمر الجروب.'),
            icon: const Icon(
              Icons.copy_outlined,
              size: 18,
            ),
            label: const Text('نسخ أمر الجروب'),
          ),
        if (tempFix != null)
          TextButton.icon(
            onPressed: () => copyCmd(
                tempFix, 'اتنسخ أمر التجربة المؤقتة.'),
            icon: const Icon(
              Icons.bolt_outlined,
              size: 18,
            ),
            label: const Text('نسخ chmod'),
          ),
        TextButton.icon(
          onPressed: () => copyCmd(
              diagnostics.isNotEmpty
                  ? diagnostics
                  : checkCmd,
              'اتنسخ التشخيص — ابعته للدعم.'),
          icon: const Icon(
            Icons.bug_report_outlined,
            size: 18,
          ),
          label: const Text('نسخ التشخيص'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(),
          child: const Text('حسنا'),
        ),
      ],
    ),
  );
}
