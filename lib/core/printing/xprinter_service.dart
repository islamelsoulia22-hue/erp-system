import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pdf/barcode_pdf.dart';
import 'usb_receipt_printer.dart';
import 'xprinter_network.dart';
import 'xprinter_usb.dart' as xusb;

// ─── استثناء XPrinter برسالة عربية ─────────────────────────────

class XPrinterException implements Exception {
  final String messageAr;
  const XPrinterException(this.messageAr);
  @override
  String toString() => messageAr;
}

// ─── وضع الطباعة ──────────────────────────────────────────────

/// - [escPos80]: طابعات الريسيت الحرارية (XP-80C / Q200 / N160II)
///   ورق 80مم متصل — أمر raster لكل ملصق + تغذية + قص.
/// - [tsplLabel]: طابعات الملصقات اللاصقة (XP-365B / 420B / DT108)
///   أوامر TSPL (SIZE/GAP/BITMAP/PRINT) بمقاس الملصق الحقيقي.
enum XPrinterMode { escPos80, tsplLabel }

// ─── الإعدادات (محفوظة على الجهاز) ───────────────────────────

class XPrinterSettings {
  final String ip;
  final int port;
  final XPrinterMode mode;
  final double labelWidthMm;
  final double labelHeightMm;
  final double gapMm;
  final int density; // 0..15 (TSPL DENSITY)
  final bool cut; // قص بعد كل ملصق (ريسيت فقط)
  final String usbDeviceId; // آخر طابعة USB مختارة (فارغ = تلقائي)

  const XPrinterSettings({
    this.ip = '192.168.1.100',
    this.port = 9100,
    this.mode = XPrinterMode.tsplLabel,
    this.labelWidthMm = 40,
    this.labelHeightMm = 30,
    this.gapMm = 2,
    this.density = 8,
    this.cut = false,
    this.usbDeviceId = '',
  });

  static const _kIp = 'xprinter_ip';
  static const _kPort = 'xprinter_port';
  static const _kMode = 'xprinter_mode';
  static const _kW = 'xprinter_w';
  static const _kH = 'xprinter_h';
  static const _kGap = 'xprinter_gap';
  static const _kDensity = 'xprinter_density';
  static const _kCut = 'xprinter_cut';
  static const _kUsb = 'xprinter_usb_id';

  static Future<XPrinterSettings> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return XPrinterSettings(
        ip: p.getString(_kIp) ?? '192.168.1.100',
        port: p.getInt(_kPort) ?? 9100,
        mode: (p.getString(_kMode) ?? 'tspl') == 'escpos'
            ? XPrinterMode.escPos80
            : XPrinterMode.tsplLabel,
        labelWidthMm: p.getDouble(_kW) ?? 40,
        labelHeightMm: p.getDouble(_kH) ?? 30,
        gapMm: p.getDouble(_kGap) ?? 2,
        density: p.getInt(_kDensity) ?? 8,
        cut: p.getBool(_kCut) ?? false,
        usbDeviceId: p.getString(_kUsb) ?? '',
      );
    } catch (_) {
      return const XPrinterSettings();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kIp, ip);
      await p.setInt(_kPort, port);
      await p.setString(
        _kMode,
        mode == XPrinterMode.escPos80 ? 'escpos' : 'tspl',
      );
      await p.setDouble(_kW, labelWidthMm);
      await p.setDouble(_kH, labelHeightMm);
      await p.setDouble(_kGap, gapMm);
      await p.setInt(_kDensity, density);
      await p.setBool(_kCut, cut);
      await p.setString(_kUsb, usbDeviceId);
    } catch (_) {}
  }

  XPrinterSettings copyWith({
    String? ip,
    int? port,
    XPrinterMode? mode,
    double? labelWidthMm,
    double? labelHeightMm,
    double? gapMm,
    int? density,
    bool? cut,
    String? usbDeviceId,
  }) =>
      XPrinterSettings(
        ip: ip ?? this.ip,
        port: port ?? this.port,
        mode: mode ?? this.mode,
        labelWidthMm: labelWidthMm ?? this.labelWidthMm,
        labelHeightMm: labelHeightMm ?? this.labelHeightMm,
        gapMm: gapMm ?? this.gapMm,
        density: density ?? this.density,
        cut: cut ?? this.cut,
        usbDeviceId: usbDeviceId ?? this.usbDeviceId,
      );
}

/// هل الطباعة الشبكية المباشرة متاحة؟ (كل الأنظمة الأصلية — لا على الويب)
bool get supportsXPrinterNetwork => kNetworkPrintingSupported;

/// هل الطباعة عبر USB المباشر متاحة؟
/// (لينكس ملف جهاز + أندرويد/ويندوز/macOS مكتبة — لا ويب ولا iOS)
bool get supportsXPrinterUsb => xusb.supportsXPrinterUsbDirect;

// ─── تحويلات المقاسات ─────────────────────────────────────────

/// مم → نقاط طابعة (203dpi افتراضيا — كل طابعات XPrinter الحرارية).
int mmToDots(double mm, {int dpi = 203}) =>
    (mm * dpi / 25.4).round();

/// مقاسات ملصقات جاهزة (عرض × ارتفاع بالمم).
const xprinterLabelPresets = <String, (double, double)>{
  '40 × 30 (الأشهر)': (40, 30),
  '50 × 30': (50, 30),
  '38 × 25': (38, 25),
  '30 × 20 (صغير)': (30, 20),
  '70 × 50 (كبير)': (70, 50),
};

// ─── تصوير أسطر عربية (خطوط الطابعة لا تدعم العربي) ──────────

/// يصور أي ويدجت بعرض [widthDots] نقطة ويعيد الصورة الخام.
Future<ui.Image> _captureDotsWidget(
  BuildContext context,
  Widget child, {
  required int widthDots,
}) async {
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
            // خط ثابت مضمن — العربي ميطلعش مربعات.
            style: kPrintBaseStyle,
            child: SizedBox(
              width: widthDots.toDouble(),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) {
      throw const XPrinterException('تعذر تجهيز الملصق للطباعة.');
    }
    return ro.toImage(pixelRatio: 1.0);
  } finally {
    entry.remove();
  }
}

/// يصور سطر اسم الصنف فقط (للعربي) كشريط أحادي —
/// الشرائط الصغيرة مجربة على XP-420B (حرف R أسود على أبيض).
Future<({int widthBytes, int height, List<int> data})>
    captureNameStripMono(
  BuildContext context,
  String name, {
  required int widthDots,
}) async {
  const nameSize = 24.0;
  final image = await _captureDotsWidget(
    // ignore: use_build_context_synchronously
    context,
    Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 3,
        ),
        alignment: Alignment.center,
        child: Text(
          name.trim(),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: nameSize,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    ),
    widthDots: widthDots,
  );
  try {
    return await imageToMonoBytes(image);
  } finally {
    image.dispose();
  }
}

/// صورة → بايتات أحادية (1 بت/نقطة) لأمر TSPL BITMAP.
/// الترميز القياسي (مثبت بتجربة XP-420B بحرف R: 1 = أسود، 0 = أبيض).
/// (دالة ESC/POS للريسيت في ملفها الخاص ولم تمس — شغالة صح).
Future<({int widthBytes, int height, List<int> data})>
    imageToMonoBytes(ui.Image image) async {
  final w = image.width;
  final h = image.height;
  if (w <= 0 || h <= 0 || h > 15000) {
    throw const XPrinterException('تعذر تجهيز الملصق للطباعة.');
  }
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) {
    throw const XPrinterException('تعذر تجهيز الملصق للطباعة.');
  }
  final px = raw.buffer.asUint8List();
  final widthBytes = (w + 7) ~/ 8;
  final data = <int>[];
  for (var y = 0; y < h; y++) {
    var byte = 0;
    var bits = 0;
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final lum = 0.299 * px[o] + 0.587 * px[o + 1] + 0.114 * px[o + 2];
      byte = (byte << 1) | (lum < 128 ? 1 : 0);
      bits++;
      if (bits == 8) {
        data.add(byte);
        byte = 0;
        bits = 0;
      }
    }
    if (bits > 0) data.add(byte << (8 - bits));
    // إكمال الصف لعرض مضاعف 8 (لو العرض ليس مضاعفا) — أبيض (0x00).
    final expected = widthBytes;
    final rowStart = y * widthBytes;
    while (data.length - rowStart < expected) {
      data.add(0);
    }
  }
  return (widthBytes: widthBytes, height: h, data: data);
}

// ─── بناء أمر TSPL لملصق واحد ─────────────────────────────────

List<int> _tspl(String cmd) => [...cmd.codeUnits, 0x0D, 0x0A];

/// رقم TSPL بدون كسور زائدة (40.0 → 40) — بعض الفيرمويرات
/// ترفض الصيغة العشرية في SIZE/GAP.
String _tsplNum(double v) {
  if (v == v.roundToDouble()) return '${v.round()}';
  var s = v.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

/// يحسب موضع BITMAP على الليبل (X,Y بالنقاط):
/// - أفقيا: توسيط + انحياز 6 نقاط يمينا (يصلح قص الشمال على XP-420B).
/// - رأسيا: توسيط في نص الليبل (بدل اللزق فوق عند y=8).
/// دالة خالصة (بدون ويدجت) عشان الاختبارات السريعة.
({int x, int y}) tsplBitmapOrigin({
  required int labelWidthDots,
  required int labelHeightDots,
  required int imgWidthDots,
  required int imgHeightDots,
}) {
  var x = (labelWidthDots - imgWidthDots) ~/ 2 + 6;
  if (x < 0) x = 0;
  // لو الصورة أعرض من الليبل: ثبتها على هامش 6 نقاط يمينا
  // بدل القص من الشمال — الهامش الأيمن المقصوص أبيض غالبا.
  if (imgWidthDots >= labelWidthDots) x = 6;
  var y = (labelHeightDots - imgHeightDots) ~/ 2;
  if (y < 8) y = 8;
  return (x: x, y: y);
}

/// هل النص تطبع خطوط الطابعة المدمجة؟ (لاتيني/أرقام فقط —
/// العربي يحتاج شريط مصور).
bool isTsplNativeText(String s) =>
    s.runes.every((r) => r >= 32 && r < 127);

/// عرض خط TSPL المدمج بالنقاط (تقريبي حسب الدليل).
int _tsplFontW(String text, String font) {
  const w = {'1': 8, '2': 12, '3': 16, '4': 24, '5': 32};
  return text.length * (w[font] ?? 12);
}

/// ارتفاع خط TSPL المدمج بالنقاط.
int _tsplFontH(String font) {
  const h = {'1': 12, '2': 20, '3': 24, '4': 32, '5': 48};
  return h[font] ?? 20;
}

/// عرض باركود Code128 الأصلي التقريبي بالنقاط (شامل هوامش الأمان).
/// الأرقام الزوجية تستخدم Code C (11 وحدة/رمزين)، وإلا Code B.
int estimateCode128Dots(String data, int narrow) {
  final digits = RegExp(r'^\d+$').hasMatch(data);
  final symbols =
      (digits && data.length.isEven) ? data.length ~/ 2 : data.length;
  // start + data + checksum (11 وحدة) + stop (13) + quiet zones.
  return (11 * (symbols + 2) + 13) * narrow + 20;
}

/// يبني مهمة TSPL بالأوامر الأصلية لكل ملصق: اسم (TEXT لاتيني أو
/// شريط عربي مصور) + باركود 128 أصلي + أرقام — الناتج زي ملصق
/// SAGAYER المجرب على XP-420B (حاد ويقرأه السكانر بثبات).
/// [copies] مفتوح بدون حد أقصى — كل نسخة = ملصق + PRINT.
Future<List<int>> buildTsplNativeJob(
  BuildContext context,
  List<BarcodeLabelData> items,
  XPrinterSettings s, {
  int copies = 1,
}) async {
  final clean =
      items.where((e) => e.barcode.trim().isNotEmpty).toList();
  if (clean.isEmpty) {
    throw const XPrinterException('لا توجد باركودات للطباعة.');
  }
  final n = copies <= 0 ? 1 : copies;
  final wDots = mmToDots(s.labelWidthMm);
  final hDots = mmToDots(s.labelHeightMm);
  // إزاحة علوية لليبلات الطويلة (25مم = بدون إزاحة = نفس هندسة
  // ملصق SAGAYER المجرب: اسم 10، باركود 55، أرقام 125).
  final topPad = hDots <= 200 ? 0 : (hDots - 200) ~/ 2;
  final out = <int>[];
  out.addAll(_tspl('SIZE ${_tsplNum(s.labelWidthMm)} mm, ${_tsplNum(s.labelHeightMm)} mm'));
  out.addAll(_tspl('GAP ${_tsplNum(s.gapMm)} mm, 0 mm'));
  out.addAll(_tspl('DENSITY ${s.density.clamp(0, 15)}'));
  out.addAll(_tspl('SPEED 3'));
  out.addAll(_tspl('DIRECTION 0'));
  out.addAll(_tspl('CLS'));

  for (final it in clean) {
    final code = it.barcode.trim().replaceAll('"', '');
    final name = it.productName.trim().replaceAll('"', '');
    // الشريط العربي يتصور مرة واحدة ويتعاد لكل نسخة.
    ({int widthBytes, int height, List<int> data})? strip;
    if (name.isNotEmpty && !isTsplNativeText(name)) {
      strip = await captureNameStripMono(
        // ignore: use_build_context_synchronously
        context,
        name,
        widthDots: wDots,
      );
    }
    // عرض الباركود: narrow=2 (0.25مم — يقرأه السكانر)، ولو طويل
    // على الليبل ينزل narrow=1.
    var narrow = 2;
    var est = estimateCode128Dots(code, narrow);
    if (est > wDots - 16) {
      narrow = 1;
      est = estimateCode128Dots(code, narrow);
    }
    final barH = 60;
    for (var i = 0; i < n; i++) {
      out.addAll(_tspl('CLS'));
      var asciiH = 38;
      if (strip != null) {
        final o = tsplBitmapOrigin(
          labelWidthDots: wDots,
          labelHeightDots: hDots,
          imgWidthDots: strip.widthBytes * 8,
          imgHeightDots: strip.height,
        );
        // الشريط فوق (هندسة SAGAYER) بدل التوسيط الكامل.
        final y = topPad + 6;
        out.addAll(
          'BITMAP ${o.x},$y,${strip.widthBytes},${strip.height},0,'
              .codeUnits,
        );
        out.addAll(strip.data);
        out.addAll([0x0D, 0x0A]);
      } else if (name.isNotEmpty) {
        var font = '4';
        if (_tsplFontW(name, font) > wDots - 20) font = '3';
        if (_tsplFontW(name, font) > wDots - 20) font = '2';
        asciiH = _tsplFontH(font) + 6;
        final nx = ((wDots - _tsplFontW(name, font)) ~/ 2)
            .clamp(4, wDots - 10);
        out.addAll(_tspl('TEXT $nx,${topPad + 10},"$font",0,1,1,"$name"'));
      }
      final nameH = strip != null ? strip.height + 6 : asciiH;
      final by = topPad + 10 + nameH + 7;
      final bx = ((wDots - est) ~/ 2).clamp(4, wDots - 10);
      out.addAll(
        _tspl('BARCODE $bx,$by,"128",$barH,0,0,$narrow,$narrow,"$code"'),
      );
      final numY = by + barH + 8;
      final numX = ((wDots - _tsplFontW(code, '2')) ~/ 2)
          .clamp(4, wDots - 10);
      out.addAll(_tspl('TEXT $numX,$numY,"2",0,1,1,"$code"'));
      out.addAll(_tspl('PRINT 1,1'));
    }
  }
  return out;
}

// ─── طباعة شبكية مباشرة (كل الأنظمة الأصلية) ──────────────────

void _checkIp(String ip) {
  final v = ip.trim();
  if (v.isEmpty) throw const XPrinterException('ادخل IP الطابعة أولا.');
  final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  if (!ipv4.hasMatch(v)) {
    throw const XPrinterException(
      'عنوان IP غير صالح — مثال: 192.168.1.100',
    );
  }
}

/// طباعة ملصقات على XPrinter شبكة (واي فاي/LAN) — ESC/POS أو TSPL
/// حسب [settings.mode]. يعمل من أندرويد وويندوز ولينكس وmacOS وiOS.
Future<void> printLabelsXPrinterNetwork(
  BuildContext context,
  List<BarcodeLabelData> items,
  XPrinterSettings settings, {
  int copies = 1,
}) async {
  if (!supportsXPrinterNetwork) {
    throw const XPrinterException(
      'الطباعة المباشرة غير متاحة على الويب — استخدم "PDF بمقاس الملصق".',
    );
  }
  _checkIp(settings.ip);
  final port = (settings.port <= 0 || settings.port > 65535)
      ? 9100
      : settings.port;

  final bytes = await buildXPrinterLabelBytes(
    context,
    items,
    settings,
    copies: copies,
  );
  try {
    await sendBytesToNetworkPrinter(
      ip: settings.ip.trim(),
      port: port,
      bytes: bytes,
    );
  } on XPrinterException {
    rethrow;
  } catch (e) {
    throw XPrinterException(
      'تعذر الوصول للطابعة ${settings.ip.trim()}:$port.\n'
      'اتأكد إن الموبايل/الكمبيوتر والطابعة على نفس الشبكة (نفس الراوتر)، '
      'وإن IP الطابعة صح (اطبع Self-Test من الطابعة).',
    );
  }
  await settings.save();
}

// ─── طباعة USB مباشرة (كابل — كل الأنظمة الأصلية) ──────────────

/// يبني بايتات الملصقات حسب [settings.mode] (ESC/POS أو TSPL).
/// مشتركة بين الشبكة والـ USB عشان الناتج يبقى واحدا.
Future<List<int>> buildXPrinterLabelBytes(
  BuildContext context,
  List<BarcodeLabelData> items,
  XPrinterSettings settings, {
  int copies = 1,
}) async {
  final clean =
      items.where((e) => e.barcode.trim().isNotEmpty).toList();
  if (clean.isEmpty) {
    throw const XPrinterException('لا توجد باركودات للطباعة.');
  }
  if (settings.mode == XPrinterMode.escPos80) {
    final n = copies <= 0 ? 1 : copies;
    final out = <int>[0x1B, 0x40];
    for (final it in clean) {
      final raster = await renderLabelEscPosRaster(context, it);
      for (var i = 0; i < n; i++) {
        out.addAll(raster);
        out.addAll([0x1B, 0x64, 0x04]);
        if (settings.cut) out.addAll([0x1D, 0x56, 0x01]);
      }
    }
    return out;
  }
  return buildTsplNativeJob(context, items, settings, copies: copies);
}

/// طباعة ملصقات على XPrinter موصلة بكابل USB —
/// لينكس (ملف الجهاز) + أندرويد OTG + ويندوز + macOS.
/// [usbDevice] من الاكتشاف، أو [linuxDevicePath] للينكس.
/// لو مفيش جهاز محدد: يختار أول جهاز مكتشف تلقائيا.
Future<void> printLabelsXPrinterUsb(
  BuildContext context,
  List<BarcodeLabelData> items,
  XPrinterSettings settings, {
  xusb.XUsbPrinterDevice? usbDevice,
  String? linuxDevicePath,
  int copies = 1,
}) async {
  if (!supportsXPrinterUsb) {
    throw const XPrinterException(
      'الـ USB المباشر غير متاح هنا — استخدم الشبكة أو "PDF بمقاس الملصق".',
    );
  }
  var device = usbDevice;
  var devPath = linuxDevicePath;
  if (device == null && (devPath == null || devPath.isEmpty)) {
    final found = await xusb.discoverXPrinterUsbDevices();
    if (found.isEmpty) {
      throw const XPrinterException(
        'لا توجد طابعة USB متصلة.\n'
        'اتأكد إن الكابل متوصل والطابعة منورة '
        '(وعلى الموبايل: لازم وصلة OTG).',
      );
    }
    final hasLinuxPaths =
        found.any((d) => d.id.startsWith('/dev/'));
    if (hasLinuxPaths) {
      // لينكس (ملف الجهاز): اختيار حسب النوع (ريسيت/ملصقات) —
      // لو طابعتين متوصلين يظهر حوار اختيار مع تست بدل أول جهاز.
      try {
        devPath = await resolveUsbPrinterPath(
          context,
          forReceipt: settings.mode == XPrinterMode.escPos80,
          overridePath: linuxDevicePath,
        );
      } on UsbPrinterException catch (e) {
        throw XPrinterException(e.messageAr);
      }
      device = null;
    } else {
      // أندرويد/ويندوز/macOS: اختيار تلقائي (أو المحفوظ سابقا).
      device = found
          .where((d) => d.id == settings.usbDeviceId)
          .firstOrNull;
      device ??= found.first;
      if (device.id.startsWith('/dev/')) devPath = device.id;
    }
  }
  final bytes = await buildXPrinterLabelBytes(
    context,
    items,
    settings,
    copies: copies,
  );
  try {
    await xusb.sendBytesToXPrinterUsb(
      device: device,
      localPath: devPath,
      bytes: bytes,
    );
  } on XPrinterException {
    rethrow;
  } on UsbPrinterException catch (e) {
    // أخطاء ملف الجهاز (صلاحيات/مشغول) برسائلها العربية الجاهزة.
    throw XPrinterException(e.messageAr);
  } catch (e) {
    throw XPrinterException('تعذر الطباعة عبر USB: $e');
  }
  await settings
      .copyWith(
        usbDeviceId: device?.id ?? devPath ?? settings.usbDeviceId,
      )
      .save();
}

// ─── حوار XPrinter الموحد (كل الأنظمة) ────────────────────────

/// يفتح حوار XPrinter: شبكة مباشرة (كل الأنظمة الأصلية) +
/// PDF بمقاس الملصق (كل الأنظمة حتى الويب) + A4.
/// يستدعى من أي شاشة باركود — لا يحتاج صلاحيات خاصة.
Future<void> showXPrinterSheet(
  BuildContext context,
  List<BarcodeLabelData> items, {
  int initialCopies = 1,
}) async {
  final clean =
      items.where((e) => e.barcode.trim().isNotEmpty).toList();
  if (clean.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('لا توجد باركودات للطباعة — أضف باركود أولا.'),
      ),
    );
    return;
  }
  var settings = await XPrinterSettings.load();
  if (!context.mounted) return;

  final ipCtrl = TextEditingController(text: settings.ip);
  final portCtrl = TextEditingController(text: '${settings.port}');
  final copiesCtrl =
      TextEditingController(text: '$initialCopies');
  var mode = settings.mode;
  var presetKey = xprinterLabelPresets.entries
      .where(
        (e) =>
            e.value.$1 == settings.labelWidthMm &&
            e.value.$2 == settings.labelHeightMm,
      )
      .map((e) => e.key)
      .firstOrNull;
  var density = settings.density.toDouble();
  var cut = settings.cut;
  var busy = false;
  String? status;

  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        Future<void> doNetworkPrint() async {
          final copies =
              int.tryParse(copiesCtrl.text.trim()) ?? 0;
          if (copies < 1) {
            setSt(() => status = 'ادخل عدد نسخ أكبر من صفر.');
            return;
          }
          final port = int.tryParse(portCtrl.text.trim()) ?? 9100;
          final s = settings.copyWith(
            ip: ipCtrl.text.trim(),
            port: port,
            mode: mode,
            density: density.round(),
            cut: cut,
          );
          settings = s;
          setSt(() {
            busy = true;
            status = null;
          });
          try {
            await printLabelsXPrinterNetwork(
              context,
              clean,
              s,
              copies: copies,
            );
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'اتطبعت ${clean.length * copies} ملصق على XPrinter (${s.ip}).',
                  ),
                ),
              );
            }
          } on XPrinterException catch (e) {
            setSt(() => status = e.messageAr);
          } catch (e) {
            setSt(() => status = 'تعذر الطباعة: $e');
          } finally {
            if (ctx.mounted) setSt(() => busy = false);
          }
        }

        Future<void> doPdfStickers() async {
          final copies =
              int.tryParse(copiesCtrl.text.trim()) ?? 1;
          Navigator.of(ctx).pop();
          try {
            await printBarcodeStickersPdf(
              context,
              clean,
              copies: copies <= 0 ? 1 : copies,
              widthMm: settings.labelWidthMm,
              heightMm: settings.labelHeightMm,
            );
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تعذر الطباعة: $e')),
              );
            }
          }
        }

        Future<void> doUsbPrint() async {
          final copies =
              int.tryParse(copiesCtrl.text.trim()) ?? 0;
          if (copies < 1) {
            setSt(() => status = 'ادخل عدد نسخ أكبر من صفر.');
            return;
          }
          final s = settings.copyWith(
            mode: mode,
            density: density.round(),
            cut: cut,
          );
          settings = s;
          setSt(() {
            busy = true;
            status = 'بنطبع على USB...';
          });
          try {
            await printLabelsXPrinterUsb(
              context,
              clean,
              s,
              copies: copies,
            );
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'اتطبعت ${clean.length * copies} ملصق على XPrinter (USB).',
                  ),
                ),
              );
            }
          } on XPrinterException catch (e) {
            // أخطاء الصلاحيات/المشغول رسائلها عربية جاهزة من طبقة USB.
            setSt(() => status = e.messageAr);
          } catch (e) {
            setSt(() => status = 'تعذر الطباعة عبر USB: $e');
          } finally {
            if (ctx.mounted) setSt(() => busy = false);
          }
        }

        Future<void> doTest() async {
          final port =
              int.tryParse(portCtrl.text.trim()) ?? 9100;
          setSt(() {
            busy = true;
            status = 'بنحاول نوصل للطابعة...';
          });
          try {
            final ok = await checkNetworkPrinter(
              ip: ipCtrl.text.trim(),
              port: port,
            );
            setSt(
              () => status = ok
                  ? 'تمام — الطابعة متصلة (${ipCtrl.text.trim()}:$port). دوس "طباعة شبكة".'
                  : 'مفيش رد من ${ipCtrl.text.trim()}:$port — اتأكد من الـ IP وإنكم على نفس الشبكة.',
            );
          } catch (e) {
            setSt(() => status = 'تعذر الفحص: $e');
          } finally {
            if (ctx.mounted) setSt(() => busy = false);
          }
        }

        final isTspl = mode == XPrinterMode.tsplLabel;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.print_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'طباعة XPrinter (${clean.length} صنف)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'USB = كابل مباشر (لينكس/أندرويد OTG/ويندوز) — الأفضل لـ XP-420B. '
                  'شبكة = مباشر بدون تعريف. '
                  'PDF = من حوار النظام وتختار XPrinter (شغال حتى على الويب).',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                // وضع الطابعة
                SegmentedButton<XPrinterMode>(
                  segments: const [
                    ButtonSegment(
                      value: XPrinterMode.tsplLabel,
                      icon: Icon(Icons.sticky_note_2_outlined, size: 18),
                      label: Text('ملصقات TSPL'),
                    ),
                    ButtonSegment(
                      value: XPrinterMode.escPos80,
                      icon: Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text('ريسيت 80مم'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) {
                    setSt(() => mode = v.first);
                    settings = settings.copyWith(mode: v.first);
                    settings.save();
                  },
                ),
                const SizedBox(height: 12),
                if (isTspl) ...[
                  DropdownButtonFormField<String>(
                    initialValue: presetKey,
                    decoration: const InputDecoration(
                      labelText: 'مقاس الملصق',
                      prefixIcon: Icon(Icons.photo_size_select_small_outlined),
                    ),
                    items: [
                      for (final e in xprinterLabelPresets.entries)
                        DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.key} مم'),
                        ),
                      const DropdownMenuItem(
                        value: 'custom',
                        child: Text('مخصص...'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == 'custom') {
                        setSt(() => presetKey = 'custom');
                        return;
                      }
                      final dims = xprinterLabelPresets[v]!;
                      setSt(() => presetKey = v);
                      settings = settings.copyWith(
                        labelWidthMm: dims.$1,
                        labelHeightMm: dims.$2,
                      );
                      settings.save();
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'العرض (مم)',
                          ),
                          controller: TextEditingController(
                            text: '${settings.labelWidthMm}',
                          ),
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            if (d != null && d >= 15 && d <= 110) {
                              settings = settings.copyWith(
                                labelWidthMm: d,
                              );
                              settings.save();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'الارتفاع (مم)',
                          ),
                          controller: TextEditingController(
                            text: '${settings.labelHeightMm}',
                          ),
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            if (d != null && d >= 10 && d <= 200) {
                              settings = settings.copyWith(
                                labelHeightMm: d,
                              );
                              settings.save();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('التغميق', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: density,
                          min: 0,
                          max: 15,
                          divisions: 15,
                          label: '${density.round()}',
                          onChanged: (v) =>
                              setSt(() => density = v),
                          onChangeEnd: (v) {
                            settings = settings.copyWith(
                              density: v.round(),
                            );
                            settings.save();
                          },
                        ),
                      ),
                      Text('${density.round()}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ] else ...[
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'قص تلقائي بعد كل ملصق',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: cut,
                    onChanged: (v) {
                      setSt(() => cut = v);
                      settings = settings.copyWith(cut: v);
                      settings.save();
                    },
                  ),
                ],
                const SizedBox(height: 8),
                // الشبكة
                const Text(
                  'الطباعة الشبكية (واي فاي / كابل LAN)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: ipCtrl,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'IP الطابعة',
                          hintText: '192.168.1.100',
                          prefixIcon: Icon(Icons.wifi_outlined),
                        ),
                        onChanged: (_) {
                          settings = settings.copyWith(
                            ip: ipCtrl.text.trim(),
                          );
                          settings.save();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: portCtrl,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'بورت',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: copiesCtrl,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'عدد النسخ لكل صنف',
                    prefixIcon: Icon(Icons.copy_outlined),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      status!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // USB مباشر (كابل) — الأفضل لـ XP-420B على لينكس.
                if (supportsXPrinterUsb) ...[
                  FilledButton.icon(
                    onPressed: busy ? null : doUsbPrint,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.usb_outlined,
                            size: 18,
                          ),
                    label: Text(
                      isTspl
                          ? 'طباعة USB مباشر TSPL (XP-420B)'
                          : 'طباعة USB مباشر ESC/POS',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (supportsXPrinterNetwork) ...[
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : doTest,
                          icon: const Icon(
                            Icons.wifi_find_outlined,
                            size: 18,
                          ),
                          label: const Text('فحص الاتصال'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: busy ? null : doNetworkPrint,
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.print_outlined,
                                  size: 18,
                                ),
                          label: Text(
                            isTspl
                                ? 'طباعة شبكة TSPL'
                                : 'طباعة شبكة ESC/POS',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: busy ? null : doPdfStickers,
                  icon: const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 18,
                  ),
                  label: Text(
                    kIsWeb
                        ? 'طباعة PDF (اختر XPrinter من الحوار)'
                        : 'PDF بمقاس الملصق (${settings.labelWidthMm.toStringAsFixed(0)}×${settings.labelHeightMm.toStringAsFixed(0)}مم)',
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'لو مش عارف IP الطابعة: اطبع Self-Test (دوس زرار FEED وانت بتفتح الطابعة) هيطبع ورقة فيها الـ IP. '
                  'ولازم الموبايل والطابعة على نفس الراوتر.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
