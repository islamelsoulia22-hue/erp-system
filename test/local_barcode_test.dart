// باركود الأصناف اللوكال: حفظ/قراءة/منع التكرار على in-memory.
// التشغيل: flutter test test/local_barcode_test.dart
import 'dart:io';

import 'package:accounting_system/core/local/local_database.dart';
import 'package:accounting_system/core/local/local_products.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// قاعدة ملف مؤقت لكل تست (الـ in-memory المشتركة تتعارض بين التستات).
Future<Database> _openTestDb() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sanad_barcode_test_');
  final db = await databaseFactoryFfi.openDatabase(
    p.join(dir.path, 't.db'),
  );
  for (final stmt in LocalDatabase.schemaV1) {
    await db.execute(stmt);
  }
  for (final stmt in LocalDatabase.migrationV1toV2) {
    await db.execute(stmt);
  }
  return db;
}

void main() {
  test('barcode roundtrip on product page', () async {
    final db = await _openTestDb();
    try {
      final repo = LocalProductsRepository(() async => db);
      final id = await repo.create(name: 'سجاير');
      expect(await repo.primaryBarcodeOf(id), isNull);

      await repo.setBarcode(productId: id, barcode: '62211628');
      expect(await repo.primaryBarcodeOf(id), '62211628');

      // تعديل نفس الصنف.
      await repo.setBarcode(productId: id, barcode: '62210000');
      expect(await repo.primaryBarcodeOf(id), '62210000');

      // الصفحة تعرض الباركود.
      final paged = await repo.page();
      expect(paged.items.first.primaryBarcode, '62210000');

      // التفاصيل تعرض الباركود.
      final got = await repo.getById(id);
      expect(got?.primaryBarcode, '62210000');
    } finally {
      await db.close();
    }
  });

  test('duplicate barcode rejected across products', () async {
    final db = await _openTestDb();
    try {
      final repo = LocalProductsRepository(() async => db);
      final a = await repo.create(name: 'صنف أ');
      final b = await repo.create(name: 'صنف ب');
      await repo.setBarcode(productId: a, barcode: '111');
      var threwDup = false;
      try {
        await repo.setBarcode(productId: b, barcode: '111');
      } on LocalDataFailure {
        threwDup = true;
      }
      expect(threwDup, isTrue, reason: 'duplicate must throw');
      // الفارغ مرفوض.
      var threwEmpty = false;
      try {
        await repo.setBarcode(productId: b, barcode: '  ');
      } on LocalDataFailure {
        threwEmpty = true;
      }
      expect(threwEmpty, isTrue, reason: 'empty must throw');
    } finally {
      await db.close();
    }
  });
}
