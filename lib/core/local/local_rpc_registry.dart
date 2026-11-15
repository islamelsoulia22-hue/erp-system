import 'local_database.dart';
import 'local_query.dart';
import 'local_trade_rpc.dart';

/// تسجيل دوال RPC المحلية (منطق السيرفر منقول لـ Dart).
/// تُستدعى تلقائيا مع أول LocalDbClient (idempotent).
void ensureLocalRpcRegistered() {
  _productsRpc();
  ensureLocalTradeRpcRegistered();
}

bool _doneProducts = false;

/// دوال الأصناف (من migrations 0024).
void _productsRpc() {
  if (_doneProducts) return;
  _doneProducts = true;

  /// حذف قسري: يمنع المحجوز، ويمسح المخزون/الحركات/
  /// السيريال/الباركود ثم الصنف. رسائل الخطأ بنفس
  /// نصوص السيرفر ليعيد mapSupabaseError نفس التحويل.
  LocalRpc.register('delete_product_force', (db, params) async {
    final id = params['p_product_id'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('PRODUCT_NOT_FOUND');
    }
    final prod = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (prod.isEmpty) throw StateError('PRODUCT_NOT_FOUND');
    final sums = await db.rawQuery(
      'SELECT COALESCE(SUM(reserved_quantity), 0) AS r '
      'FROM warehouse_stock WHERE product_id = ?',
      [id],
    );
    final reserved = sums.first['r'];
    if (reserved is num && reserved > 0) {
      throw StateError(
        'HAS_RESERVED_STOCK: cannot force-delete with reserved $reserved',
      );
    }
    await db.delete(
      'warehouse_stock',
      where: 'product_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'product_serials',
      where: 'product_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'product_barcodes',
      where: 'product_id = ?',
      whereArgs: [id],
    );
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    try {
      await db.insert('audit_logs', {
        'id': LocalDatabase.newId(),
        'action': 'DELETE_FORCE',
        'entity_type': 'PRODUCT',
        'entity_id': id,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
    return null;
  });
}
