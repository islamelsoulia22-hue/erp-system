import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/product.dart';

const _productSelect = '''
id, sku, name, description, category_id, unit_id,
purchase_price, sale_price, supplier_id, device_type, brand, model,
taxable, tax_rate,
minimum_stock, track_inventory, is_customizable, is_active,
barcode_material_id, label_length_mm, label_width_mm, qty_per_roll,
created_at,
product_categories ( name, name_ar ),
units ( name, name_ar ),
suppliers ( name ),
barcode_materials ( name, name_ar ),
product_barcodes ( barcode, is_primary )
''';

/// نفس السيلكت القديم قبل migration 0025 — يستخدم كـ fallback
/// لو السيرفر لسه متنفذش عليه الترحيل (PGRST200 schema cache).
const _productSelectLegacy = '''
id, sku, name, description, category_id, unit_id,
purchase_price, sale_price, supplier_id, device_type, brand, model,
taxable, tax_rate,
minimum_stock, track_inventory, is_customizable, is_active,
created_at,
product_categories ( name, name_ar ),
units ( name, name_ar ),
suppliers ( name ),
product_barcodes ( barcode, is_primary )
''';

/// true لو الخطأ سببه إن migration 0025 لسه متنفذش على السيرفر.
bool _isMissingRollBackend(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('barcode_materials') ||
      s.contains('barcode_material_id') ||
      s.contains('label_length_mm') ||
      s.contains('label_width_mm') ||
      s.contains('qty_per_roll') ||
      s.contains('is_system') ||
      s.contains('pgrst200') ||
      s.contains('schema cache');
}

Map<String, dynamic> _withoutRollKeys(Map<String, dynamic> data) {
  final d = Map<String, dynamic>.from(data);
  d.remove('barcode_material_id');
  d.remove('label_length_mm');
  d.remove('label_width_mm');
  d.remove('qty_per_roll');
  return d;
}

class ProductsRepository {
  final dynamic _client;
  ProductsRepository(this._client);

  /// Server-side paginated search by name / SKU / barcode.
  Future<List<Product>> search({
    String query = '',
    int page = 0,
    int pageSize = AppConstants.pageSize,
    bool onlyActive = true,
    String? categoryId,
  }) async {
    try {
      final q = query.trim();
      if (q.isNotEmpty) {
        // Barcode exact match first (fast unique lookup).
        final byBarcode = await findByBarcode(q);
        if (byBarcode != null) return [byBarcode];
      }
      try {
        return await _searchWith(_productSelect,
            query: query,
            page: page,
            pageSize: pageSize,
            onlyActive: onlyActive,
            categoryId: categoryId);
      } catch (e) {
        // fallback لو migration 0025 لسه متنفذش على السيرفر.
        if (_isMissingRollBackend(e)) {
          debugPrint('products.search fallback to legacy select');
          return await _searchWith(_productSelectLegacy,
              query: query,
              page: page,
              pageSize: pageSize,
              onlyActive: onlyActive,
              categoryId: categoryId);
        }
        rethrow;
      }
    } catch (e, st) {
      // اطبع الخام قبل الـ mapping عشان التشخيص.
      debugPrint(
          'products.search RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  Future<List<Product>> _searchWith(
    String select, {
    String query = '',
    int page = 0,
    int pageSize = AppConstants.pageSize,
    bool onlyActive = true,
    String? categoryId,
  }) async {
    final q = query.trim();
    var req = _client.from('products').select(select);
    if (onlyActive) req = req.eq('is_active', true);
    if (categoryId != null && categoryId.isNotEmpty) {
      req = req.eq('category_id', categoryId);
    }
    if (q.isNotEmpty) {
      req = req.or('name.ilike.%$q%,sku.ilike.%$q%');
    }
    req = req
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);
    final rows = (await req) as List;
    return rows
        .map((e) => Product.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// بحث مرقّم الصفحات: نفس فلاتر [search] + إجمالي العدد.
  /// يرجع (items, total) — والباركود المطابق تماما يرجع total=1.
  Future<({List<Product> items, int total})> searchPaged({
    String query = '',
    int page = 0,
    int pageSize = AppConstants.listPageSize,
    bool onlyActive = true,
    String? categoryId,
  }) async {
    try {
      final q = query.trim();
      if (q.isNotEmpty) {
        final byBarcode = await findByBarcode(q);
        if (byBarcode != null) {
          if (onlyActive && !byBarcode.isActive) {
            return (items: const <Product>[], total: 0);
          }
          if (categoryId != null &&
              categoryId.isNotEmpty &&
              byBarcode.categoryId != categoryId) {
            return (items: const <Product>[], total: 0);
          }
          return (
            items: <Product>[byBarcode],
            total: 1
          );
        }
      }
      final items = await search(
        query: query,
        page: page,
        pageSize: pageSize,
        onlyActive: onlyActive,
        categoryId: categoryId,
      );
      var req = _client.from('products').select('id');
      if (onlyActive) req = req.eq('is_active', true);
      if (categoryId != null && categoryId.isNotEmpty) {
        req = req.eq('category_id', categoryId);
      }
      if (q.isNotEmpty) {
        req = req.or('name.ilike.%$q%,sku.ilike.%$q%');
      }
      final res = await req.count();
      return (items: items, total: (res.count as int?) ?? 0);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Exact barcode lookup across product_barcodes. Returns null when missing.
  /// UI must show "المنتج غير موجود" and never auto-create.
  Future<Product?> findByBarcode(String barcode) async {
    try {
      final code = barcode.trim();
      if (code.isEmpty) return null;
      try {
        return await _findByBarcodeWith(_productSelect, code);
      } catch (e) {
        if (_isMissingRollBackend(e)) {
          return await _findByBarcodeWith(
              _productSelectLegacy, code);
        }
        rethrow;
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Product?> _findByBarcodeWith(
      String select, String code) async {
    final row = await _client
        .from('product_barcodes')
        .select('product_id, products!inner($select)')
        .eq('barcode', code)
        .maybeSingle();
    if (row == null) return null;
    final p = (row as Map)['products'] as Map;
    return Product.fromMap(Map<String, dynamic>.from(p));
  }

  Future<Product?> getById(String id) async {
    try {
      try {
        final row = await _client
            .from('products')
            .select(_productSelect)
            .eq('id', id)
            .maybeSingle();
        if (row == null) return null;
        return Product.fromMap(
            Map<String, dynamic>.from(row as Map));
      } catch (e) {
        if (_isMissingRollBackend(e)) {
          final row = await _client
              .from('products')
              .select(_productSelectLegacy)
              .eq('id', id)
              .maybeSingle();
          if (row == null) return null;
          return Product.fromMap(
              Map<String, dynamic>.from(row as Map));
        }
        rethrow;
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// دفعة أصناف بالـ ids (لفحص النواقص: الحد الأدنى + المورد).
  Future<List<Product>> getMany(List<String> ids) async {
    try {
      if (ids.isEmpty) return [];
      try {
        final rows = (await _client
            .from('products')
            .select(_productSelect)
            .inFilter('id', ids)) as List;
        return rows
            .map((e) =>
                Product.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (e) {
        if (_isMissingRollBackend(e)) {
          final rows = (await _client
              .from('products')
              .select(_productSelectLegacy)
              .inFilter('id', ids)) as List;
          return rows
              .map((e) =>
                  Product.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
        rethrow;
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<ProductBarcode>> barcodesOf(String productId) async {
    try {
      final rows = (await _client
          .from('product_barcodes')
          .select()
          .eq('product_id', productId)
          .order('is_primary', ascending: false)) as List;
      return rows
          .map((e) =>
              ProductBarcode.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Product> create(Map<String, dynamic> data) async {
    try {
      try {
        final row = await _client
            .from('products')
            .insert({...data, 'created_by': _client.auth.currentUser?.id})
            .select(_productSelect)
            .single();
        await _audit('CREATE', 'PRODUCT', (row as Map)['id'] as String,
            null, Map<String, dynamic>.from(row));
        return Product.fromMap(Map<String, dynamic>.from(row));
      } catch (e) {
        if (_isMissingRollBackend(e)) {
          final clean = _withoutRollKeys(data);
          final row = await _client
              .from('products')
              .insert(
                  {...clean, 'created_by': _client.auth.currentUser?.id})
              .select(_productSelectLegacy)
              .single();
          await _audit('CREATE', 'PRODUCT',
              (row as Map)['id'] as String, null,
              Map<String, dynamic>.from(row));
          return Product.fromMap(
              Map<String, dynamic>.from(row));
        }
        rethrow;
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Product> update(String id, Map<String, dynamic> data) async {
    try {
      final before = await _client
          .from('products')
          .select()
          .eq('id', id)
          .maybeSingle();
      try {
        final row = await _client
            .from('products')
            .update(data)
            .eq('id', id)
            .select(_productSelect)
            .single();
        await _audit('UPDATE', 'PRODUCT', id,
            before == null
                ? null
                : Map<String, dynamic>.from(before as Map),
            Map<String, dynamic>.from(row as Map));
        return Product.fromMap(Map<String, dynamic>.from(row));
      } catch (e) {
        if (_isMissingRollBackend(e)) {
          final clean = _withoutRollKeys(data);
          final row = await _client
              .from('products')
              .update(clean)
              .eq('id', id)
              .select(_productSelectLegacy)
              .single();
          await _audit('UPDATE', 'PRODUCT', id,
              before == null
                  ? null
                  : Map<String, dynamic>.from(before as Map),
              Map<String, dynamic>.from(row as Map));
          return Product.fromMap(
              Map<String, dynamic>.from(row));
        }
        rethrow;
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> addBarcode({
    required String productId,
    required String barcode,
    String type = 'EAN13',
    bool isPrimary = false,
  }) async {
    try {
      await _client.from('product_barcodes').insert({
        'product_id': productId,
        'barcode': barcode.trim(),
        'barcode_type': type,
        'is_primary': isPrimary,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> removeBarcode(String barcodeId) async {
    try {
      await _client.from('product_barcodes').delete().eq('id', barcodeId);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// حذف صنف (المدير فقط في UI؛ السيرفر يمنع لو عليه حركات/مخزون).
  Future<void> deleteProduct(String id) async {
    try {
      await _client.from('products').delete().eq('id', id);
    } catch (e, st) {
      debugPrint(
          'products.delete RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// إيقاف صنف (soft delete): يخفيه من كل القوائم بدون مسح تاريخ
  /// الفواتير/الحركات. هو الحل الآمن لو الحذف النهائي مرفوض
  /// بسبب مخزون أو حركات مرتبطة.
  Future<void> deactivateProduct(String id) async {
    try {
      await _client
          .from('products')
          .update({'is_active': false})
          .eq('id', id);
    } catch (e, st) {
      debugPrint(
          'products.deactivate RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// حذف نهائي قسري عبر RPC (يمسح رصيد المخزون صفر + سجل حركات
  /// الصنف ثم يحذف الصنف). يتطلب صلاحية products.create.
  /// يستخدم فقط بعد تأكيد المستخدم لأنه يمسح تاريخ الصنف.
  Future<void> deleteProductForce(String id) async {
    try {
      await _client.rpc('delete_product_force', params: {
        'p_product_id': id,
      });
    } catch (e, st) {
      debugPrint(
          'products.deleteForce RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  Future<List<ProductCategory>> categories() async {
    try {
      final rows = (await _client
          .from('product_categories')
          .select()
          .eq('is_active', true)
          .order('name')) as List;
      return rows
          .map((e) =>
              ProductCategory.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint(
          'products.categories RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// إنشاء فئة جديدة من داخل فورم الصنف.
  Future<ProductCategory> createCategory({
    required String name,
    String? nameAr,
  }) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final row = await _client
          .from('product_categories')
          .insert({
            'code': 'CAT-${ts.substring(ts.length - 6)}',
            'name': name.trim(),
            'name_ar':
                nameAr?.trim().isEmpty == true ? null : nameAr?.trim(),
            'is_active': true,
            'created_by': _client.auth.currentUser?.id,
          })
          .select()
          .single();
      return ProductCategory.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// كل الفئات (نشطة + موقوفة) لشاشة إدارة المدير.
  Future<List<ProductCategory>> categoriesAll() async {
    try {
      final rows = (await _client
          .from('product_categories')
          .select()
          .order('is_active', ascending: false)
          .order('name')) as List;
      return rows
          .map((e) =>
              ProductCategory.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint(
          'products.categoriesAll RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// إيقاف فئة (إخفاء) — للمدير. الفئة المحمية BARCODE_ROLL ممنوعة.
  Future<void> deactivateCategory(ProductCategory c) async {
    if (isBarcodeRollCategory(c)) {
      throw const ValidationFailure(
          'فئة بكر الباركود محمية ولا يمكن مسحها أو إيقافها.');
    }
    try {
      await _client
          .from('product_categories')
          .update({'is_active': false})
          .eq('id', c.id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// استرجاع فئة موقوفة (إضافتها تاني).
  Future<void> restoreCategory(String id) async {
    try {
      await _client
          .from('product_categories')
          .update({'is_active': true})
          .eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// حذف نهائي لفئة — للمدير فقط. ممنوع للمحمية، والأصناف
  /// المرتبطة بتتفك (category_id = null) تلقائيا.
  Future<void> deleteCategoryHard(ProductCategory c) async {
    if (isBarcodeRollCategory(c)) {
      throw const ValidationFailure(
          'فئة بكر الباركود محمية ولا يمكن مسحها.');
    }
    try {
      await _client.from('product_categories').delete().eq('id', c.id);
    } catch (e, st) {
      debugPrint(
          'products.deleteCategory RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  // ---------- خامات الباركود ----------

  /// الخامات الستة الافتراضية (نفس المزروعين في migration 0025).
  /// تستخدم كبذرة أول مرة لمخزن الإعدادات قبل تنفيذ الترحيل.
  static const List<Map<String, String>> defaultMaterials = [
    {'name': 'semi-gloss', 'name_ar': 'نص لميع'},
    {'name': 'white-plastic', 'name_ar': 'بلاستك ابيض'},
    {'name': 'thermal', 'name_ar': 'حراري'},
    {'name': 'thermal-fridge', 'name_ar': 'حراري ثلاجة'},
    {'name': 'thermal-plastic', 'name_ar': 'بلاستك حراري'},
    {'name': 'silver-plastic', 'name_ar': 'بلاستك سيلفر'},
  ];

  /// true لو جدول الخامات نفسه مش موجود (الترحيل متنفذش).
  bool _isMissingTable(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('42p01') ||
        s.contains('does not exist') ||
        s.contains('not find the table') ||
        s.contains('could not find the table');
  }

  /// يتأكد إن فئة بكر الباركود موجودة — يعملها تلقائيا لو ناقصة.
  /// شغال قبل وبعد migration 0025 (insert عادي بدون is_system).
  /// يرجع الفئة (الجديدة أو الموجودة) أو null لو تعذر.
  Future<ProductCategory?> ensureBarcodeRollCategory() async {
    try {
      final all = await categoriesAll();
      for (final c in all) {
        if (isBarcodeRollCategory(c)) return c;
      }
      final row = await _client
          .from('product_categories')
          .insert({
            'code': barcodeRollCategoryCode,
            'name': 'Barcode Sticker Roll',
            'name_ar': 'بكر الباركود',
            'is_active': true,
            'created_by': _client.auth.currentUser?.id,
          })
          .select()
          .single();
      final created = ProductCategory.fromMap(
          Map<String, dynamic>.from(row as Map));
      // بعد الترحيل: علّمها محمية (best-effort — تتجاهل لو العمود ناقص).
      try {
        await _client
            .from('product_categories')
            .update({'is_system': true})
            .eq('id', created.id);
        return ProductCategory(
          id: created.id,
          code: created.code,
          name: created.name,
          nameAr: created.nameAr,
          isActive: created.isActive,
          isSystem: true,
        );
      } catch (_) {
        return created;
      }
    } catch (e, st) {
      debugPrint(
          'products.ensureRollCat error: $e | type=${e.runtimeType}\n$st');
      return null;
    }
  }

  Future<List<BarcodeMaterial>> barcodeMaterials(
      {bool onlyActive = true}) async {
    try {
      // ملحوظة: الـ eq لازم قبل الـ order — بعد order الـ builder
      // بيبقى TransformBuilder ومفيهوش eq (NoSuchMethodError).
      var req = _client.from('barcode_materials').select();
      if (onlyActive) req = req.eq('is_active', true);
      final rows = (await req.order('name_ar')) as List;
      return rows
          .map((e) =>
              BarcodeMaterial.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint(
          'products.materials RAW error: $e | type=${e.runtimeType}\n$st');
      // الجدول لسه متعملش (0025 متنفذش) = مخزن مؤقت في app_settings.
      // أول ما الترحيل يتنفذ الجدول ياخد الأولوية تلقائيا.
      if (_isMissingRollBackend(e) || _isMissingTable(e)) {
        return _settingsMaterials();
      }
      throw mapSupabaseError(e);
    }
  }

  // ----- مخزن مؤقت للخامات في app_settings (قبل migration 0025) -----

  static const _settingsKey = 'barcode_materials';

  /// يقرأ الخامات من app_settings، ويبذر الستة الافتراضيين أول مرة.
  Future<List<BarcodeMaterial>> _settingsMaterials() async {
    try {
      final row = await _client
          .from('app_settings')
          .select('value')
          .eq('key', _settingsKey)
          .maybeSingle();
      final val =
          row == null ? null : (row as Map)['value'];
      final list = val is Map
          ? (val['materials'] as List?)
          : (val is List ? val : null);
      if (list != null && list.isNotEmpty) {
        return [
          for (final e in list)
            BarcodeMaterial.fromMap(
                Map<String, dynamic>.from(e as Map)),
        ];
      }
      // أول مرة: بذر الستة الافتراضيين (best-effort — لو ممنوع
      // الكتابة نرجعهم من الذاكرة قراءة فقط).
      final seed = [
        for (final d in defaultMaterials)
          BarcodeMaterial(
            id: 'mat-${d['name']}',
            name: d['name']!,
            nameAr: d['name_ar'],
            purchasePrice: 0,
            salePrice: 0,
            isActive: true,
          ),
      ];
      try {
        await _writeSettingsMaterials(seed);
      } catch (_) {}
      return seed;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> _writeSettingsMaterials(
      List<BarcodeMaterial> mats) async {
    await _client.from('app_settings').upsert({
      'key': _settingsKey,
      'value': {
        'materials': [
          for (final m in mats)
            {
              'id': m.id,
              'name': m.name,
              'name_ar': m.nameAr,
              'purchase_price': m.purchasePrice,
              'sale_price': m.salePrice,
              'is_active': m.isActive,
            },
        ],
      },
    });
  }

  /// إضافة خامة جديدة (زرار إضافة خامة) بسعر شراء/بيع ثابت.
  Future<BarcodeMaterial> createMaterial({
    required String nameAr,
    required double purchasePrice,
    required double salePrice,
  }) async {
    try {
      final row = await _client
          .from('barcode_materials')
          .insert({
            'name': 'custom-${DateTime.now().millisecondsSinceEpoch}',
            'name_ar': nameAr.trim(),
            'purchase_price': purchasePrice,
            'sale_price': salePrice,
            'is_active': true,
            'created_by': _client.auth.currentUser?.id,
          })
          .select()
          .single();
      return BarcodeMaterial.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      // الجدول ناقص = خزن في app_settings بدل ما نفشل.
      if (_isMissingRollBackend(e) || _isMissingTable(e)) {
        try {
          final mats = await _settingsMaterials();
          final mat = BarcodeMaterial(
            id: 'mat-custom-${DateTime.now().millisecondsSinceEpoch}',
            name:
                'custom-${DateTime.now().millisecondsSinceEpoch}',
            nameAr: nameAr.trim(),
            purchasePrice: purchasePrice,
            salePrice: salePrice,
            isActive: true,
          );
          await _writeSettingsMaterials([...mats, mat]);
          return mat;
        } catch (e2) {
          throw mapSupabaseError(e2);
        }
      }
      throw mapSupabaseError(e);
    }
  }

  Future<BarcodeMaterial> updateMaterial(
    String id, {
    String? nameAr,
    double? purchasePrice,
    double? salePrice,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (nameAr != null) data['name_ar'] = nameAr.trim();
      if (purchasePrice != null) data['purchase_price'] = purchasePrice;
      if (salePrice != null) data['sale_price'] = salePrice;
      final row = await _client
          .from('barcode_materials')
          .update(data)
          .eq('id', id)
          .select()
          .single();
      return BarcodeMaterial.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      if (_isMissingRollBackend(e) || _isMissingTable(e)) {
        try {
          final mats = await _settingsMaterials();
          var found = false;
          final next = <BarcodeMaterial>[];
          for (final m in mats) {
            if (m.id == id) {
              found = true;
              next.add(BarcodeMaterial(
                id: m.id,
                name: m.name,
                nameAr: nameAr?.trim() ?? m.nameAr,
                purchasePrice:
                    purchasePrice ?? m.purchasePrice,
                salePrice: salePrice ?? m.salePrice,
                isActive: m.isActive,
              ));
            } else {
              next.add(m);
            }
          }
          if (!found) {
            throw const ValidationFailure(
                'الخامة غير موجودة.');
          }
          await _writeSettingsMaterials(next);
          return next.firstWhere((m) => m.id == id);
        } catch (e2) {
          if (e2 is AppFailure) rethrow;
          throw mapSupabaseError(e2);
        }
      }
      throw mapSupabaseError(e);
    }
  }

  Future<void> deleteMaterial(String id) async {
    try {
      await _client.from('barcode_materials').delete().eq('id', id);
    } catch (e) {
      if (_isMissingRollBackend(e) || _isMissingTable(e)) {
        try {
          final mats = await _settingsMaterials();
          await _writeSettingsMaterials(
              [for (final m in mats) if (m.id != id) m]);
          return;
        } catch (e2) {
          throw mapSupabaseError(e2);
        }
      }
      throw mapSupabaseError(e);
    }
  }

  Future<List<ProductUnit>> units() async {
    try {
      final rows = (await _client
          .from('units')
          .select()
          .eq('is_active', true)
          .order('code')) as List;
      return rows
          .map((e) =>
              ProductUnit.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint(
          'products.units RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// إنشاء وحدة جديدة من داخل فورم الصنف.
  Future<ProductUnit> createUnit({
    required String code,
    required String name,
    String? nameAr,
  }) async {
    try {
      final row = await _client
          .from('units')
          .insert({
            'code': code.trim().toUpperCase(),
            'name': name.trim(),
            'name_ar':
                nameAr?.trim().isEmpty == true ? null : nameAr?.trim(),
            'is_active': true,
          })
          .select()
          .single();
      return ProductUnit.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// سيريالات الصنف (أجهزة الإلكترونيات).
  Future<List<String>> serialsOf(String productId) async {
    try {
      final rows = (await _client
          .from('product_serials')
          .select('serial')
          .eq('product_id', productId)
          .order('created_at')) as List;
      return [
        for (final r in rows)
          (Map<String, dynamic>.from(r as Map)['serial'] as String? ??
              '')
      ].where((s) => s.isNotEmpty).toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// استبدال سيريالات الصنف بالقائمة الحالية (حذف + إدخال).
  Future<void> replaceSerials(
      String productId, List<String> serials) async {
    try {
      final clean = [
        for (final s in serials)
          s.trim()
      ].where((s) => s.isNotEmpty).toList();
      await _client
          .from('product_serials')
          .delete()
          .eq('product_id', productId);
      if (clean.isNotEmpty) {
        await _client.from('product_serials').insert([
          for (final s in clean)
            {'product_id': productId, 'serial': s},
        ]);
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> _audit(String action, String entity, String id,
      Map<String, dynamic>? oldD, Map<String, dynamic>? newD) async {
    try {
      await _client.from('audit_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'action': action,
        'entity_type': entity,
        'entity_id': id,
        'old_data': oldD,
        'new_data': newD,
      });
    } catch (_) {}
  }
}

final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return ProductsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ProductsRepository(ref.watch(supabaseClientProvider));
});
