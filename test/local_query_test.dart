// محول SQLite بنفس واجهة Supabase — اختبار شامل.
// التشغيل: flutter test test/local_query_test.dart
import 'package:accounting_system/core/local/local_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _open() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(
    'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT, is_active INTEGER DEFAULT 1)',
  );
  await db.execute(
    'CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT, sku TEXT, '
    'price REAL DEFAULT 0, category_id TEXT, is_active INTEGER DEFAULT 1)',
  );
  await db.execute(
    'CREATE TABLE barcodes (id TEXT PRIMARY KEY, product_id TEXT, '
    'barcode TEXT UNIQUE, is_primary INTEGER DEFAULT 0)',
  );
  return db;
}

void main() {
  test('select/eq/order/range/ilike/count', () async {
    final db = await _open();
    try {
      final c = LocalDbClient(() async => db);
      await db.insert('products', {'id': 'p1', 'name': 'سجاير', 'sku': 'S1', 'price': 50.0, 'is_active': 1});
      await db.insert('products', {'id': 'p2', 'name': 'سكر', 'sku': 'S2', 'price': 30.0, 'is_active': 1});
      await db.insert('products', {'id': 'p3', 'name': 'ملح', 'sku': 'S3', 'price': 10.0, 'is_active': 0});

      // eq + bool mapping (int 1 → true).
      final active = await c.from('products').select().eq('is_active', true) as List;
      expect(active.length, 2);
      expect(active.first['is_active'], isTrue);

      // or + ilike.
      final found = await c
          .from('products')
          .select()
          .eq('is_active', true)
          .or('name.ilike.%سج%,sku.ilike.%S2%') as List;
      expect(found.length, 2);

      // order + range.
      final page = await c
          .from('products')
          .select()
          .order('price', ascending: false)
          .range(0, 1) as List;
      expect(page.length, 2);
      expect(page.first['id'], 'p1');

      // count.
      final res = await c.from('products').select('id').eq('is_active', true).count();
      expect(res.count, 2);

      // single / maybeSingle.
      final one = await c.from('products').select().eq('id', 'p1').single() as Map;
      expect(one['name'], 'سجاير');
      final none = await c.from('products').select().eq('id', 'nope').maybeSingle();
      expect(none, isNull);
    } finally {
      await db.close();
    }
  });

  test('embeds single + list', () async {
    final db = await _open();
    try {
      final c = LocalDbClient(() async => db);
      await db.insert('categories', {'id': 'c1', 'name': 'دخان', 'is_active': 1});
      await db.insert('products', {'id': 'p1', 'name': 'سجاير', 'category_id': 'c1', 'is_active': 1});
      await db.insert('barcodes', {'id': 'b1', 'product_id': 'p1', 'barcode': '622', 'is_primary': 1});
      await db.insert('barcodes', {'id': 'b2', 'product_id': 'p1', 'barcode': '623', 'is_primary': 0});

      final rows = await c
          .from('products')
          .select('id, name, categories ( name ), barcodes ( barcode, is_primary )')
          .eq('id', 'p1') as List;
      expect(rows.length, 1);
      final r = rows.first as Map;
      expect((r['categories'] as Map)['name'], 'دخان');
      final codes = r['barcodes'] as List;
      expect(codes.length, 2);
      expect(codes.first['barcode'], '622');
    } finally {
      await db.close();
    }
  });

  test('insert/update/delete/upsert returning', () async {
    final db = await _open();
    try {
      final c = LocalDbClient(() async => db);
      final ins = await c
          .from('products')
          .insert({'id': 'p9', 'name': 'شاي', 'price': 20.0, 'is_active': true})
          .select()
          .single() as Map;
      expect(ins['name'], 'شاي');
      expect(ins['is_active'], isTrue);

      final upd = await c
          .from('products')
          .update({'price': 25.0})
          .eq('id', 'p9')
          .select()
          .single() as Map;
      expect(upd['price'], 25.0);

      await c.from('products').upsert(
        {'id': 'p9', 'name': 'شاي أخضر', 'price': 27.0},
        onConflict: 'id',
      );
      final got = await c.from('products').select().eq('id', 'p9').single() as Map;
      expect(got['name'], 'شاي أخضر');

      final del = await c.from('products').delete().eq('id', 'p9').select() as List;
      expect(del.length, 1);
      final none = await c.from('products').select().eq('id', 'p9').maybeSingle();
      expect(none, isNull);
    } finally {
      await db.close();
    }
  });

  test('nested embeds + !inner from child side', () async {
    final db = await _open();
    try {
      final c = LocalDbClient(() async => db);
      await db.execute(
        'CREATE TABLE units (id TEXT PRIMARY KEY, name TEXT)',
      );
      await db.execute(
        'ALTER TABLE products ADD COLUMN unit_id TEXT',
      );
      await db.insert('units', {'id': 'u1', 'name': 'قطعة'});
      await db.insert(
        'categories',
        {'id': 'c1', 'name': 'دخان', 'is_active': 1},
      );
      await db.execute(
        "ALTER TABLE categories ADD COLUMN dummy TEXT",
      );
      await db.insert('products', {
        'id': 'p1',
        'name': 'سجاير',
        'category_id': 'c1',
        'unit_id': 'u1',
        'is_active': 1,
      });
      await db.insert('products', {
        'id': 'p2',
        'name': 'يتيم',
        'is_active': 1,
      });
      await db.insert('barcodes', {
        'id': 'b1',
        'product_id': 'p1',
        'barcode': '622',
        'is_primary': 1,
      });
      await db.insert('barcodes', {
        'id': 'b9',
        'product_id': 'ghost',
        'barcode': '000',
        'is_primary': 1,
      });

      // من جهة الابن مع تداخل: منتج + فئته.
      final rows = await c
          .from('barcodes')
          .select(
            'barcode, products!inner(id, name, categories ( name ))',
          )
          .eq('barcode', '622')
          .maybeSingle() as Map?;
      expect(rows, isNotNull);
      final p = rows!['products'] as Map;
      expect(p['name'], 'سجاير');
      expect((p['categories'] as Map)['name'], 'دخان');

      // !inner يسقط الباركود اليتيم (بدون منتج).
      final all = await c
          .from('barcodes')
          .select('barcode, products!inner(id)') as List;
      expect(all.length, 1);
      expect((all.first as Map)['barcode'], '622');

      // inFilter alias.
      final inn = await c
          .from('products')
          .select('id')
          .inFilter('id', ['p1', 'p2']) as List;
      expect(inn.length, 2);
    } finally {
      await db.close();
    }
  });

  test('gte/lt/in_/not/is_', () async {
    final db = await _open();
    try {
      final c = LocalDbClient(() async => db);
      await db.insert('products', {'id': 'p1', 'name': 'A', 'price': 10.0, 'sku': null});
      await db.insert('products', {'id': 'p2', 'name': 'B', 'price': 50.0, 'sku': 'X'});

      final g = await c.from('products').select('id').gte('price', 20).lt('price', 100) as List;
      expect(g.length, 1);

      final inn = await c.from('products').select('id').in_('id', ['p1', 'p2', 'px']) as List;
      expect(inn.length, 2);

      final nn = await c.from('products').select('id').not('sku', 'is', null) as List;
      expect(nn.length, 1);

      final nl = await c.from('products').select('id').is_('sku', null) as List;
      expect(nl.length, 1);
    } finally {
      await db.close();
    }
  });
}
