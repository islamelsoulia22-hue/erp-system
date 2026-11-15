import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_alerts.dart';
import 'local_database.dart';
import 'local_products.dart' show LocalDataFailure, LocalProduct;

class LocalWarehouse {
  final String id;
  final String code;
  final String name;
  final bool isActive;
  const LocalWarehouse({
    required this.id,
    required this.code,
    required this.name,
    required this.isActive,
  });

  factory LocalWarehouse.fromMap(Map<String, Object?> m) {
    return LocalWarehouse(
      id: (m['id'] as String?) ?? '',
      code: (m['code'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      isActive: (m['is_active'] as num? ?? 1) != 0,
    );
  }
}

/// سطر مخزون: الصنف + الكمية + المحجوز + المتاح.
class LocalStockLine {
  final LocalProduct product;
  final double quantity;
  final double reserved;
  const LocalStockLine({
    required this.product,
    required this.quantity,
    required this.reserved,
  });

  double get available => quantity - reserved;
}

class LocalWarehousesRepository {
  final Future<Database> Function() _open;
  LocalWarehousesRepository(this._open);

  Future<List<LocalWarehouse>> list({bool onlyActive = true}) async {
    final db = await _open();
    final rows = await db.query(
      'warehouses',
      where: onlyActive ? 'is_active = 1' : null,
      orderBy: 'name',
    );
    return [for (final r in rows) LocalWarehouse.fromMap(r)];
  }

  Future<LocalWarehouse?> getById(String id) async {
    final db = await _open();
    final rows = await db.query(
      'warehouses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalWarehouse.fromMap(rows.first);
  }

  Future<String> create({required String name, String? code}) async {
    if (name.trim().isEmpty) {
      throw const LocalDataFailure('اسم المخزن مطلوب.');
    }
    final db = await _open();
    final id = LocalDatabase.newId();
    await db.insert('warehouses', {
      'id': id,
      'code': code?.trim().isEmpty == true ? null : code?.trim(),
      'name': name.trim(),
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> setActive(String id, bool active) async {
    final db = await _open();
    await db.update(
      'warehouses',
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف المخزن — مرفوض لو فيه أرصدة.
  Future<void> remove(String id) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM warehouse_stock WHERE warehouse_id = ?',
      [id],
    );
    if (((rows.first['c'] as num?)?.toInt() ?? 0) > 0) {
      throw const LocalDataFailure('المخزن فيه أرصدة — لا يمكن حذفه.');
    }
    await db.delete('warehouses', where: 'id = ?', whereArgs: [id]);
  }

  /// أرصدة مخزن: تنقصها الأصناف الموقوفة؟ لا — كل
  /// الأرصدة حتى لو الصنف موقوف (رصيد حقيقي).
  Future<List<LocalStockLine>> stockOf(String warehouseId) async {
    final db = await _open();
    final rows = await db.rawQuery(
      '''
SELECT s.quantity, s.reserved_quantity, p.*
FROM warehouse_stock s
JOIN products p ON p.id = s.product_id
WHERE s.warehouse_id = ?
ORDER BY p.name
''',
      [warehouseId],
    );
    double n(Object? v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return [
      for (final r in rows)
        LocalStockLine(
          product: LocalProduct.fromMap(r),
          quantity: n(r['quantity']),
          reserved: n(r['reserved_quantity']),
        ),
    ];
  }

  /// تسوية مخزون (+/-) مع حركة مسجلة + تقييم
  /// التنبيهات والنواقص تلقائيا.
  Future<void> adjust({
    required String warehouseId,
    required String productId,
    required double delta,
    String? notes,
  }) async {
    if (delta == 0) {
      throw const LocalDataFailure('ادخل كمية غير صفرية.');
    }
    final db = await _open();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'warehouse_stock',
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: [warehouseId, productId],
      );
      final before = rows.isEmpty
          ? 0.0
          : ((rows.first['quantity'] as num?)?.toDouble() ?? 0);
      final after = before + delta;
      if (after < 0) {
        throw const LocalDataFailure('الرصيد لا يكفي للتخفيض.');
      }
      if (rows.isEmpty) {
        await txn.insert('warehouse_stock', {
          'warehouse_id': warehouseId,
          'product_id': productId,
          'quantity': after,
          'reserved_quantity': 0,
        });
      } else {
        await txn.update(
          'warehouse_stock',
          {'quantity': after},
          where: 'warehouse_id = ? AND product_id = ?',
          whereArgs: [warehouseId, productId],
        );
      }
      await txn.insert('stock_movements', {
        'id': LocalDatabase.newId(),
        'warehouse_id': warehouseId,
        'product_id': productId,
        'movement_type': delta > 0 ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
        'quantity': delta.abs(),
        'before_quantity': before,
        'after_quantity': after,
        'reference_type': 'STOCK_ADJUSTMENT',
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
      await evaluateStockLevels(
        txn,
        warehouseId: warehouseId,
        productId: productId,
      );
    });
  }
}

final localWarehousesRepositoryProvider = Provider<LocalWarehousesRepository>((
  ref,
) {
  return LocalWarehousesRepository(() => LocalDatabase.instance.db);
});

final localWarehousesProvider =
    FutureProvider.autoDispose<List<LocalWarehouse>>((ref) {
      return ref.watch(localWarehousesRepositoryProvider).list();
    });

/// أرصدة مخزن واحد.
final localStockProvider = FutureProvider.autoDispose
    .family<List<LocalStockLine>, String>((ref, warehouseId) {
      return ref.watch(localWarehousesRepositoryProvider).stockOf(warehouseId);
    });
