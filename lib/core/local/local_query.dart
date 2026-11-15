import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_rpc_registry.dart';
import 'password_hash.dart';

/// عميل استعلامات SQLite بنفس واجهة Supabase المستخدمة في الريبوزيتوري.
///
/// الفكرة: كل الريبوزيتوري تأخذ `dynamic _client` وتنادي
/// `from().select().eq().order()...` — المحول ينفذ نفس السلاسل
/// على SQLite فيعمل كود السحابة **بدون تعديل** في نسخة الجهاز.
///
/// المدعوم: select (بما فيها embeds من مستوى واحد
/// `categories ( name )` و`!inner`), eq/neq/gt/gte/lt/lte/like/
/// ilike/in_/is_/or/not, order, range, limit, single, maybeSingle,
/// count, insert/update/delete/upsert مع إرجاع الصفوف.
/// غير المدعوم بعد: تجميعات SQL، joins بأكثر من مستوى، realtime.
///
/// تحويل الأنواع (مهم لأن الموديلات تعمل cast صارم):
/// - أعمدة البوليان (INT بقيم 0/1) ترجع bool.
/// - القيم الرقمية والتواريخ النصية تمر كما هي (ISO strings).
class LocalDbClient {
  final Future<Database> Function() _open;
  LocalDbClient(this._open) {
    ensureLocalRpcRegistered();
  }

  LocalTableQuery from(String table) =>
      LocalTableQuery._(_open, table);

  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) =>
      LocalRpc(_open).call(fn, params ?? const {});

  LocalAuthShim get auth => LocalAuthShim(_open);

  /// بديل `client.storage` — ملفات محلية تحت Documents/sanad_local_files.
  LocalStorageShim get storage => LocalStorageShim();

  /// بديل Edge Functions المستخدمة (create-user/delete-user).
  LocalFunctionsShim get functions => LocalFunctionsShim(_open);
}

/// الجلسة المحلية الحالية (يضبطها تسجيل الدخول/الخروج اللوكال —
/// إما عبر AuthRepository أو شاشات اللوكال القديمة).
abstract final class LocalSession {
  static String? currentUserId;
  static String? currentUserEmail;

  static void clear() {
    currentUserId = null;
    currentUserEmail = null;
  }

  /// استعادة الجلسة المحفوظة في جدول local_session بعد إعادة
  /// التشغيل (يُنادى مرة واحدة من main في نسخة الجهاز).
  static Future<void> restore(Database db) async {
    try {
      final rows = await db.rawQuery('''
SELECT u.id AS id, u.email AS email FROM local_session s
JOIN users u ON u.id = s.user_id AND u.is_active = 1
WHERE s.id = 1 LIMIT 1''');
      if (rows.isEmpty) return;
      currentUserId = rows.first['id'] as String?;
      currentUserEmail = rows.first['email'] as String?;
    } catch (_) {}
  }
}

/// بديل `client.auth` فوق SQLite — نفس التواقيع المستخدمة في
/// AuthRepository (signInWithPassword/signOut/onAuthStateChange/
/// currentUser) بأنواع gotrue الحقيقية فيعمل كود السحابة
/// **بدون تعديل**. البث broadcast عام (static) لأن كل
/// `client.auth` نسخة جديدة لكن الجلسة واحدة.
class LocalAuthShim {
  final Future<Database> Function() _open;
  LocalAuthShim(this._open);

  static final StreamController<AuthState> _events =
      StreamController<AuthState>.broadcast();

  /// كائن User حقيقي (gotrue) بنفس id/email — يكفي احتياجات
  /// الريبوزيتوري (created_by والتدقيق) والـ providers.
  User? get currentUser {
    final id = LocalSession.currentUserId;
    if (id == null) return null;
    return _localUser(id, LocalSession.currentUserEmail);
  }

  static User _localUser(String id, String? email) => User(
        id: id,
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: email,
      );

  static Session _localSession(User user) =>
      Session(accessToken: 'local', tokenType: 'bearer', user: user);

  /// مثل GoTrue: اللقطة الحالية أولا ثم الأحداث.
  Stream<AuthState> get onAuthStateChange async* {
    final u = currentUser;
    yield AuthState(
      AuthChangeEvent.initialSession,
      u == null ? null : _localSession(u),
    );
    yield* _events.stream;
  }

  /// دخول بالإيميل + باسورد من جدول users — يرمي AuthException
  /// بنفس نص السحابة ليعيد mapSupabaseError نفس التحويل
  /// (InvalidCredentialsFailure). فحص is_active يتم بعده في
  /// AuthRepository عبر profiles مثل السحابة تماما.
  Future<AuthResponse> signInWithPassword({
    String? phone,
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final mail = email.trim().toLowerCase();
    final db = await _open();
    Map<String, Object?>? hit;
    try {
      final rows = await db.query('users', limit: 5000);
      for (final r in rows) {
        final e = ((r['email'] as String?) ?? '').trim().toLowerCase();
        if (mail.isNotEmpty && e == mail) {
          hit = r;
          break;
        }
      }
    } catch (_) {}
    final ok = hit != null &&
        PasswordHash.verify(
          password,
          (hit['password_salt'] as String?) ?? '',
          (hit['password_hash'] as String?) ?? '',
        );
    if (!ok) {
      throw AuthException('Invalid login credentials');
    }
    final id = hit['id'] as String;
    final rawMail = (hit['email'] as String?) ?? '';
    final userEmail = rawMail.isEmpty ? mail : rawMail;
    // مرآة profiles بنفس الـ id (OR IGNORE يحفظ is_active لو
    // المدير عطّل الحساب — لا يعيد التفعيل).
    try {
      await db.rawInsert(
        'INSERT OR IGNORE INTO profiles '
        '(id, full_name, email, is_active, created_at) '
        'VALUES (?, ?, ?, 1, ?)',
        [
          id,
          (hit['full_name'] as String?) ?? '',
          userEmail,
          DateTime.now().toIso8601String(),
        ],
      );
    } catch (_) {}
    LocalSession.currentUserId = id;
    LocalSession.currentUserEmail = userEmail;
    try {
      await db.insert('local_session', {
        'id': 1,
        'user_id': id,
        'started_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
    final user = _localUser(id, userEmail);
    final session = _localSession(user);
    _events.add(AuthState(AuthChangeEvent.signedIn, session));
    return AuthResponse(session: session, user: user);
  }

  Future<void> signOut() async {
    LocalSession.clear();
    try {
      final db = await _open();
      await db.delete('local_session', where: 'id = 1');
    } catch (_) {}
    _events.add(const AuthState(AuthChangeEvent.signedOut, null));
  }
}

/// نتيجة العد بنفس شكل PostgREST (`res.count`).
class LocalCountResult {
  final int count;
  const LocalCountResult(this.count);
}

class _Cond {
  final String sql;
  final List<Object?> args;
  const _Cond(this.sql, [this.args = const []]);
}

class _Embed {
  final String table;
  final List<String> cols;
  final List<_Embed> children;
  final bool inner;
  const _Embed(this.table, this.cols,
      [this.children = const [], this.inner = false]);
}

/// أعمدة JSON تُفك من TEXT (jsonb في السحابة).
const _jsonColumns = <String, Set<String>>{
  'app_settings': {'value'},
  'audit_logs': {'old_data', 'new_data'},
  'sales_invoice_items': {'serial_numbers'},
};

/// أعمدة بوليان صريحة لكل جدول (مفاتيح snake_case).
/// أي عمود INT يبدأ بـ is_/has_/can_ يعامل بوليان تلقائيا.
const _boolColumns = <String, Set<String>>{
  'products': {'is_active', 'taxable', 'track_inventory', 'is_customizable'},
  'product_barcodes': {'is_primary'},
  'product_categories': {'is_active', 'is_system'},
  'barcode_materials': {'is_active'},
  'units': {'is_active'},
  'customers': {'is_active'},
  'suppliers': {'is_active'},
  'warehouses': {'is_active'},
  'users': {'is_active'},
  'profiles': {'is_active'},
  'user_page_overrides': {'visible'},
  'customer_addresses': {'is_default'},
  'payment_methods': {'is_active'},
  'sales_invoices': {'is_posted'},
  'purchase_invoices': {'is_posted'},
  'payments': {'is_posted'},
};

bool _isBoolCol(String table, String col, String? declaredType) {
  if (_boolColumns[table]?.contains(col) == true) return true;
  final t = (declaredType ?? '').toUpperCase();
  if (!t.contains('INT')) return false;
  return col.startsWith('is_') ||
      col.startsWith('has_') ||
      col.startsWith('can_');
}

String _q(String ident) => '"${ident.replaceAll('"', '""')}"';

/// سلسلة استعلام قابلة للـ await (تنفذ عند الـ await فقط،
/// مثل PostgrestFilterBuilder).
class LocalTableQuery implements Future<dynamic> {
  final Future<Database> Function() _open;
  final String _table;

  String _mode = 'select'; // select | insert | update | delete | upsert
  Object? _payload;
  String? _onConflict;

  final List<String> _baseCols = [];
  final List<_Embed> _embeds = [];
  bool _colsParsed = false;
  String _rawSelect = '*';

  final List<_Cond> _filters = [];
  final List<String> _orders = [];
  int? _rangeFrom;
  int? _rangeTo;
  int? _limit;
  bool _single = false;
  bool _maybeSingle = false;

  final Map<String, Map<String, String?>> _schemaCache = {};

  LocalTableQuery._(this._open, this._table);

  // ── بناء السلسلة (نفس أسماء Supabase) ──

  LocalTableQuery select([String columns = '*']) {
    if (_mode == 'select') {
      _rawSelect = columns;
      _colsParsed = false;
    }
    return this;
  }

  LocalTableQuery eq(String col, Object? v) {
    _filters.add(_Cond('${_q(col)} = ?', [_bind(v)]));
    return this;
  }

  LocalTableQuery neq(String col, Object? v) {
    _filters.add(_Cond('${_q(col)} != ?', [_bind(v)]));
    return this;
  }

  LocalTableQuery gt(String col, Object? v) {
    _filters.add(_Cond('${_q(col)} > ?', [_bind(v)]));
    return this;
  }

  LocalTableQuery gte(String col, Object? v) {
    _filters.add(_Cond('${_q(col)} >= ?', [_bind(v)]));
    return this;
  }

  LocalTableQuery lt(String col, Object? v) {
    _filters.add(_Cond('${_q(col)} < ?', [_bind(v)]));
    return this;
  }

  LocalTableQuery lte(String col, Object? v) {
    _filters.add(_Cond('${_q(col)} <= ?', [_bind(v)]));
    return this;
  }

  LocalTableQuery like(String col, String pattern) {
    _filters.add(_Cond("${_q(col)} LIKE ? ESCAPE '\\'", [pattern]));
    return this;
  }

  LocalTableQuery ilike(String col, String pattern) {
    _filters.add(_Cond("${_q(col)} LIKE ? ESCAPE '\\' COLLATE NOCASE", [pattern]));
    return this;
  }

  LocalTableQuery in_(String col, List<Object?> values) {    if (values.isEmpty) {
      _filters.add(const _Cond('1 = 0'));
      return this;
    }
    final marks = List.filled(values.length, '?').join(',');
    _filters.add(
      _Cond('${_q(col)} IN ($marks)', [for (final v in values) _bind(v)]),
    );
    return this;
  }

  /// اسم بديل لـ in_ يستخدمه بعض الريبوزيتوري.
  LocalTableQuery inFilter(String col, List<Object?> values) =>
      in_(col, values);

  LocalTableQuery is_(String col, Object? v) {
    if (v == null) {
      _filters.add(_Cond('${_q(col)} IS NULL'));
    } else if (v is bool) {
      _filters.add(_Cond('${_q(col)} = ?', [v ? 1 : 0]));
    } else {
      _filters.add(_Cond('${_q(col)} = ?', [_bind(v)]));
    }
    return this;
  }

  /// `or('a.ilike.%x%,b.eq.1')` — يدعم and()/or() المتداخلة
  /// بمستوى واحد (`or('and(a.eq.1,b.eq.2),c.eq.3')`).
  LocalTableQuery or(String expr) {
    final built = _parseOr(expr);
    if (built != null) _filters.add(built);
    return this;
  }

  LocalTableQuery not(String col, String op, Object? v) {
    if (op == 'is' && v == null) {
      _filters.add(_Cond('${_q(col)} IS NOT NULL'));
    } else if (op == 'eq') {
      _filters.add(_Cond('${_q(col)} != ?', [_bind(v)]));
    } else if (op == 'neq') {
      _filters.add(_Cond('${_q(col)} = ?', [_bind(v)]));
    } else {
      throw UnsupportedError('local not($op) غير مدعوم');
    }
    return this;
  }

  LocalTableQuery order(String col, {bool ascending = true}) {
    _orders.add('${_q(col)} ${ascending ? 'ASC' : 'DESC'}');
    return this;
  }

  /// range شامل من الطرفين (مثل PostgREST).
  LocalTableQuery range(int from, int to) {
    _rangeFrom = from;
    _rangeTo = to;
    return this;
  }

  LocalTableQuery limit(int n) {
    _limit = n;
    return this;
  }

  LocalTableQuery single() {
    _single = true;
    return this;
  }

  LocalTableQuery maybeSingle() {
    _maybeSingle = true;
    return this;
  }

  Future<LocalCountResult> count() async {
    final db = await _open();
    final where = _whereSql();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${_q(_table)} $where',
      _whereArgs(),
    );
    final c = rows.first['c'];
    return LocalCountResult(c is num ? c.toInt() : 0);
  }

  LocalTableQuery insert(Object payload) {
    _mode = 'insert';
    _payload = payload;
    return this;
  }

  LocalTableQuery update(Map<String, Object?> payload) {
    _mode = 'update';
    _payload = payload;
    return this;
  }

  LocalTableQuery delete() {
    _mode = 'delete';
    return this;
  }

  LocalTableQuery upsert(Object payload, {String? onConflict}) {
    _mode = 'upsert';
    _payload = payload;
    _onConflict = onConflict;
    return this;
  }

  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) =>
      LocalRpc(_open).call(fn, params ?? const {});

  // ── تنفيذ ──

  static Object? _bind(Object? v) {
    if (v is bool) return v ? 1 : 0;
    if (v is DateTime) return v.toIso8601String();
    if (v is Map || v is List) return jsonEncode(v);
    return v;
  }

  String _whereSql() {
    if (_filters.isEmpty) return '';
    return 'WHERE ${_filters.map((f) => '(${f.sql})').join(' AND ')}';
  }

  List<Object?> _whereArgs() =>
      [for (final f in _filters) ...f.args];

  /// يقسم `or` على الفواصل العليا (يتجاهل ما داخل الأقواس).
  static List<String> _splitTop(String s) {
    final parts = <String>[];
    var depth = 0;
    var cur = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (ch == ',' && depth == 0) {
        parts.add(cur.toString());
        cur = StringBuffer();
      } else {
        cur.write(ch);
      }
    }
    parts.add(cur.toString());
    return parts;
  }

  static _Cond? _parseOr(String expr) {
    final parts = _splitTop(expr.trim());
    final conds = <_Cond>[];
    for (var part in parts) {
      part = part.trim();
      if (part.startsWith('and(') && part.endsWith(')')) {
        final inner = _parseOr(part.substring(4, part.length - 1));
        if (inner == null) return null;
        conds.add(_Cond('(${inner.sql})', inner.args));
        continue;
      }
      if (part.startsWith('or(') && part.endsWith(')')) {
        final inner = _parseOr(part.substring(3, part.length - 1));
        if (inner == null) return null;
        conds.add(_Cond('(${inner.sql})', inner.args));
        continue;
      }
      final m = RegExp(r'^([^.()]+)\.([^.()]+)\.(.*)$').firstMatch(part);
      if (m == null) return null;
      final col = m.group(1)!;
      final op = m.group(2)!;
      var val = m.group(3)!;
      switch (op) {
        case 'eq':
          conds.add(_Cond('${_q(col)} = ?', [_lit(val)]));
        case 'neq':
          conds.add(_Cond('${_q(col)} != ?', [_lit(val)]));
        case 'gt':
          conds.add(_Cond('${_q(col)} > ?', [_lit(val)]));
        case 'gte':
          conds.add(_Cond('${_q(col)} >= ?', [_lit(val)]));
        case 'lt':
          conds.add(_Cond('${_q(col)} < ?', [_lit(val)]));
        case 'lte':
          conds.add(_Cond('${_q(col)} <= ?', [_lit(val)]));
        case 'like':
          conds.add(_Cond("${_q(col)} LIKE ? ESCAPE '\\'", [val]));
        case 'ilike':
          conds.add(
            _Cond("${_q(col)} LIKE ? ESCAPE '\\' COLLATE NOCASE", [val]),
          );
        case 'is':
          if (val.toLowerCase() == 'null') {
            conds.add(_Cond('${_q(col)} IS NULL'));
          } else if (val.toLowerCase() == 'true') {
            conds.add(_Cond('${_q(col)} = 1'));
          } else if (val.toLowerCase() == 'false') {
            conds.add(_Cond('${_q(col)} = 0'));
          } else {
            return null;
          }
        case 'in':
          final list = val.replaceAll(RegExp(r'^\(|\)$'), '').split(',');
          final marks = List.filled(list.length, '?').join(',');
          conds.add(
            _Cond('${_q(col)} IN ($marks)', [for (final e in list) _lit(e)]),
          );
        default:
          return null;
      }
    }
    if (conds.isEmpty) return null;
    return _Cond(
      conds.map((c) => '(${c.sql})').join(' OR '),
      [for (final c in conds) ...c.args],
    );
  }

  /// قيمة حرفية من نص PostgREST (true/false/null/رقم/نص).
  static Object? _lit(String s) {
    final t = s.trim();
    if (t.toLowerCase() == 'null') return null;
    if (t.toLowerCase() == 'true') return 1;
    if (t.toLowerCase() == 'false') return 0;
    final n = num.tryParse(t);
    if (n != null) return n;
    return t;
  }

  Future<Map<String, String?>> _columnsOf(
    Database db,
    String table,
  ) async {
    final cached = _schemaCache[table];
    if (cached != null) return cached;
    final out = <String, String?>{};
    try {
      final rows = await db.rawQuery('PRAGMA table_info(${_q(table)})');
      for (final r in rows) {
        out[(r['name'] as String?) ?? ''] =
            r['type'] as String?;
      }
    } catch (_) {}
    _schemaCache[table] = out;
    return out;
  }

  void _parseSelect() {
    if (_colsParsed) return;
    _colsParsed = true;
    _baseCols.clear();
    _embeds.clear();
    var s = _rawSelect.trim();
    if (s.isEmpty) s = '*';
    final parsed = _parseLevel(s);
    _baseCols.addAll(parsed.cols);
    _embeds.addAll(parsed.embeds);
  }

  /// تحليل مستوى واحد: أعمدة + embeds (يدعم تداخل الأقواس
  /// مثل `products!inner(id, categories ( name ))`).
  static ({List<String> cols, List<_Embed> embeds}) _parseLevel(String s) {
    final cols = <String>[];
    final embeds = <_Embed>[];
    var i = 0;
    while (i < s.length) {
      // تخطي المسافات والفواصل.
      while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\t' || s[i] == ',')) {
        i++;
      }
      if (i >= s.length) break;
      // قراءة الاسم (قد يتبعه !inner).
      final start = i;
      while (i < s.length && RegExp(r'[\w:!-]').hasMatch(s[i])) {
        i++;
      }
      var name = s.substring(start, i).trim();
      while (i < s.length && s[i] == ' ') {
        i++;
      }
      if (i < s.length && s[i] == '(') {
        // embed: أوجد القوس المطابق.
        var depth = 0;
        final innerStart = i + 1;
        var j = i;
        for (; j < s.length; j++) {
          if (s[j] == '(') depth++;
          if (s[j] == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        final inner = s.substring(innerStart, j);
        i = j + 1;
        var table = name;
        var innerFlag = false;
        if (name.contains('!')) {
          final seg = name.split('!');
          table = seg.first;
          innerFlag = seg.skip(1).any((e) => e == 'inner');
        }
        if (table.contains(':')) table = table.split(':').last.trim();
        final sub = _parseLevel(inner);
        embeds.add(_Embed(
          table,
          sub.cols.isEmpty ? ['*'] : sub.cols,
          sub.embeds,
          innerFlag,
        ));
      } else {
        if (name.isEmpty) {
          i++; // رمز غير متوقع (مثل *) — تخطه.
          continue;
        }
        if (name == '*') continue;
        if (name.contains(':')) name = name.split(':').last.trim();
        if (name.isNotEmpty) cols.add(name);
      }
    }
    return (cols: cols, embeds: embeds);
  }

  /// اسم مفرد تقريبي (category من categories...).
  static String _singular(String table) {
    const irregular = {
      'categories': 'category',
      'companies': 'company',
      'entries': 'entry',
      'quantities': 'quantity',
    };
    if (irregular.containsKey(table)) return irregular[table]!;
    if (table.endsWith('ies')) {
      return '${table.substring(0, table.length - 3)}y';
    }
    if (table.endsWith('ses') ||
        table.endsWith('xes') ||
        table.endsWith('ches') ||
        table.endsWith('shes')) {
      return table.substring(0, table.length - 2);
    }
    if (table.endsWith('s') && table.length > 1) {
      return table.substring(0, table.length - 1);
    }
    return table;
  }

  Map<String, dynamic> _convertRow(
    String table,
    Map<String, Object?> row,
    Map<String, String?> colTypes,
  ) {
    final out = <String, dynamic>{};
    row.forEach((k, v) {
      if (v is int &&
          (v == 0 || v == 1) &&
          _isBoolCol(table, k, colTypes[k])) {
        out[k] = v == 1;
      } else if (v is String &&
          (_jsonColumns[table]?.contains(k) == true) &&
          (v.startsWith('{') || v.startsWith('['))) {
        try {
          out[k] = jsonDecode(v);
        } catch (_) {
          out[k] = v;
        }
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  Future<List<Map<String, dynamic>>> _runSelect(Database db) async {
    _parseSelect();
    final baseCols = await _columnsOf(db, _table);
    final where = _whereSql();
    final args = _whereArgs();
    var sql = 'SELECT ${_q(_table)}.* FROM ${_q(_table)} $where';
    if (_orders.isNotEmpty) sql += " ORDER BY ${_orders.join(', ')}";
    if (_rangeFrom != null && _rangeTo != null) {
      final n = _rangeTo! - _rangeFrom! + 1;
      sql += ' LIMIT $n OFFSET $_rangeFrom';
    } else if (_limit != null) {
      sql += ' LIMIT $_limit';
    }
    final raw = await db.rawQuery(sql, args);
    final rows = [
      for (final r in raw) _convertRow(_table, r, baseCols),
    ];
    // embeds (قد تكون متداخلة).
    for (final e in _embeds) {
      await _attachEmbed(db, rows, _table, baseCols, e);
    }
    // !inner على مستوى الأساس = إسقاط الصفوف بدون علاقة.
    for (final e in _embeds) {
      if (e.inner) {
        rows.removeWhere((r) {
          final v = r[e.table];
          return v == null || (v is List && v.isEmpty);
        });
      }
    }
    // تقليل الأعمدة لو محددة (بعد الـ embeds حتى لا تكسر FK).
    if (_baseCols.isNotEmpty && !_baseCols.contains('*')) {
      final keep = _baseCols.toSet();
      for (final r in rows) {
        r.removeWhere((k, _) =>
            !keep.contains(k) &&
            !_embeds.any((e) => e.table == k));
      }
    }
    return rows;
  }

  Future<void> _attachEmbed(
    Database db,
    List<Map<String, dynamic>> rows,
    String baseTable,
    Map<String, String?> baseCols,
    _Embed e,
  ) async {
    if (rows.isEmpty) return;
    final embedCols = await _columnsOf(db, e.table);
    if (embedCols.isEmpty) {
      for (final r in rows) {
        r[e.table] = null;
      }
      return;
    }
    final baseSingular = _singular(baseTable);
    final embedSingular = _singular(e.table);
    final parentFk = '${embedSingular}_id'; // مفرد المضمن في الأساس
    final childFk = '${baseSingular}_id'; // مفرد الأساس في المضمن
    if (baseCols.containsKey(parentFk)) {
      // علاقة مفردة (N→1): دفعة واحدة بـ IN.
      final ids = {
        for (final r in rows)
          if (r[parentFk] != null) r[parentFk],
      };
      final map = <Object?, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final marks = List.filled(ids.length, '?').join(',');
        final got = await db.rawQuery(
          'SELECT * FROM ${_q(e.table)} WHERE ${_q('id')} IN ($marks)',
          ids.toList(),
        );
        for (final g in got) {
          map[g['id']] = _projectLevel(
            _convertRow(e.table, g, embedCols),
            e,
          );
        }
      }
      for (final r in rows) {
        r[e.table] = map[r[parentFk]];
      }
      // تعمق للأطفال داخل الخرائط المرتبطة.
      for (final child in e.children) {
        final nested = [
          for (final r in rows)
            if (r[e.table] is Map<String, dynamic>)
              r[e.table] as Map<String, dynamic>,
        ];
        await _attachEmbed(db, nested, e.table, embedCols, child);
      }
    } else if (embedCols.containsKey(childFk)) {
      // علاقة قائمة (1→N).
      final ids = [for (final r in rows) r['id']];
      final groups = <Object?, List<Map<String, dynamic>>>{};
      if (ids.isNotEmpty) {
        final marks = List.filled(ids.length, '?').join(',');
        final got = await db.rawQuery(
          'SELECT * FROM ${_q(e.table)} WHERE ${_q(childFk)} IN ($marks)',
          ids,
        );
        for (final g in got) {
          final conv = _convertRow(e.table, g, embedCols);
          (groups[g[childFk]] ??= []).add(_projectLevel(conv, e));
        }
      }
      for (final r in rows) {
        r[e.table] = groups[r['id']] ?? [];
      }
      for (final child in e.children) {
        final nested = [
          for (final r in rows)
            for (final item in (r[e.table] as List))
              if (item is Map<String, dynamic>) item,
        ];
        await _attachEmbed(db, nested, e.table, embedCols, child);
      }
    } else {
      for (final r in rows) {
        r[e.table] = null;
      }
    }
  }

  /// إسقاط على أعمدة المستوى — لو فيه أطفال يُترك كاملا
  /// حتى لا تضيع مفاتيح FK اللازمة للتعمق.
  Map<String, dynamic> _projectLevel(
    Map<String, dynamic> row,
    _Embed e,
  ) {
    if (e.children.isNotEmpty) return row;
    return _project(row, e.cols);
  }

  Map<String, dynamic> _project(
    Map<String, dynamic> row,
    List<String> cols,
  ) {
    if (cols.length == 1 && cols.first == '*') return row;
    return {for (final c in cols) if (row.containsKey(c)) c: row[c]};
  }

  Map<String, Object?> _outbound(Map<String, Object?> m) {
    final out = <String, Object?>{};
    m.forEach((k, v) => out[k] = _bind(v));
    return out;
  }

  /// معرف نصي فريد (بديل UUID للسيرفر) عند غيابه في الإدخال.
  static String _genId() {
    final r = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final rand = List.generate(
      8,
      (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$r$rand';
  }

  static final _rand = Random.secure();

  /// مواصفات أرقام المستندات التلقائية (بديل generate_* في السحابة):
  /// (جدول, عمود, prefix, عرض المسلسل, هل يلحق السنة).
  static const _numberSpecs = [
    ('sales_invoices', 'invoice_number', 'SAL', 6, true),
    ('purchase_orders', 'order_number', 'PO', 6, true),
    ('purchase_invoices', 'invoice_number', 'PUR', 6, true),
    ('sales_returns', 'return_number', 'RET-SAL', 6, true),
    ('purchase_returns', 'return_number', 'RET-PUR', 6, true),
    ('payments', 'payment_number', 'PAY', 6, true),
    ('shipments', 'shipment_number', 'SHP', 6, true),
    ('customers', 'customer_code', 'CUST', 6, false),
    ('suppliers', 'supplier_code', 'SUP', 6, false),
    ('warehouses', 'code', 'WH', 3, false),
  ];

  /// الرقم التالي بعداد في app_settings (مقاوم للفجوات: يتخطى
  /// الموجود حتى 200 محاولة). null لو تعذر (يترك العمود فارغا
  /// مثل السحابة عند غياب الـ default).
  Future<String?> _nextNumber(
    Database db,
    Map<String, String?> cols,
    String col,
    String prefix,
    int width,
    bool yearly,
  ) async {
    try {
      if (!cols.containsKey(col)) return null;
      final key = 'seq_${_table}__$col';
      var n = 0;
      try {
        final rows = await db.query(
          'app_settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          n = int.tryParse((rows.first['value'] as String?) ?? '') ?? 0;
        }
      } catch (_) {}
      if (n <= 0) {
        try {
          final c = await db.rawQuery(
            'SELECT COUNT(*) AS c FROM ${_q(_table)}',
          );
          final v = c.first['c'];
          n = v is num ? v.toInt() : 0;
        } catch (_) {}
      }
      final y = DateTime.now().year.toString();
      for (var i = 0; i < 200; i++) {
        n++;
        final num = yearly
            ? '$prefix-$y-${n.toString().padLeft(width, '0')}'
            : '$prefix-${n.toString().padLeft(width, '0')}';
        var free = true;
        try {
          final ex = await db.query(
            _table,
            columns: ['id'],
            where: '${_q(col)} = ?',
            whereArgs: [num],
            limit: 1,
          );
          free = ex.isEmpty;
        } catch (_) {}
        if (free) {
          try {
            await db.rawInsert(
              'INSERT OR REPLACE INTO app_settings '
              '(key, value, updated_at) VALUES (?, ?, ?)',
              [key, '$n', DateTime.now().toIso8601String()],
            );
          } catch (_) {}
          return num;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// يملأ افتراضيات السيرفر: id (نصي) + created_at/updated_at (الآن)
  /// لو الأعمدة موجودة والقيم ناقصة — مثل defaults في Postgres.
  Future<Map<String, Object?>> _withDefaults(
    Database db,
    Map<String, Object?> m, {
    required bool isInsert,
  }) async {
    final cols = await _columnsOf(db, _table);
    final out = Map<String, Object?>.from(m);
    if (isInsert) {
      final idType = cols['id'];
      if (idType != null &&
          idType.toUpperCase().contains('TEXT') &&
          (out['id'] == null ||
              (out['id'] is String &&
                  (out['id'] as String).isEmpty))) {
        out['id'] = _genId();
      }
      if (cols.containsKey('created_at') && out['created_at'] == null) {
        out['created_at'] = DateTime.now().toIso8601String();
      }
    }
    if (cols.containsKey('updated_at')) {
      out['updated_at'] = DateTime.now().toIso8601String();
    }
    // أرقام المستندات التلقائية (SAL-YYYY-000001 style) —
    // للعمود المخصص في هذا الجدول لو قيمته ناقصة.
    for (final spec in _numberSpecs) {
      if (spec.$1 != _table) continue;
      final cur = out[spec.$2];
      if (cur != null && !(cur is String && cur.isEmpty)) continue;
      if (!cols.containsKey(spec.$2)) continue;
      final num = await _nextNumber(
        db,
        cols,
        spec.$2,
        spec.$3,
        spec.$4,
        spec.$5,
      );
      if (num != null) out[spec.$2] = num;
    }
    return out;
  }

  Future<dynamic> _runInsert(Database db) async {
    final p = _payload;
    final list = p is List ? p : [p];
    final ids = <int>[];
    for (final item in list) {
      var m = _outbound(Map<String, Object?>.from(item as Map));
      m = await _withDefaults(db, m, isInsert: true);
      ids.add(await db.insert(_table, m));
    }
    // إرجاع الصفوف المدخلة (مثل .select() بعد insert).
    final got = <Map<String, dynamic>>[];
    final baseCols = await _columnsOf(db, _table);
    for (final id in ids) {
      final rows = await db.query(_table, where: 'rowid = ?', whereArgs: [id]);
      if (rows.isNotEmpty) {
        got.add(_convertRow(_table, rows.first, baseCols));
      }
    }
    return _finishRows(got);
  }

  Future<dynamic> _runUpdate(Database db) async {
    var m = _outbound(Map<String, Object?>.from(_payload as Map));
    m = await _withDefaults(db, m, isInsert: false);
    final where = _whereSql();
    final args = _whereArgs();
    final before = await db.rawQuery(
      'SELECT rowid AS _rid FROM ${_q(_table)} $where',
      args,
    );
    final rids = [for (final r in before) r['_rid']];
    if (where.isEmpty) {
      throw UnsupportedError('local update بدون شرط مرفوض للأمان');
    }
    await db.rawUpdate(
      'UPDATE ${_q(_table)} SET ${m.keys.map((k) => '${_q(k)} = ?').join(', ')} $where',
      [...m.values, ...args],
    );
    final baseCols = await _columnsOf(db, _table);
    final got = <Map<String, dynamic>>[];
    for (final rid in rids) {
      final rows =
          await db.query(_table, where: 'rowid = ?', whereArgs: [rid]);
      if (rows.isNotEmpty) {
        got.add(_convertRow(_table, rows.first, baseCols));
      }
    }
    return _finishRows(got);
  }

  Future<dynamic> _runDelete(Database db) async {
    final where = _whereSql();
    final args = _whereArgs();
    if (where.isEmpty) {
      throw UnsupportedError('local delete بدون شرط مرفوض للأمان');
    }
    final baseCols = await _columnsOf(db, _table);
    final before = await db.rawQuery('SELECT * FROM ${_q(_table)} $where', args);
    await db.rawDelete('DELETE FROM ${_q(_table)} $where', args);
    final got = [
      for (final r in before) _convertRow(_table, r, baseCols),
    ];
    return _finishRows(got);
  }

  Future<dynamic> _runUpsert(Database db) async {
    final p = _payload;
    final list = p is List ? p : [p];
    final got = <Map<String, dynamic>>[];
    final baseCols = await _columnsOf(db, _table);
    for (final item in list) {
      var m = _outbound(Map<String, Object?>.from(item as Map));
      m = await _withDefaults(db, m, isInsert: true);
      if (_onConflict != null && m.containsKey(_onConflict)) {
        final col = _onConflict!;
        final others = m.keys.where((k) => k != col).toList();
        final setSql = others.map((k) => '${_q(k)} = ?').join(', ');
        await db.rawInsert(
          'INSERT INTO ${_q(_table)} (${m.keys.map(_q).join(', ')}) '
          'VALUES (${List.filled(m.length, '?').join(', ')}) '
          'ON CONFLICT(${_q(col)}) DO UPDATE SET $setSql',
          [...m.values, for (final k in others) m[k]],
        );
        final rows = await db.query(
          _table,
          where: '${_q(col)} = ?',
          whereArgs: [m[col]],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          got.add(_convertRow(_table, rows.first, baseCols));
        }
      } else {
        final id = await db.insert(
          _table,
          m,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final rows =
            await db.query(_table, where: 'rowid = ?', whereArgs: [id]);
        if (rows.isNotEmpty) {
          got.add(_convertRow(_table, rows.first, baseCols));
        }
      }
    }
    return _finishRows(got);
  }

  dynamic _finishRows(List<Map<String, dynamic>> rows) {
    if (_single) {
      if (rows.isEmpty) {
        throw StateError('local single: لا توجد صفوف');
      }
      return rows.first;
    }
    if (_maybeSingle) {
      return rows.isEmpty ? null : rows.first;
    }
    return rows;
  }

  Future<dynamic> _execute() async {
    final db = await _open();
    switch (_mode) {
      case 'insert':
        return _runInsert(db);
      case 'update':
        return _runUpdate(db);
      case 'delete':
        return _runDelete(db);
      case 'upsert':
        return _runUpsert(db);
      default:
        final rows = await _runSelect(db);
        if (_single) {
          if (rows.isEmpty) {
            throw StateError('local single: لا توجد صفوف');
          }
          return rows.first;
        }
        if (_maybeSingle) {
          return rows.isEmpty ? null : rows.first;
        }
        return rows;
    }
  }

  // ── Future (للـ await المباشر مثل Supabase) ──

  @override
  Stream<dynamic> asStream() => _execute().asStream();

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) =>
      _execute().catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) =>
      _execute().then<R>(onValue, onError: onError);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) =>
      _execute().timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      _execute().whenComplete(action);
}

/// سجل دوال RPC المحلية — تضاف الدوال الحقيقية مع كل مرحلة.
/// أي دالة غير منفذة ترمي خطأ واضحا بدل السكوت.
class LocalRpc {
  final Future<Database> Function() _open;
  LocalRpc(this._open);

  static final Map<String, LocalRpcFn> _registry = {};

  /// تسجيل دالة RPC محلية (ينادى مرة واحدة عند الإقلاع/الاختبار).
  static void register(String name, LocalRpcFn fn) {
    _registry[name] = fn;
  }

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    final impl = _registry[fn];
    if (impl == null) {
      throw UnsupportedError(
        'دالة $fn غير منفذة في نسخة الجهاز بعد.',
      );
    }
    final db = await _open();
    return impl(db, Map<String, dynamic>.from(params));
  }
}

typedef LocalRpcFn = Future<dynamic> Function(
  Database db,
  Map<String, dynamic> params,
);

/// بديل `client.storage` فوق ملفات الجهاز (نسخة اللوكال).
/// البكت = مجلد فرعي تحت Documents/sanad_local_files.
class LocalStorageShim {
  LocalStorageBucket from(String bucket) => LocalStorageBucket(bucket);
}

class LocalStorageBucket {
  final String bucket;
  const LocalStorageBucket(this.bucket);

  Future<Directory> _bucketDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'sanad_local_files', bucket));
    await dir.create(recursive: true);
    return dir;
  }

  /// نفس توقيع storage_client (fileOptions يُتجاهل محليا).
  Future<void> uploadBinary(
    String path,
    Uint8List bytes, {
    Object? fileOptions,
  }) async {
    final dir = await _bucketDir();
    final f = File(p.join(dir.path, path));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  /// لا روابط موقعة محليا — يرجع مسار الملف (الواجهات لا تستخدمه).
  Future<String> createSignedUrl(String path, int expiresIn) async {
    final dir = await _bucketDir();
    return p.join(dir.path, path);
  }

  Future<void> remove(List<String> paths) async {
    final dir = await _bucketDir();
    for (final path in paths) {
      try {
        await File(p.join(dir.path, path)).delete();
      } catch (_) {}
    }
  }
}

/// بديل Edge Functions (create-user/delete-user من شاشة المستخدمين)
/// بنفس البروتوكول: invoke يرجع {status, data} وdata يحمل
/// {'error': code} عند الفشل — مثل functions_client.
class LocalFunctionsShim {
  final Future<Database> Function() _open;
  LocalFunctionsShim(this._open);

  Future<LocalFunctionResponse> invoke(
    String fn, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final db = await _open();
    final b = body ?? const {};
    switch (fn) {
      case 'create-user':
        return _createUser(db, b);
      case 'delete-user':
        return _deleteUser(db, b);
      default:
        throw UnsupportedError('دالة $fn غير منفذة في نسخة الجهاز.');
    }
  }

  Future<bool> _canManageUsers(Database db, String uid) async {
    try {
      final rows = await db.query(
        'user_permissions',
        columns: ['permission_key'],
        where: 'user_id = ?',
        whereArgs: [uid],
      );
      return rows.any((r) => r['permission_key'] == 'users.manage');
    } catch (_) {
      return false;
    }
  }

  Future<LocalFunctionResponse> _createUser(
    Database db,
    Map<String, dynamic> b,
  ) async {
    const err = LocalFunctionResponse.new;
    final uid = LocalSession.currentUserId;
    if (uid == null) {
      return err(status: 401, data: {'error': 'NOT_AUTHENTICATED'});
    }
    if (!await _canManageUsers(db, uid)) {
      return err(status: 403, data: {'error': 'NO_PERMISSION'});
    }
    final email = ((b['email'] as String?) ?? '').trim();
    final password = (b['password'] as String?) ?? '';
    final fullName = ((b['full_name'] as String?) ?? '').trim();
    final roleId = b['role_id'] as String?;
    // صيغة متساهلة (تقبل admin@local بلا TLD) — نسخة جهاز.
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(email);
    if (!emailOk || password.length < 6) {
      return err(status: 400, data: {'error': 'INVALID_INPUT'});
    }
    try {
      final mail = email.toLowerCase();
      var users = <Map<String, Object?>>[];
      var profiles = <Map<String, Object?>>[];
      try {
        users = await db.query('users', limit: 5000);
        profiles = await db.query('profiles', limit: 5000);
      } catch (_) {}
      final exists = users.any(
            (r) => (((r['email'] as String?) ?? '').trim().toLowerCase()) == mail,
          ) ||
          profiles.any(
            (r) => (((r['email'] as String?) ?? '').trim().toLowerCase()) == mail,
          );
      if (exists) {
        return err(status: 400, data: {'error': 'EMAIL_EXISTS'});
      }
      final now = DateTime.now().toIso8601String();
      final id = LocalTableQuery._genId();
      final salt = PasswordHash.generateSalt();
      await db.insert('users', {
        'id': id,
        'full_name': fullName.isEmpty ? email : fullName,
        'email': email,
        'password_salt': salt,
        'password_hash': PasswordHash.hash(password, salt),
        'is_active': 1,
        'created_at': now,
      });
      await db.rawInsert(
        'INSERT OR IGNORE INTO profiles '
        '(id, full_name, email, is_active, created_at) '
        'VALUES (?, ?, ?, 1, ?)',
        [id, fullName.isEmpty ? email : fullName, email, now],
      );
      if (roleId != null && roleId.isNotEmpty) {
        final rr = await db.query(
          'roles',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [roleId],
          limit: 1,
        );
        if (rr.isNotEmpty) {
          await db.rawInsert(
            'INSERT OR IGNORE INTO user_roles '
            '(user_id, role_id, assigned_by, assigned_at) '
            'VALUES (?, ?, ?, ?)',
            [id, roleId, uid, now],
          );
        }
      }
      try {
        await db.insert('audit_logs', {
          'id': LocalTableQuery._genId(),
          'user_id': uid,
          'action': 'CREATE',
          'entity_type': 'USER',
          'entity_id': id,
          'created_at': now,
        });
      } catch (_) {}
      return err(status: 200, data: {'id': id, 'email': email});
    } catch (_) {
      return err(status: 500, data: {'error': 'UNKNOWN'});
    }
  }

  Future<LocalFunctionResponse> _deleteUser(
    Database db,
    Map<String, dynamic> b,
  ) async {
    const err = LocalFunctionResponse.new;
    final uid = LocalSession.currentUserId;
    if (uid == null) {
      return err(status: 401, data: {'error': 'NOT_AUTHENTICATED'});
    }
    final target = (b['user_id'] as String?) ?? '';
    if (target.isEmpty) {
      return err(status: 400, data: {'error': 'INVALID_INPUT'});
    }
    if (target == uid) {
      return err(status: 400, data: {'error': 'CANNOT_DELETE_SELF'});
    }
    if (!await _canManageUsers(db, uid)) {
      return err(status: 403, data: {'error': 'NO_PERMISSION'});
    }
    try {
      await db.delete('local_session', where: 'user_id = ?', whereArgs: [target]);
      await db.delete('user_roles', where: 'user_id = ?', whereArgs: [target]);
      await db.delete('user_permission_grants',
          where: 'user_id = ?', whereArgs: [target]);
      await db.delete('user_page_overrides',
          where: 'user_id = ?', whereArgs: [target]);
      await db.delete('profiles', where: 'id = ?', whereArgs: [target]);
      await db.delete('users', where: 'id = ?', whereArgs: [target]);
      return err(status: 200, data: {'ok': true});
    } catch (_) {
      return err(status: 500, data: {'error': 'UNKNOWN'});
    }
  }
}

/// رد يشبه FunctionResponse (status/data) ليعمل كود
/// UsersRepository بدون تعديل.
class LocalFunctionResponse {
  final int? status;
  final dynamic data;
  const LocalFunctionResponse({this.status, this.data});
}
