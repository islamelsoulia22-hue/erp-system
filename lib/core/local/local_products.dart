import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';

/// خطأ بيانات محلي برسالة عربية جاهزة للعرض.
class LocalDataFailure implements Exception {
  final String messageAr;
  const LocalDataFailure(this.messageAr);

  @override
  String toString() => messageAr;
}

/// صنف محلي (نسخة الجهاز).
class LocalProduct {
  final String id;
  final String sku;
  final String name;
  final double purchasePrice;
  final double salePrice;
  final double minimumStock;
  final bool isActive;
  /// الباركود الأساسي (من product_barcodes) — فارغ لو بدون باركود.
  final String primaryBarcode;
  const LocalProduct({
    required this.id,
    required this.sku,
    required this.name,
    required this.purchasePrice,
    required this.salePrice,
    required this.minimumStock,
    required this.isActive,
    this.primaryBarcode = '',
  });

  static double _n(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory LocalProduct.fromMap(Map<String, Object?> m) {
    return LocalProduct(
      id: (m['id'] as String?) ?? '',
      sku: (m['sku'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      purchasePrice: _n(m['purchase_price']),
      salePrice: _n(m['sale_price']),
      minimumStock: _n(m['minimum_stock']),
      isActive: (m['is_active'] as num? ?? 1) != 0,
      primaryBarcode: (m['primary_barcode'] as String?) ?? '',
    );
  }

  /// نسخة بحقل باركود محدث (بعد الحفظ بدون إعادة تحميل الصفحة).
  LocalProduct copyWithBarcode(String barcode) => LocalProduct(
        id: id,
        sku: sku,
        name: name,
        purchasePrice: purchasePrice,
        salePrice: salePrice,
        minimumStock: minimumStock,
        isActive: isActive,
        primaryBarcode: barcode,
      );
}

/// أصناف النسخة اللوكال (SQLite). يأخذ دالة فتح القاعدة
/// كحقن عشان الاختبار بقاعدة in-memory.
class LocalProductsRepository {
  final Future<Database> Function() _open;
  LocalProductsRepository(this._open);

  static const int pageSize = 20;

  String _like(String q) =>
      q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  /// صفحة أصناف + الإجمالي (بحث بالاسم/SKU).
  Future<({List<LocalProduct> items, int total})> page({
    String query = '',
    int page = 0,
    bool onlyActive = true,
  }) async {
    final db = await _open();
    final q = query.trim();
    final where = <String>[];
    final args = <Object?>[];
    if (onlyActive) where.add('is_active = 1');
    if (q.isNotEmpty) {
      where.add("(name LIKE ? ESCAPE '\\' OR sku LIKE ? ESCAPE '\\')");
      final like = '%${_like(q)}%';
      args.addAll([like, like]);
    }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    const join =
        'LEFT JOIN (SELECT product_id, barcode AS primary_barcode '
        'FROM product_barcodes WHERE is_primary = 1) b '
        'ON b.product_id = products.id';
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM products $w',
      args,
    );
    final total = (totalRows.first['c'] as num?)?.toInt() ?? 0;
    final rows = await db.rawQuery(
      'SELECT products.*, b.primary_barcode FROM products $join $w '
      'ORDER BY products.name LIMIT ? OFFSET ?',
      [...args, pageSize, page * pageSize],
    );
    return (
      items: [for (final r in rows) LocalProduct.fromMap(r)],
      total: total,
    );
  }

  Future<LocalProduct?> getById(String id) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT products.*, b.primary_barcode FROM products '
      'LEFT JOIN (SELECT product_id, barcode AS primary_barcode '
      'FROM product_barcodes WHERE is_primary = 1) b '
      'ON b.product_id = products.id '
      'WHERE products.id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return LocalProduct.fromMap(rows.first);
  }

  /// الباركود الأساسي لصنف (أو null لو بدون).
  Future<String?> primaryBarcodeOf(String productId) async {
    final db = await _open();
    final rows = await db.query(
      'product_barcodes',
      columns: ['barcode'],
      where: 'product_id = ? AND is_primary = 1',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['barcode'] as String?;
  }

  /// حفظ/تعديل الباركود الأساسي للصنف.
  /// يرفض الفارغ والمكرر على صنف آخر برسالة عربية.
  Future<void> setBarcode({
    required String productId,
    required String barcode,
  }) async {
    final code = barcode.trim();
    if (code.isEmpty) {
      throw const LocalDataFailure('ادخل رقم الباركود أولا.');
    }
    final db = await _open();
    final clash = await db.query(
      'product_barcodes',
      columns: ['product_id'],
      where: 'barcode = ? AND product_id != ?',
      whereArgs: [code, productId],
      limit: 1,
    );
    if (clash.isNotEmpty) {
      throw const LocalDataFailure('الباركود مستخدم لصنف آخر.');
    }
    final mine = await db.query(
      'product_barcodes',
      columns: ['id'],
      where: 'product_id = ? AND is_primary = 1',
      whereArgs: [productId],
      limit: 1,
    );
    if (mine.isEmpty) {
      await db.insert('product_barcodes', {
        'id': LocalDatabase.newId(),
        'product_id': productId,
        'barcode': code,
        'barcode_type': 'CODE128',
        'is_primary': 1,
      });
    } else {
      await db.update(
        'product_barcodes',
        {'barcode': code},
        where: 'id = ?',
        whereArgs: [mine.first['id']],
      );
    }
  }

  /// إنشاء صنف جديد. الاسم إجباري.
  Future<String> create({
    required String name,
    String? sku,
    double purchasePrice = 0,
    double salePrice = 0,
    double minimumStock = 0,
  }) async {
    if (name.trim().isEmpty) {
      throw const LocalDataFailure('اسم الصنف مطلوب.');
    }
    if (purchasePrice < 0 || salePrice < 0) {
      throw const LocalDataFailure('الأسعار لا تكون بالسالب.');
    }
    final db = await _open();
    final id = LocalDatabase.newId();
    await db.insert('products', {
      'id': id,
      'sku': sku?.trim().isEmpty == true ? null : sku?.trim(),
      'name': name.trim(),
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'minimum_stock': minimumStock,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> setActive(String id, bool active) async {
    final db = await _open();
    await db.update(
      'products',
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف نهائي للصنف (مع باركوداته).
  Future<void> remove(String id) async {
    final db = await _open();
    await db.delete(
      'product_barcodes',
      where: 'product_id = ?',
      whereArgs: [id],
    );
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }
}

final localProductsRepositoryProvider = Provider<LocalProductsRepository>((
  ref,
) {
  return LocalProductsRepository(() => LocalDatabase.instance.db);
});

/// صفحة أصناف لوكال (بحث + ترقيم).
final localProductsPageProvider = FutureProvider.autoDispose
    .family<
      ({List<LocalProduct> items, int total}),
      ({String query, int page})
    >((ref, args) {
      return ref
          .watch(localProductsRepositoryProvider)
          .page(query: args.query, page: args.page);
    });

/// الباركود الأساسي لصنف لوكال (للعرض والطباعة).
final localPrimaryBarcodeProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, productId) {
  return ref
      .watch(localProductsRepositoryProvider)
      .primaryBarcodeOf(productId);
});
