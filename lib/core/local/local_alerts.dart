import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';

/// محرك تنبيهات المخزون اللوكال — نفس قواعد السحابة
/// (ترحيلات 0034/0035) منفذة بالدارت:
/// - المتاح > صفر: يقفل تنبيهات النفاذ NEW.
/// - فوق الحد الأدنى: يقفل تنبيهات الحد NEW.
/// - نواقص PENDING/ORDERED المغطاة (المطلوب <= المتاح)
///   تتقفل DONE تلقائيا.
/// - صفر: تنبيه نفاذ + تسجيل/تزويد نواقص تلقائي.
/// يعمل على DatabaseExecutor فيشتغل جوه الترانزاكشن.
Future<void> evaluateStockLevels(
  DatabaseExecutor db, {
  required String warehouseId,
  required String productId,
}) async {
  double n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  final stock = await db.query(
    'warehouse_stock',
    where: 'warehouse_id = ? AND product_id = ?',
    whereArgs: [warehouseId, productId],
    limit: 1,
  );
  if (stock.isEmpty) return;
  final avail =
      n(stock.first['quantity']) - n(stock.first['reserved_quantity']);

  final prows = await db.query(
    'products',
    columns: ['minimum_stock', 'supplier_id'],
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );
  if (prows.isEmpty) return;
  final min = n(prows.first['minimum_stock']);
  final supplierId = prows.first['supplier_id'] as String?;

  Future<bool> hasAlert(String level) async {
    final r = await db.query(
      'stock_alerts',
      columns: ['id'],
      where: 'product_id = ? AND warehouse_id = ? AND level = ? AND status = ?',
      whereArgs: [productId, warehouseId, level, 'NEW'],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<void> resolveAlerts(String level) async {
    await db.update(
      'stock_alerts',
      {'status': 'RESOLVED'},
      where: 'product_id = ? AND warehouse_id = ? AND level = ? AND status = ?',
      whereArgs: [productId, warehouseId, level, 'NEW'],
    );
  }

  // قفل القديم اللي اتحل.
  if (avail > 0) {
    await resolveAlerts('OUT_OF_STOCK');
  }
  if (min <= 0 || avail > min) {
    await resolveAlerts('MINIMUM');
  }

  // النواقص المغطاة تتقفل تلقائيا.
  if (avail > 0) {
    await db.update(
      'shortages',
      {'status': 'DONE'},
      where:
          'product_id = ? AND warehouse_id = ? AND status IN (?, ?) AND required_qty <= ?',
      whereArgs: [productId, warehouseId, 'PENDING', 'ORDERED', avail],
    );
  }

  // نفذ (صفر أو أقل): تنبيه + نواقص.
  if (avail <= 0) {
    if (!await hasAlert('OUT_OF_STOCK')) {
      final aid = LocalDatabase.newId();
      await db.insert('stock_alerts', {
        'id': aid,
        'product_id': productId,
        'warehouse_id': warehouseId,
        'level': 'OUT_OF_STOCK',
        'status': 'NEW',
        'available_qty': avail,
        'created_at': DateTime.now().toIso8601String(),
      });
      final need = min > 0 ? min : 1.0;
      final existing = await db.query(
        'shortages',
        columns: ['id', 'required_qty'],
        where: 'product_id = ? AND warehouse_id = ? AND status = ?',
        whereArgs: [productId, warehouseId, 'PENDING'],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final cur = n(existing.first['required_qty']);
        await db.update(
          'shortages',
          {'required_qty': cur + need},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await db.insert('shortages', {
          'id': LocalDatabase.newId(),
          'product_id': productId,
          'warehouse_id': warehouseId,
          'supplier_id': supplierId,
          'required_qty': need,
          'status': 'PENDING',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }
    return;
  }

  // وصل الحد الأدنى.
  if (min > 0 && avail <= min) {
    if (!await hasAlert('MINIMUM')) {
      await db.insert('stock_alerts', {
        'id': LocalDatabase.newId(),
        'product_id': productId,
        'warehouse_id': warehouseId,
        'level': 'MINIMUM',
        'status': 'NEW',
        'available_qty': avail,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }
}
