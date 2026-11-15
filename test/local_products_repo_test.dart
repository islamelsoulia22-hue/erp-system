// إثبات المسار: ProductsRepository (كود السحابة بدون تعديل)
// يعمل على SQLite عبر LocalDbClient.
// التشغيل: flutter test test/local_products_repo_test.dart
import 'dart:io';

import 'package:accounting_system/core/errors/failures.dart';
import 'package:accounting_system/core/local/local_database.dart';
import 'package:accounting_system/core/local/local_query.dart';
import 'package:accounting_system/features/products/data/products_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _open() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sanad_prod_test_');
  final db = await databaseFactoryFfi.openDatabase(
    p.join(dir.path, 't.db'),
    options: OpenDatabaseOptions(
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  for (final stmt in LocalDatabase.schemaV1) {
    await db.execute(stmt);
  }
  for (final stmt in LocalDatabase.migrationV1toV2) {
    await db.execute(stmt);
  }
  for (final stmt in LocalDatabase.migrationV2toV3) {
    await db.execute(stmt);
  }
  await LocalDatabase.applyV4(db);
  return db;
}

void main() {
  test('products CRUD + search + barcodes on sqlite', () async {
    final db = await _open();
    try {
      LocalSession.currentUserId = 'tester';
      final repo = ProductsRepository(LocalDbClient(() async => db));

      final created = await repo.create({
        'sku': 'SAG-1',
        'name': 'سجاير',
        'purchase_price': 40,
        'sale_price': 50,
      });
      expect(created.id.isNotEmpty, isTrue);
      expect(created.name, 'سجاير');
      expect(created.taxable, isTrue);

      await repo.addBarcode(
        productId: created.id,
        barcode: '62211628',
        isPrimary: true,
      );
      final byCode = await repo.findByBarcode('62211628');
      expect(byCode?.id, created.id);
      expect(byCode?.primaryBarcode, '62211628');

      final paged = await repo.searchPaged(query: 'سجاير');
      expect(paged.total, 1);
      expect(paged.items.first.primaryBarcode, '62211628');

      final codes = await repo.barcodesOf(created.id);
      expect(codes.length, 1);

      final updated = await repo.update(created.id, {'sale_price': 55});
      expect(updated.salePrice, 55);

      // فئات ووحدات وخامات.
      final cat = await repo.createCategory(name: 'دخان', nameAr: 'دخان');
      expect(cat.name, 'دخان');
      expect((await repo.categories()).length, greaterThanOrEqualTo(5));
      final unit = await repo.createUnit(code: 'PCS2', name: 'Piece2');
      expect(unit.code, 'PCS2');
      expect((await repo.units()).length, greaterThanOrEqualTo(7));
      final mats = await repo.barcodeMaterials();
      expect(mats.length, 6);

      // سيريالات.
      await repo.replaceSerials(created.id, ['SN1', 'SN2']);
      expect(await repo.serialsOf(created.id), ['SN1', 'SN2']);

      // حذف محظور بوجود مخزون → LinkedRecordFailure.
      await db.insert('warehouse_stock', {
        'warehouse_id': 'w1',
        'product_id': created.id,
        'quantity': 5,
      });
      var blocked = false;
      try {
        await repo.deleteProduct(created.id);
      } on LinkedRecordFailure {
        blocked = true;
      }
      expect(blocked, isTrue);

      // حذف قسري يمسح كل حاجة.
      await repo.deleteProductForce(created.id);
      expect(await repo.getById(created.id), isNull);
      expect(await repo.findByBarcode('62211628'), isNull);
    } finally {
      LocalSession.clear();
      await db.close();
    }
  });
}
