// تحقق سريع من منطق XPrinter الخالص (بدون ويدجت/شبكة).
// التشغيل: flutter test test/xprinter_logic_test.dart
import 'package:accounting_system/core/printing/xprinter_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mmToDots يحسب نقاط 203dpi صح', () {
    expect(mmToDots(40), 320); // 40*203/25.4 = 319.5 → 320
    expect(mmToDots(30), 240); // 30*203/25.4 = 239.7 → 240
    expect(mmToDots(80), 639); // 80*203/25.4 = 639.3 → 639
  });

  test('مقاسات الملصقات الجاهزة موجودة', () {
    expect(xprinterLabelPresets.containsKey('40 × 30 (الأشهر)'), isTrue);
    final dims = xprinterLabelPresets['40 × 30 (الأشهر)']!;
    expect(dims.$1, 40);
    expect(dims.$2, 30);
  });

  test('الإعدادات الافتراضية = TSPL 40×30 بورت 9100', () {
    const s = XPrinterSettings();
    expect(s.mode, XPrinterMode.tsplLabel);
    expect(s.labelWidthMm, 40);
    expect(s.labelHeightMm, 30);
    expect(s.port, 9100);
    expect(s.density, 8);
  });

  test('copyWith يغير المطلوب فقط', () {
    const s = XPrinterSettings();
    final c = s.copyWith(ip: '192.168.1.50', mode: XPrinterMode.escPos80);
    expect(c.ip, '192.168.1.50');
    expect(c.mode, XPrinterMode.escPos80);
    expect(c.port, 9100);
    expect(c.labelWidthMm, 40);
  });

  test('موضع BITMAP متمركز في نص ليبل 38×25', () {
    // 38مم = 304 نقاط، 25مم = 200 نقطة (203dpi).
    expect(mmToDots(38), 304);
    expect(mmToDots(25), 200);
    // صورة بنفس عرض الليبل وارتفاع 105: تتوسط رأسيا
    // y = (200-105)~/2 = 47، وتنزاح 6 يمينا.
    final o = tsplBitmapOrigin(
      labelWidthDots: 304,
      labelHeightDots: 200,
      imgWidthDots: 304,
      imgHeightDots: 105,
    );
    expect(o.x, 6);
    expect(o.y, 47);
  });

  test('موضع BITMAP لصورة أضيق: توسيط + إزاحة يمين', () {
    final o = tsplBitmapOrigin(
      labelWidthDots: 304,
      labelHeightDots: 200,
      imgWidthDots: 200,
      imgHeightDots: 100,
    );
    expect(o.x, (304 - 200) ~/ 2 + 6);
    expect(o.y, (200 - 100) ~/ 2);
  });

  test('موضع BITMAP لصورة أطول من الليبل: يثبت فوق', () {
    final o = tsplBitmapOrigin(
      labelWidthDots: 304,
      labelHeightDots: 200,
      imgWidthDots: 304,
      imgHeightDots: 300,
    );
    expect(o.y, 8);
  });

  test('الأسماء اللاتينية تطبع TEXT أصلي والعربي شريط مصور', () {
    expect(isTsplNativeText('SAGAYER 123'), isTrue);
    expect(isTsplNativeText('سجاير'), isFalse);
    expect(isTsplNativeText('لبن 1L'), isFalse);
  });

  test('عرض Code128 التقديري يركز الباركود في 38مم', () {
    // 62211628 أرقام زوجية → Code C: (11*(4+2)+13)*2+20 = 178.
    final est = estimateCode128Dots('62211628', 2);
    expect(est, 178);
    final bx = ((304 - est) ~/ 2).clamp(4, 304 - 10);
    expect(bx, 63); // قريب من 70 المجربة في ملصق SAGAYER
    // باركود طويل جدا: التقدير يكبر (المنشئ ينزل narrow=1).
    expect(estimateCode128Dots('622116281234567890ABC', 2), greaterThan(304 - 16));
  });
}
