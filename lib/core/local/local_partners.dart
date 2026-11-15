import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';
import 'local_products.dart' show LocalDataFailure;

/// عميل أو مورد محلي (نفس الشكل — جدولان منفصلان).
class LocalPartner {
  final String id;
  final String name;
  final String phone;
  final bool isActive;
  const LocalPartner({
    required this.id,
    required this.name,
    required this.phone,
    required this.isActive,
  });

  factory LocalPartner.fromMap(Map<String, Object?> m) {
    return LocalPartner(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      phone: (m['phone'] as String?) ?? '',
      isActive: (m['is_active'] as num? ?? 1) != 0,
    );
  }
}

class _PartnersRepo {
  final Future<Database> Function() _open;
  final String table;
  final String kindAr;
  _PartnersRepo(this._open, this.table, this.kindAr);

  static const int pageSize = 20;

  String _like(String q) =>
      '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  Future<({List<LocalPartner> items, int total})> page({
    String query = '',
    int page = 0,
    bool onlyActive = true,
  }) async {
    final db = await _open();
    final q = query.trim();
    final conds = <String>[];
    final args = <Object?>[];
    if (onlyActive) conds.add('is_active = 1');
    if (q.isNotEmpty) {
      conds.add("(name LIKE ? ESCAPE '\\' OR phone LIKE ? ESCAPE '\\')");
      final like = _like(q);
      args.addAll([like, like]);
    }
    final w = conds.isEmpty ? '' : 'WHERE ${conds.join(' AND ')}';
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table $w',
      args,
    );
    final total = (totalRows.first['c'] as num?)?.toInt() ?? 0;
    final rows = await db.rawQuery(
      'SELECT * FROM $table $w ORDER BY name LIMIT ? OFFSET ?',
      [...args, pageSize, page * pageSize],
    );
    return (
      items: [for (final r in rows) LocalPartner.fromMap(r)],
      total: total,
    );
  }

  Future<LocalPartner?> getById(String id) async {
    final db = await _open();
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalPartner.fromMap(rows.first);
  }

  Future<String> create({required String name, String? phone}) async {
    if (name.trim().isEmpty) {
      throw LocalDataFailure('اسم $kindAr مطلوب.');
    }
    final db = await _open();
    final id = LocalDatabase.newId();
    await db.insert(table, {
      'id': id,
      'name': name.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> setActive(String id, bool active) async {
    final db = await _open();
    await db.update(
      table,
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> remove(String id) async {
    final db = await _open();
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}

class LocalCustomersRepository extends _PartnersRepo {
  LocalCustomersRepository(Future<Database> Function() open)
    : super(open, 'customers', 'العميل');
}

class LocalSuppliersRepository extends _PartnersRepo {
  LocalSuppliersRepository(Future<Database> Function() open)
    : super(open, 'suppliers', 'المورد');
}

final localCustomersRepositoryProvider = Provider<LocalCustomersRepository>((
  ref,
) {
  return LocalCustomersRepository(() => LocalDatabase.instance.db);
});

final localSuppliersRepositoryProvider = Provider<LocalSuppliersRepository>((
  ref,
) {
  return LocalSuppliersRepository(() => LocalDatabase.instance.db);
});

final localCustomersPageProvider = FutureProvider.autoDispose
    .family<
      ({List<LocalPartner> items, int total}),
      ({String query, int page})
    >((ref, args) {
      return ref
          .watch(localCustomersRepositoryProvider)
          .page(query: args.query, page: args.page);
    });

final localSuppliersPageProvider = FutureProvider.autoDispose
    .family<
      ({List<LocalPartner> items, int total}),
      ({String query, int page})
    >((ref, args) {
      return ref
          .watch(localSuppliersRepositoryProvider)
          .page(query: args.query, page: args.page);
    });
