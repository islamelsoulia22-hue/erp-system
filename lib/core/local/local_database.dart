import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'password_hash.dart';

/// قاعدة البيانات المحلية (نسخة الجهاز BACKEND=local):
/// ملف SQLite واحد على الجهاز عبر sqflite_common_ffi
/// (شغالة موبايل + لينكس + ويندوز).
///
/// السكيما مرآة مختصرة لأسماء جداول/أعمدة سوبابيز
/// (snake_case) لتسهيل نقل منطق الريبوزيتوري لاحقا.
/// الإصدار يُدار بجدول schema_migrations — أي جداول
/// جديدة تضاف بترقية (v2, v3...) وليس بإعادة الإنشاء.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  static const int latestVersion = 6;
  static const String fileName = 'sanad_local.db';

  Database? _db;
  bool _ffiReady = false;
  String? _path;

  /// مسار ملف القاعدة (بعد الفتح).
  String? get path => _path;

  /// يفتح القاعدة (إنشاء + سكيما + بيانات أساسية أول مرة)
  /// ويجهزها للاستخدام. آمن للتكرار.
  Future<Database> get db async {
    final opened = _db;
    if (opened != null && opened.isOpen) return opened;
    if (!_ffiReady) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiReady = true;
    }
    final dir = await getApplicationDocumentsDirectory();
    _path = p.join(dir.path, fileName);
    _db = await databaseFactory.openDatabase(
      _path!,
      options: OpenDatabaseOptions(
        version: latestVersion,
        onConfigure: (db) async {
          // تفعيل مفاتيح FK (ضروري لـ CASCADE/RESTRICT مثل السحابة).
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createV1(db);
          await _applyV2(db);
          await _applyV3(db);
          await applyV4(db);
          await _seedBase(db);
          await applyV5(db);
          await applyV6(db);
          await db.insert('schema_migrations', {
            'version': latestVersion,
            'applied_at': _now(),
          });
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _applyV2(db);
            await _ensureAdminPassword(db);
          }
          if (oldVersion < 3) {
            await _applyV3(db);
          }
          if (oldVersion < 4) {
            await applyV4(db);
          }
          if (oldVersion < 5) {
            await applyV5(db);
          }
          if (oldVersion < 6) {
            await applyV6(db);
          }
          await db.insert('schema_migrations', {
            'version': newVersion,
            'applied_at': _now(),
          });
        },
      ),
    );
    return _db!;
  }

  /// يضمن فتح القاعدة — للاستدعاء من main قبل runApp.
  Future<void> ready() async {
    await db;
  }

  /// رقم السكيما المطبق (0 لو الجدول مش موجود).
  Future<int> schemaVersion() async {
    final d = await db;
    try {
      final rows = await d.rawQuery(
        'SELECT MAX(version) AS v FROM schema_migrations',
      );
      final v = rows.first['v'];
      if (v is num) return v.toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// عدد الصفوف في الجداول الأساسية (لشاشة الحالة).
  Future<Map<String, int>> tableCounts() async {
    final d = await db;
    const tables = [
      'users',
      'warehouses',
      'products',
      'customers',
      'suppliers',
      'warehouse_stock',
      'sales_invoices',
      'purchase_invoices',
      'payments',
    ];
    final out = <String, int>{};
    for (final t in tables) {
      try {
        final rows = await d.rawQuery('SELECT COUNT(*) AS c FROM $t');
        final c = rows.first['c'];
        out[t] = c is num ? c.toInt() : 0;
      } catch (_) {
        out[t] = -1;
      }
    }
    return out;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// معرف نصي فريد (بديل UUID بدون اعتماديات).
  static String newId() {
    final r = Random.secure();
    final hex = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$ts$hex';
  }

  static String _now() => DateTime.now().toIso8601String();

  /// سكيما v1 كجمل منفصلة — قابلة للاختبار على
  /// قاعدة in-memory بدون path_provider.
  static List<String> get schemaV1 => const [
    '''
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
)''',
    '''
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  full_name TEXT NOT NULL DEFAULT '',
  email TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE payment_methods (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT,
  name_ar TEXT,
  is_active INTEGER NOT NULL DEFAULT 1
)''',
    '''
CREATE TABLE warehouses (
  id TEXT PRIMARY KEY,
  code TEXT,
  name TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  sku TEXT,
  name TEXT NOT NULL,
  purchase_price REAL NOT NULL DEFAULT 0,
  sale_price REAL NOT NULL DEFAULT 0,
  average_cost REAL NOT NULL DEFAULT 0,
  minimum_stock REAL NOT NULL DEFAULT 0,
  supplier_id TEXT,
  track_inventory INTEGER NOT NULL DEFAULT 1,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE product_barcodes (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  barcode TEXT NOT NULL,
  barcode_type TEXT NOT NULL DEFAULT 'CODE128',
  is_primary INTEGER NOT NULL DEFAULT 0
)''',
    'CREATE INDEX idx_pbar_product ON product_barcodes(product_id)',
    'CREATE UNIQUE INDEX uq_pbar_code ON product_barcodes(barcode)',
    '''
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE warehouse_stock (
  warehouse_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity REAL NOT NULL DEFAULT 0,
  reserved_quantity REAL NOT NULL DEFAULT 0,
  PRIMARY KEY (warehouse_id, product_id)
)''',
    '''
CREATE TABLE sales_invoices (
  id TEXT PRIMARY KEY,
  invoice_number TEXT,
  customer_id TEXT,
  warehouse_id TEXT,
  payment_method_id TEXT,
  status TEXT NOT NULL DEFAULT 'DRAFT',
  payment_status TEXT NOT NULL DEFAULT 'UNPAID',
  subtotal REAL NOT NULL DEFAULT 0,
  discount REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  grand_total REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE sales_invoice_items (
  id TEXT PRIMARY KEY,
  sales_invoice_id TEXT NOT NULL,
  product_id TEXT,
  item_name TEXT,
  sku TEXT,
  quantity REAL NOT NULL DEFAULT 1,
  unit_price REAL NOT NULL DEFAULT 0,
  unit_cost REAL NOT NULL DEFAULT 0,
  discount REAL NOT NULL DEFAULT 0,
  tax_rate REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0
)''',
    'CREATE INDEX idx_sii_inv ON sales_invoice_items(sales_invoice_id)',
    '''
CREATE TABLE purchase_invoices (
  id TEXT PRIMARY KEY,
  invoice_number TEXT,
  supplier_id TEXT,
  warehouse_id TEXT,
  payment_method_id TEXT,
  status TEXT NOT NULL DEFAULT 'DRAFT',
  payment_status TEXT NOT NULL DEFAULT 'UNPAID',
  subtotal REAL NOT NULL DEFAULT 0,
  discount REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  grand_total REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE purchase_invoice_items (
  id TEXT PRIMARY KEY,
  purchase_invoice_id TEXT NOT NULL,
  product_id TEXT,
  product_name TEXT,
  sku TEXT,
  quantity REAL NOT NULL DEFAULT 1,
  unit_cost REAL NOT NULL DEFAULT 0,
  discount REAL NOT NULL DEFAULT 0,
  tax_rate REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0
)''',
    'CREATE INDEX idx_pii_inv ON purchase_invoice_items(purchase_invoice_id)',
    '''
CREATE TABLE payments (
  id TEXT PRIMARY KEY,
  customer_id TEXT,
  supplier_id TEXT,
  sales_invoice_id TEXT,
  purchase_invoice_id TEXT,
  payment_method_id TEXT,
  amount REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'COMPLETED',
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE stock_movements (
  id TEXT PRIMARY KEY,
  warehouse_id TEXT,
  product_id TEXT,
  movement_type TEXT NOT NULL,
  quantity REAL NOT NULL,
  before_quantity REAL NOT NULL DEFAULT 0,
  after_quantity REAL NOT NULL DEFAULT 0,
  reference_type TEXT,
  reference_id TEXT,
  notes TEXT,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE stock_alerts (
  id TEXT PRIMARY KEY,
  product_id TEXT,
  warehouse_id TEXT,
  level TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'NEW',
  available_qty REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE shortages (
  id TEXT PRIMARY KEY,
  product_id TEXT,
  warehouse_id TEXT,
  supplier_id TEXT,
  required_qty REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'PENDING',
  created_at TEXT NOT NULL
)''',
  ];

  Future<void> _createV1(Database db) async {
    for (final stmt in schemaV1) {
      await db.execute(stmt);
    }
  }

  /// ترقية v1 → v2: باسورد المستخدمين + جدول الجلسة.
  /// كقائمة جمل للاختبار على in-memory.
  static List<String> get migrationV1toV2 => const [
    'ALTER TABLE users ADD COLUMN password_hash TEXT',
    'ALTER TABLE users ADD COLUMN password_salt TEXT',
    '''
CREATE TABLE local_session (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  user_id TEXT NOT NULL,
  started_at TEXT NOT NULL
)''',
  ];

  Future<void> _applyV2(Database db) async {
    for (final stmt in migrationV1toV2) {
      await db.execute(stmt);
    }
  }

  /// ترقية v2 → v3: جداول المرتجعات (مبيعات/مشتريات).
  static List<String> get migrationV2toV3 => const [
    '''
CREATE TABLE sales_returns (
  id TEXT PRIMARY KEY,
  return_number TEXT,
  sales_invoice_id TEXT,
  customer_id TEXT,
  warehouse_id TEXT,
  status TEXT NOT NULL DEFAULT 'COMPLETED',
  subtotal REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  grand_total REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE sales_return_items (
  id TEXT PRIMARY KEY,
  sales_return_id TEXT NOT NULL,
  product_id TEXT,
  item_name TEXT,
  quantity REAL NOT NULL DEFAULT 1,
  unit_price REAL NOT NULL DEFAULT 0,
  unit_cost REAL NOT NULL DEFAULT 0,
  tax_rate REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0
)''',
    'CREATE INDEX idx_sri_ret ON sales_return_items(sales_return_id)',
    '''
CREATE TABLE purchase_returns (
  id TEXT PRIMARY KEY,
  return_number TEXT,
  purchase_invoice_id TEXT,
  supplier_id TEXT,
  warehouse_id TEXT,
  status TEXT NOT NULL DEFAULT 'COMPLETED',
  subtotal REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  grand_total REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''',
    '''
CREATE TABLE purchase_return_items (
  id TEXT PRIMARY KEY,
  purchase_return_id TEXT NOT NULL,
  product_id TEXT,
  product_name TEXT,
  quantity REAL NOT NULL DEFAULT 1,
  unit_cost REAL NOT NULL DEFAULT 0,
  tax_rate REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0
)''',
    'CREATE INDEX idx_pri_ret ON purchase_return_items(purchase_return_id)',
  ];

  Future<void> _applyV3(Database db) async {
    for (final stmt in migrationV2toV3) {
      await db.execute(stmt);
    }
  }

  // ── v4: اكتمال الأصناف بشكل السحابة (فئات/وحدات/خامات/ ──
  // ── سيريال/إعدادات/تدقيق + أعمدة products الناقصة) ──

  /// أعمدة products الناقصة عن السحابة (للترقية idempotent).
  static const Map<String, String> v4ProductColumns = {
    'description': 'TEXT',
    'category_id': 'TEXT',
    'unit_id': 'TEXT',
    'taxable': 'INTEGER NOT NULL DEFAULT 1',
    'tax_rate': 'REAL NOT NULL DEFAULT 14',
    'track_inventory': 'INTEGER NOT NULL DEFAULT 1',
    'is_customizable': 'INTEGER NOT NULL DEFAULT 0',
    'device_type': 'TEXT',
    'brand': 'TEXT',
    'model': 'TEXT',
    'barcode_material_id': 'TEXT',
    'label_length_mm': 'REAL',
    'label_width_mm': 'REAL',
    'qty_per_roll': 'REAL',
    'created_by': 'TEXT',
    'updated_at': 'TEXT',
  };

  /// DDL ترقية v4 (idempotent: IF NOT EXISTS + تجاهل المكرر).
  /// منع حذف الصنف المرتبط بمخزون/حركات (مثل RESTRICT في السحابة —
  /// الرسالة PRESS تطابق LinkedRecordFailure).
  static const String productsStockGuardTrigger = '''
CREATE TRIGGER IF NOT EXISTS trg_products_no_delete_with_stock
BEFORE DELETE ON products
FOR EACH ROW
BEGIN
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM warehouse_stock WHERE product_id = OLD.id
  ) THEN RAISE(
    ABORT, 'FOREIGN KEY constraint failed: warehouse_stock'
  ) END;
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM stock_movements WHERE product_id = OLD.id
  ) THEN RAISE(
    ABORT, 'FOREIGN KEY constraint failed: stock_movements'
  ) END;
END''';

  static List<String> get migrationV3toV4 => [
        '''
CREATE TABLE IF NOT EXISTS product_categories (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE,
  name TEXT NOT NULL,
  name_ar TEXT,
  description TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  is_system INTEGER NOT NULL DEFAULT 0,
  created_by TEXT,
  created_at TEXT NOT NULL
)''',
        '''
CREATE TABLE IF NOT EXISTS units (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  name_ar TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
)''',
        '''
CREATE TABLE IF NOT EXISTS barcode_materials (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_ar TEXT,
  purchase_price REAL NOT NULL DEFAULT 0,
  sale_price REAL NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_material_name '
            'ON barcode_materials(name)',
        '''
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
        '''
CREATE TABLE IF NOT EXISTS product_serials (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL
    REFERENCES products(id) ON DELETE CASCADE,
  serial TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (product_id, serial)
)''',
        'CREATE INDEX IF NOT EXISTS idx_serials_product '
            'ON product_serials(product_id)',
        '''
CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  old_data TEXT,
  new_data TEXT,
  created_at TEXT NOT NULL
)''',
        // توحيد الباركود الأساسي (صف واحد لكل صنف) قبل الفهرس الجزئي.
        '''
UPDATE product_barcodes SET is_primary = 0
WHERE is_primary = 1 AND rowid NOT IN (
  SELECT MIN(rowid) FROM product_barcodes
  WHERE is_primary = 1 GROUP BY product_id
)''',
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_barcodes_primary_per_product '
            'ON product_barcodes(product_id) WHERE is_primary = 1',
        'CREATE INDEX IF NOT EXISTS idx_products_category '
            'ON products(category_id)',
        'CREATE INDEX IF NOT EXISTS idx_products_material '
            'ON products(barcode_material_id)',
        // منع حذف الصنف المرتبط بمخزون/حركات (مثل RESTRICT في السحابة —
        // الرسالة تطابق LinkedRecordFailure).
        productsStockGuardTrigger,
      ];

  /// يضيف عمودا لو ناقص (SQLite لا يدعم ADD COLUMN IF NOT EXISTS).
  /// متسامح عمدا: يتخطى الجداول الغائبة (ترقيات جزئية/اختبارات).
  static Future<void> ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    try {
      final info = await db.rawQuery(
        'PRAGMA table_info("$table")',
      );
      if (info.isEmpty) return;
      final exists = info.any((r) => (r['name'] as String?) == column);
      if (!exists) {
        await db.execute(
          'ALTER TABLE "$table" ADD COLUMN "$column" $definition',
        );
      }
    } catch (_) {}
  }

  /// بذور v4 (INSERT OR IGNORE — آمنة للتكرار).
  static Future<void> seedV4(Database db) async {
    final now = _now();
    const units = [
      ['PCS', 'Piece', 'قطعة'],
      ['KG', 'Kilogram', 'كيلو'],
      ['M', 'Meter', 'متر'],
      ['L', 'Liter', 'لتر'],
      ['BOX', 'Box', 'علبة'],
      ['PACK', 'Pack', 'باكت'],
    ];
    for (final u in units) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO units '
        '(id, code, name, name_ar, is_active, created_at) '
        'VALUES (?, ?, ?, ?, 1, ?)',
        [newId(), u[0], u[1], u[2], now],
      );
    }
    const cats = [
      ['GEN', 'General', 'عام'],
      ['RAW', 'Raw materials', 'خامات'],
      ['FIN', 'Finished goods', 'منتجات تامة'],
      ['CUS', 'Custom', 'مخصص'],
      ['BARCODE_ROLL', 'Barcode Sticker Roll', 'بكر الباركود'],
    ];
    for (final c in cats) {
      final isSystem = c[0] == 'BARCODE_ROLL' ? 1 : 0;
      await db.rawInsert(
        'INSERT OR IGNORE INTO product_categories '
        '(id, code, name, name_ar, is_active, is_system, created_at) '
        'VALUES (?, ?, ?, ?, 1, ?, ?)',
        [newId(), c[0], c[1], c[2], isSystem, now],
      );
    }
    const mats = [
      ['semi-gloss', 'نص لميع'],
      ['white-plastic', 'بلاستك ابيض'],
      ['thermal', 'حراري'],
      ['thermal-fridge', 'حراري ثلاجة'],
      ['thermal-plastic', 'بلاستك حراري'],
      ['silver-plastic', 'بلاستك سيلفر'],
    ];
    for (final m in mats) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO barcode_materials '
        '(id, name, name_ar, purchase_price, sale_price, is_active, '
        'created_at, updated_at) '
        'VALUES (?, ?, ?, 0, 0, 1, ?, ?)',
        [newId(), m[0], m[1], now, now],
      );
    }
    await db.rawInsert(
      'INSERT OR IGNORE INTO app_settings (key, value, updated_at) '
      "VALUES ('tax', '{\"default_rate\": 14, \"currency\": \"EGP\"}', ?)",
      [now],
    );
  }

  /// ترقية v3 → v4 كاملة (عامة للاختبارات والتطبيق).
  static Future<void> applyV4(Database db) async {
    for (final e in v4ProductColumns.entries) {
      await ensureColumn(db, 'products', e.key, e.value);
    }
    await ensureColumn(db, 'product_barcodes', 'created_at', 'TEXT');
    for (final stmt in migrationV3toV4) {
      await db.execute(stmt);
    }
    await seedV4(db);
  }

  // ── v5: المصادقة والصلاحيات بشكل السحابة (0001 + 0019 + ──
  // ── 0021 + 0023) ليعمل AuthRepository/UsersRepository ──
  // ── بنفس الكود على SQLite. ──

  /// DDL ترقية v4 → v5 (idempotent).
  /// ملاحظة: بدون FK صريحة عمدا — الترتيب الحر للإدخال
  /// (بذور/اختبارات) أهم من فرض القيود، ولا RLS محليا.
  /// user_page_overrides بمفتاح مركب (بلا id منفصل) حتى
  /// يعمل upsert ... onConflict user_id,route كـ replace.
  static List<String> get migrationV4toV5 => const [
        '''
CREATE TABLE IF NOT EXISTS roles (
  id TEXT PRIMARY KEY,
  key TEXT UNIQUE,
  name_ar TEXT NOT NULL,
  description TEXT,
  created_at TEXT NOT NULL
)''',
        '''
CREATE TABLE IF NOT EXISTS permissions (
  id TEXT PRIMARY KEY,
  key TEXT UNIQUE,
  name_ar TEXT NOT NULL,
  module TEXT NOT NULL,
  created_at TEXT NOT NULL
)''',
        '''
CREATE TABLE IF NOT EXISTS role_permissions (
  role_id TEXT NOT NULL,
  permission_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (role_id, permission_id)
)''',
        '''
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  full_name TEXT,
  phone TEXT,
  email TEXT,
  avatar_url TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT
)''',
        'CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email)',
        '''
CREATE TABLE IF NOT EXISTS user_roles (
  user_id TEXT NOT NULL,
  role_id TEXT NOT NULL,
  assigned_by TEXT,
  assigned_at TEXT NOT NULL,
  PRIMARY KEY (user_id, role_id)
)''',
        'CREATE INDEX IF NOT EXISTS idx_user_roles_user '
            'ON user_roles(user_id)',
        '''
CREATE TABLE IF NOT EXISTS user_permission_grants (
  user_id TEXT NOT NULL,
  permission_id TEXT NOT NULL,
  granted_by TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, permission_id)
)''',
        'CREATE INDEX IF NOT EXISTS idx_upg_user '
            'ON user_permission_grants(user_id)',
        '''
CREATE TABLE IF NOT EXISTS user_page_overrides (
  user_id TEXT NOT NULL,
  route TEXT NOT NULL,
  visible INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, route)
)''',
        'CREATE INDEX IF NOT EXISTS idx_upo_user '
            'ON user_page_overrides(user_id)',
      ];

  /// كل الصلاحيات (0001 foundation + 0019 expenses +
  /// 0030 serials.verify): key / nameAr / module.
  static const List<List<String>> v5Permissions = [
    ['sales.create', 'إنشاء مبيعات', 'sales'],
    ['sales.edit', 'تعديل مبيعات', 'sales'],
    ['sales.view', 'عرض مبيعات', 'sales'],
    ['sales.approve', 'اعتماد مبيعات', 'sales'],
    ['sales.delete', 'حذف مبيعات', 'sales'],
    ['purchases.create', 'إنشاء مشتريات', 'purchases'],
    ['purchases.edit', 'تعديل مشتريات', 'purchases'],
    ['purchases.view', 'عرض مشتريات', 'purchases'],
    ['purchases.approve', 'اعتماد مشتريات', 'purchases'],
    ['products.create', 'إنشاء منتجات', 'products'],
    ['products.edit', 'تعديل منتجات', 'products'],
    ['products.view', 'عرض منتجات', 'products'],
    ['inventory.view', 'عرض مخزون', 'inventory'],
    ['inventory.adjust', 'تسوية مخزون', 'inventory'],
    ['inventory.transfer', 'تحويل مخزون', 'inventory'],
    ['customers.create', 'إنشاء عملاء', 'customers'],
    ['customers.edit', 'تعديل عملاء', 'customers'],
    ['customers.view', 'عرض عملاء', 'customers'],
    ['suppliers.create', 'إنشاء موردين', 'suppliers'],
    ['suppliers.edit', 'تعديل موردين', 'suppliers'],
    ['suppliers.view', 'عرض موردين', 'suppliers'],
    ['users.manage', 'إدارة المستخدمين', 'users'],
    ['warehouses.manage', 'إدارة المخازن', 'warehouses'],
    ['reports.view', 'عرض التقارير', 'reports'],
    ['expenses.view', 'عرض مصروفات', 'expenses'],
    ['expenses.create', 'إنشاء مصروفات', 'expenses'],
    ['expenses.edit', 'تعديل مصروفات', 'expenses'],
    ['expenses.approve', 'اعتماد مصروفات', 'expenses'],
    ['serials.verify', 'تحقق من السيريال', 'sales'],
  ];

  /// صلاحيات مدير المبيعات (0001 + serials.verify من 0030).
  static const List<String> v5SalesManagerPerms = [
    'sales.create',
    'sales.edit',
    'sales.view',
    'serials.verify',
    'products.view',
    'inventory.view',
    'customers.create',
    'customers.edit',
    'customers.view',
  ];

  /// صلاحيات مدير المشتريات (0001).
  static const List<String> v5PurchaseManagerPerms = [
    'purchases.create',
    'purchases.edit',
    'purchases.view',
    'products.view',
    'inventory.view',
    'suppliers.create',
    'suppliers.edit',
    'suppliers.view',
  ];

  /// يعيد بناء view user_permissions (دور + منح فردي — مثل 0023).
  /// DROP ثم CREATE عشان IF NOT EXISTS قد يبقي تعريفا قديما.
  static Future<void> rebuildUserPermissionsView(Database db) async {
    await db.execute('DROP VIEW IF EXISTS user_permissions');
    await db.execute('''
CREATE VIEW user_permissions AS
SELECT ur.user_id AS user_id,
       pm.key AS permission_key,
       r.key AS role_key
FROM user_roles ur
JOIN roles r ON r.id = ur.role_id
JOIN role_permissions rp ON rp.role_id = r.id
JOIN permissions pm ON pm.id = rp.permission_id
JOIN profiles p ON p.id = ur.user_id
WHERE p.is_active = 1
UNION
SELECT g.user_id AS user_id,
       pm.key AS permission_key,
       NULL AS role_key
FROM user_permission_grants g
JOIN permissions pm ON pm.id = g.permission_id
JOIN profiles p ON p.id = g.user_id
WHERE p.is_active = 1''');
  }

  /// بذور v5 (INSERT OR IGNORE — آمنة للتكرار):
  /// أدوار + صلاحيات + ربطها + ملف مدير الجهاز
  /// (نفس id صف users) بدور company_manager (كل الصلاحيات).
  static Future<void> seedV5(Database db) async {
    final now = _now();
    const roles = [
      ['company_manager', 'مدير الشركة'],
      ['sales_manager', 'مدير المبيعات'],
      ['purchase_manager', 'مدير المشتريات'],
    ];
    for (final r in roles) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO roles (id, key, name_ar, created_at) '
        'VALUES (?, ?, ?, ?)',
        [newId(), r[0], r[1], now],
      );
    }
    for (final p in v5Permissions) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO permissions (id, key, name_ar, module, '
        'created_at) VALUES (?, ?, ?, ?, ?)',
        [newId(), p[0], p[1], p[2], now],
      );
    }
    Future<String?> roleId(String key) async {
      final rows = await db.query(
        'roles',
        columns: ['id'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['id'] as String?;
    }

    Future<String?> permId(String key) async {
      final rows = await db.query(
        'permissions',
        columns: ['id'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['id'] as String?;
    }

    Future<void> grant(String roleKey, String permKey) async {
      final rid = await roleId(roleKey);
      final pid = await permId(permKey);
      if (rid == null || pid == null) return;
      await db.rawInsert(
        'INSERT OR IGNORE INTO role_permissions '
        '(role_id, permission_id, created_at) VALUES (?, ?, ?)',
        [rid, pid, now],
      );
    }

    // مدير الشركة: كل الصلاحيات.
    for (final p in v5Permissions) {
      await grant('company_manager', p[0]);
    }
    for (final k in v5SalesManagerPerms) {
      await grant('sales_manager', k);
    }
    for (final k in v5PurchaseManagerPerms) {
      await grant('purchase_manager', k);
    }
    // ملف مدير الجهاز + دوره (بنفس id صف users ليعمل
    // AuthRepository.profiles بنفس الكود).
    final admins = await db.query(
      'users',
      columns: ['id', 'full_name', 'email'],
      limit: 50,
    );
    Map<String, Object?>? admin;
    for (final u in admins) {
      final e = ((u['email'] as String?) ?? '').trim().toLowerCase();
      if (e == 'admin@local') {
        admin = u;
        break;
      }
    }
    if (admin != null) {
      final aid = admin['id'] as String;
      await db.rawInsert(
        'INSERT OR IGNORE INTO profiles '
        '(id, full_name, email, is_active, created_at) '
        'VALUES (?, ?, ?, 1, ?)',
        [aid, admin['full_name'] ?? 'مدير', 'admin@local', now],
      );
      final rid = await roleId('company_manager');
      if (rid != null) {
        await db.rawInsert(
          'INSERT OR IGNORE INTO user_roles '
          '(user_id, role_id, assigned_at) VALUES (?, ?, ?)',
          [aid, rid, now],
        );
      }
    }
  }

  /// ترقية v4 → v5 كاملة (عامة للاختبارات والتطبيق).
  static Future<void> applyV5(Database db) async {
    for (final stmt in migrationV4toV5) {
      await db.execute(stmt);
    }
    await rebuildUserPermissionsView(db);
    await seedV5(db);
  }

  // ── v6: اكتمال التدفقات (مبيعات/مشتريات/مرتجعات/مدفوعات/ ──
  // ── شحن/سيريال/عناوين/مرفقات + أعمدة ناقصة + low_stock) ──

  /// جداول v6 الجديدة (idempotent).
  /// ملاحظة: purchase_orders/items لم يكونا في سكيما v1 أصلا
  /// (اللوكال القديم كان فواتير فقط) — يُنشآن هنا بالشكل الكامل.
  static List<String> get migrationV5toV6 => const [
        '''
CREATE TABLE IF NOT EXISTS purchase_orders (
  id TEXT PRIMARY KEY,
  order_number TEXT UNIQUE,
  reference_number TEXT,
  supplier_id TEXT,
  warehouse_id TEXT,
  status TEXT NOT NULL DEFAULT 'DRAFT',
  subtotal REAL NOT NULL DEFAULT 0,
  discount REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  grand_total REAL NOT NULL DEFAULT 0,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT
)''',
        '''
CREATE TABLE IF NOT EXISTS purchase_order_items (
  id TEXT PRIMARY KEY,
  purchase_order_id TEXT NOT NULL,
  product_id TEXT,
  product_name TEXT NOT NULL,
  sku TEXT,
  quantity REAL NOT NULL DEFAULT 1,
  received_quantity REAL NOT NULL DEFAULT 0,
  unit_cost REAL NOT NULL DEFAULT 0,
  discount REAL NOT NULL DEFAULT 0,
  tax_rate REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0
)''',
        'CREATE INDEX IF NOT EXISTS idx_poi_order '
            'ON purchase_order_items(purchase_order_id)',
        '''
CREATE TABLE IF NOT EXISTS customer_addresses (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  label TEXT,
  address_line TEXT,
  governorate TEXT,
  city TEXT,
  area TEXT,
  latitude REAL,
  longitude REAL,
  phone TEXT,
  is_default INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT
)''',
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_addr_default '
            'ON customer_addresses(customer_id) WHERE is_default = 1',
        'CREATE INDEX IF NOT EXISTS idx_addr_customer '
            'ON customer_addresses(customer_id)',
        '''
CREATE TABLE IF NOT EXISTS serial_sales (
  id TEXT PRIMARY KEY,
  serial TEXT NOT NULL UNIQUE,
  product_id TEXT,
  product_name_snapshot TEXT,
  customer_id TEXT,
  customer_name_snapshot TEXT,
  customer_phone_snapshot TEXT,
  sales_invoice_id TEXT,
  sales_invoice_item_id TEXT,
  unit_price REAL NOT NULL DEFAULT 0,
  unit_cost REAL NOT NULL DEFAULT 0,
  sold_at TEXT NOT NULL,
  notes TEXT,
  created_by TEXT,
  created_at TEXT NOT NULL
)''',
        'CREATE INDEX IF NOT EXISTS idx_serial_sales_serial '
            'ON serial_sales(serial)',
        'CREATE INDEX IF NOT EXISTS idx_serial_sales_invoice '
            'ON serial_sales(sales_invoice_id)',
        '''
CREATE TABLE IF NOT EXISTS shipments (
  id TEXT PRIMARY KEY,
  shipment_number TEXT UNIQUE,
  sales_invoice_id TEXT,
  customer_id TEXT,
  shipping_company TEXT,
  tracking_number TEXT,
  recipient_name TEXT,
  recipient_phone TEXT,
  address TEXT,
  governorate TEXT,
  city TEXT,
  latitude REAL,
  longitude REAL,
  shipping_cost REAL NOT NULL DEFAULT 0,
  collection_method TEXT,
  collection_amount REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'PREPARING',
  shipped_at TEXT,
  delivered_at TEXT,
  notes TEXT,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT
)''',
        'CREATE INDEX IF NOT EXISTS idx_ship_status ON shipments(status)',
        '''
CREATE TABLE IF NOT EXISTS attachments (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_type TEXT,
  file_size INTEGER,
  uploaded_by TEXT,
  created_at TEXT NOT NULL
)''',
        'CREATE INDEX IF NOT EXISTS idx_attachments_entity '
            'ON attachments(entity_type, entity_id)',
      ];

  /// أعمدة ناقصة في الجداول القائمة (جدول → عمود → تعريف).
  static const Map<String, Map<String, String>> v6MissingColumns = {
    'sales_invoices': {
      'reference_number': 'TEXT',
      'sales_order_id': 'TEXT',
      'customer_name_snapshot': 'TEXT',
      'customer_phone_snapshot': 'TEXT',
      'customer_address_snapshot': 'TEXT',
      'customer_tax_number_snapshot': 'TEXT',
      'taxable_amount': 'REAL NOT NULL DEFAULT 0',
      'delivery_method': "TEXT NOT NULL DEFAULT 'OFFICE_PICKUP'",
      'credit_period_days': 'INTEGER',
      'due_date': 'TEXT',
      'credit_reason': 'TEXT',
      'created_by': 'TEXT',
      'approved_by': 'TEXT',
      'approved_at': 'TEXT',
      'rejected_by': 'TEXT',
      'rejected_at': 'TEXT',
      'rejection_reason': 'TEXT',
      'updated_at': 'TEXT',
    },
    'sales_invoice_items': {
      'item_type': "TEXT NOT NULL DEFAULT 'STANDARD'",
      'custom_unit': 'TEXT',
      'length_value': 'REAL',
      'length_unit': 'TEXT',
      'width_value': 'REAL',
      'width_unit': 'TEXT',
      'raw_material_id': 'TEXT',
      'raw_material_name': 'TEXT',
      'qty_per_roll': 'REAL',
      'custom_notes': 'TEXT',
      'customized_item_id': 'TEXT',
      'tax_amount': 'REAL NOT NULL DEFAULT 0',
      'serial_numbers': "TEXT NOT NULL DEFAULT '[]'",
    },
    'purchase_orders': {
      'reference_number': 'TEXT',
      'created_by': 'TEXT',
      'updated_at': 'TEXT',
    },
    'purchase_order_items': {
      'received_quantity': 'REAL NOT NULL DEFAULT 0',
    },
    'purchase_invoices': {
      'reference_number': 'TEXT',
      'purchase_order_id': 'TEXT',
      'supplier_name_snapshot': 'TEXT',
      'supplier_phone_snapshot': 'TEXT',
      'supplier_address_snapshot': 'TEXT',
      'supplier_tax_number_snapshot': 'TEXT',
      'taxable_amount': 'REAL NOT NULL DEFAULT 0',
      'created_by': 'TEXT',
      'approved_by': 'TEXT',
      'approved_at': 'TEXT',
      'rejected_by': 'TEXT',
      'rejected_at': 'TEXT',
      'rejection_reason': 'TEXT',
      'received_at': 'TEXT',
      'updated_at': 'TEXT',
    },
    'purchase_invoice_items': {
      'product_name_snapshot': 'TEXT',
      'sku_snapshot': 'TEXT',
      'tax_amount': 'REAL NOT NULL DEFAULT 0',
    },
    'sales_returns': {
      'reason': 'TEXT',
      'created_by': 'TEXT',
      'updated_at': 'TEXT',
    },
    'sales_return_items': {
      'sku': 'TEXT',
      'tax_amount': 'REAL NOT NULL DEFAULT 0',
    },
    'purchase_returns': {
      'reason': 'TEXT',
      'created_by': 'TEXT',
      'updated_at': 'TEXT',
    },
    'purchase_return_items': {
      'sku': 'TEXT',
      'tax_amount': 'REAL NOT NULL DEFAULT 0',
    },
    'customers': {
      'customer_code': 'TEXT',
      'email': 'TEXT',
      'tax_number': 'TEXT',
      'credit_limit': 'REAL NOT NULL DEFAULT 0',
      'default_payment_method_id': 'TEXT',
      'notes': 'TEXT',
      'company': 'TEXT',
      'created_by': 'TEXT',
      'updated_at': 'TEXT',
    },
    'suppliers': {
      'supplier_code': 'TEXT',
      'email': 'TEXT',
      'tax_number': 'TEXT',
      'address': 'TEXT',
      'credit_limit': 'REAL NOT NULL DEFAULT 0',
      'default_payment_method_id': 'TEXT',
      'notes': 'TEXT',
      'company': 'TEXT',
      'supply_category_id': 'TEXT',
      'created_by': 'TEXT',
      'updated_at': 'TEXT',
    },
    'warehouses': {
      'location': 'TEXT',
      'manager_id': 'TEXT',
      'created_by': 'TEXT',
      'updated_at': 'TEXT',
    },
    'stock_movements': {
      'created_by': 'TEXT',
    },
    'stock_alerts': {
      'ack_by': 'TEXT',
      'ack_at': 'TEXT',
    },
    'shortages': {
      'source_type': 'TEXT',
      'source_id': 'TEXT',
      'notes': 'TEXT',
      'created_by': 'TEXT',
      'updated_at': 'TEXT',
    },
    'payments': {
      'payment_number': 'TEXT',
      'transaction_reference': 'TEXT',
      'payment_date': 'TEXT',
      'notes': 'TEXT',
      'created_by': 'TEXT',
    },
    'payment_methods': {
      'created_at': 'TEXT',
    },
    'shipments': {
      // ترسله شاشة الشحن مع البيانات (تحقق محلي) — عمود إضافي
      // عن السحابة، لا يضر.
      'delivery_method': 'TEXT',
    },
  };

  /// يعيد بناء warehouse_stock بالشكل السحابي (id + UNIQUE +
  /// available_quantity محسوب) مع نقل البيانات. نسخة v1 كانت
  /// بمفتاح مركب وبدون id/available — والشاشات تحتاجهما.
  static Future<void> rebuildWarehouseStock(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info("warehouse_stock")');
    final hasId = info.any((r) => (r['name'] as String?) == 'id');
    final hasAvail =
        info.any((r) => (r['name'] as String?) == 'available_quantity');
    if (hasId && hasAvail) return;
    await db.execute('''
CREATE TABLE IF NOT EXISTS warehouse_stock_new (
  id TEXT PRIMARY KEY,
  warehouse_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity REAL NOT NULL DEFAULT 0,
  reserved_quantity REAL NOT NULL DEFAULT 0,
  available_quantity REAL GENERATED ALWAYS AS
    (quantity - reserved_quantity) STORED,
  updated_at TEXT NOT NULL,
  UNIQUE (warehouse_id, product_id)
)''');
    try {
      final now = _now().replaceAll("'", "''");
      await db.execute('''
INSERT OR IGNORE INTO warehouse_stock_new
  (id, warehouse_id, product_id, quantity, reserved_quantity, updated_at)
SELECT lower(hex(randomblob(16))), warehouse_id, product_id,
       quantity, reserved_quantity, '$now'
FROM warehouse_stock''');
    } catch (_) {}
    // التريجر الحارس والـ view يشيران لـ warehouse_stock —
    // إسقاطهما مؤقتا لأن SQLite يرفض تغيير السكيما مع وجودهما.
    try {
      await db.execute(
          'DROP TRIGGER IF EXISTS trg_products_no_delete_with_stock');
    } catch (_) {}
    try {
      await db.execute('DROP VIEW IF EXISTS low_stock_products');
    } catch (_) {}
    await db.execute('DROP TABLE warehouse_stock');
    await db.execute(
        'ALTER TABLE warehouse_stock_new RENAME TO warehouse_stock');
    try {
      await db.execute(productsStockGuardTrigger);
    } catch (_) {}
    try {
      await rebuildLowStockView(db);
    } catch (_) {}
  }

  /// view النواقص (0010) — تقرأه التقارير والداشبورد.
  static Future<void> rebuildLowStockView(Database db) async {
    await db.execute('DROP VIEW IF EXISTS low_stock_products');
    await db.execute('''
CREATE VIEW low_stock_products AS
SELECT ws.warehouse_id AS warehouse_id,
       w.name AS warehouse_name,
       ws.product_id AS product_id,
       p.name AS product_name,
       p.sku AS sku,
       p.minimum_stock AS minimum_stock,
       ws.quantity AS quantity,
       ws.reserved_quantity AS reserved_quantity,
       ws.available_quantity AS available_quantity
FROM warehouse_stock ws
JOIN products p ON p.id = ws.product_id
JOIN warehouses w ON w.id = ws.warehouse_id
WHERE p.track_inventory = 1 AND p.is_active = 1
  AND ws.available_quantity <= p.minimum_stock''');
  }

  /// بذور v6 (آمنة للتكرار).
  static Future<void> seedV6(Database db) async {
    await db.rawInsert(
      'INSERT OR IGNORE INTO payment_methods (id, code, name, name_ar, '
      'is_active) VALUES (?, ?, ?, ?, 1)',
      [newId(), 'SHIPPING_COMPANY', 'Shipping company', 'شركة شحن'],
    );
  }

  /// ترقية v5 → v6 كاملة (عامة للاختبارات والتطبيق).
  static Future<void> applyV6(Database db) async {
    for (final stmt in migrationV5toV6) {
      await db.execute(stmt);
    }
    for (final t in v6MissingColumns.entries) {
      for (final c in t.value.entries) {
        await ensureColumn(db, t.key, c.key, c.value);
      }
    }
    await rebuildWarehouseStock(db);
    await rebuildLowStockView(db);
    await seedV6(db);
  }

  /// يضمن باسورد افتراضي للمدير الموجود بدون باسورد
  /// (قواعد v1 المُرقاة) — لا يمس الموجود.
  Future<void> _ensureAdminPassword(Database db) async {
    final rows = await db.rawQuery(
      'SELECT id FROM users WHERE password_hash IS NULL LIMIT 1',
    );
    if (rows.isEmpty) return;
    final salt = PasswordHash.generateSalt();
    await db.update(
      'users',
      {
        'password_salt': salt,
        'password_hash': PasswordHash.hash(kDefaultAdminPassword, salt),
      },
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
  }

  /// بيانات أساسية: طرق الدفع (نفس أكواد السحابة) + مدير محلي.
  Future<void> _seedBase(Database db) async {
    const methods = [
      ('CASH', 'Cash', 'كاش'),
      ('CREDIT', 'Credit', 'آجل'),
      ('BANK_TRANSFER', 'Bank transfer', 'تحويل بنكي'),
      ('INSTAPAY', 'InstaPay', 'انستاباي'),
      ('VODAFONE_CASH', 'Vodafone Cash', 'فودافون كاش'),
    ];
    for (final m in methods) {
      await db.insert('payment_methods', {
        'id': newId(),
        'code': m.$1,
        'name': m.$2,
        'name_ar': m.$3,
        'is_active': 1,
      });
    }
    final salt = PasswordHash.generateSalt();
    await db.insert('users', {
      'id': newId(),
      'full_name': 'مدير',
      'email': 'admin@local',
      'password_salt': salt,
      'password_hash': PasswordHash.hash(kDefaultAdminPassword, salt),
      'is_active': 1,
      'created_at': _now(),
    });
  }
}
