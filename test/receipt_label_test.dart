// اختبار توليد ملصق ESC/POS حقيقي (سجاير - 62211628) بنفس
// كود الإنتاج، لطباعته على طابعة الريسيت والتحقق منه.
// التشغيل: flutter test test/receipt_label_test.dart
// الناتج: /tmp/sagayer_label.bin
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:accounting_system/core/pdf/barcode_pdf.dart';
import 'package:accounting_system/core/printing/usb_receipt_printer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render sagayer label to escpos file', (tester) async {
    // تحميل خط Cairo الحقيقي عشان العربي يتصور صح
    // (بيئة الاختبار افتراضيا بخط Ahem).
    final fontBytes = File('assets/fonts/Cairo.ttf').readAsBytesSync();
    final loader = FontLoader('Cairo')
      ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
    await loader.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Cairo'),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    final ctx = tester.element(find.byType(Scaffold));
    // دالة الإنتاج بتستنى endOfFrame + مهلة — نحرك الفريمات
    // يدويا عشان زمن الاختبار الوهمي ميعلقش.
    final future = renderLabelEscPosRaster(
      ctx,
      const BarcodeLabelData(
        productId: 'demo',
        productName: 'سجاير',
        barcode: '62211628',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    final raster = await future;
    final out = <int>[
      0x1B, 0x40, // ESC @
      ...raster,
      0x1B, 0x64, 0x04, // feed
      0x1D, 0x56, 0x01, // cut
    ];
    File('/tmp/sagayer_label.bin').writeAsBytesSync(out);
    debugPrint('wrote ${out.length} escpos bytes');
    expect(out.length, greaterThan(1000));
  });
}
