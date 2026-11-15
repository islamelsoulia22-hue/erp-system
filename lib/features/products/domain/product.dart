/// Domain models for catalog. Money as double in UI, numeric in DB.
class ProductCategory {
  final String id;
  final String? code;
  final String name;
  final String? nameAr;
  final bool isActive;
  final bool isSystem;

  const ProductCategory({
    required this.id,
    this.code,
    required this.name,
    this.nameAr,
    required this.isActive,
    this.isSystem = false,
  });

  factory ProductCategory.fromMap(Map<String, dynamic> m) {
    return ProductCategory(
      id: m['id'] as String,
      code: m['code'] as String?,
      name: (m['name'] as String?) ?? '',
      nameAr: m['name_ar'] as String?,
      isActive: (m['is_active'] as bool?) ?? true,
      isSystem: (m['is_system'] as bool?) ?? false,
    );
  }

  String get display => (nameAr?.isNotEmpty == true ? nameAr! : name);
}

class ProductUnit {
  final String id;
  final String code;
  final String name;
  final String? nameAr;

  const ProductUnit({
    required this.id,
    required this.code,
    required this.name,
    this.nameAr,
  });

  factory ProductUnit.fromMap(Map<String, dynamic> m) {
    return ProductUnit(
      id: m['id'] as String,
      code: (m['code'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      nameAr: m['name_ar'] as String?,
    );
  }

  String get display => (nameAr?.isNotEmpty == true ? nameAr! : name);
}

class Product {
  final String id;
  final String sku;
  final String name;
  final String? description;
  final String? categoryId;
  final String? categoryName;
  final String? unitId;
  final String? unitName;
  final double purchasePrice;
  final double salePrice;
  final String? supplierId;
  final String? supplierName;
  final String? deviceType;
  final String? brand;
  final String? model;
  final bool taxable;
  final double taxRate;
  final double minimumStock;
  final bool trackInventory;
  final bool isCustomizable;
  final bool isActive;
  final String? primaryBarcode;
  // بيانات بكر الباركود (فئة BARCODE_ROLL فقط).
  final String? barcodeMaterialId;
  final String? barcodeMaterialName;
  final double? labelLengthMm;
  final double? labelWidthMm;
  final double? qtyPerRoll;

  const Product({
    required this.id,
    required this.sku,
    required this.name,
    this.description,
    this.categoryId,
    this.categoryName,
    this.unitId,
    this.unitName,
    required this.purchasePrice,
    required this.salePrice,
    this.supplierId,
    this.supplierName,
    this.deviceType,
    this.brand,
    this.model,
    required this.taxable,
    required this.taxRate,
    required this.minimumStock,
    required this.trackInventory,
    required this.isCustomizable,
    required this.isActive,
    this.primaryBarcode,
    this.barcodeMaterialId,
    this.barcodeMaterialName,
    this.labelLengthMm,
    this.labelWidthMm,
    this.qtyPerRoll,
  });

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory Product.fromMap(Map<String, dynamic> m) {
    final cat = m['product_categories'];
    final unit = m['units'];
    final sup = m['suppliers'];
    String? barcode;
    final barcodes = m['product_barcodes'];
    if (barcodes is List) {
      for (final b in barcodes) {
        final bm = Map<String, dynamic>.from(b as Map);
        if (bm['is_primary'] == true) {
          barcode = bm['barcode'] as String?;
          break;
        }
      }
      barcode ??= barcodes.isNotEmpty
          ? (Map<String, dynamic>.from(barcodes.first as Map)['barcode']
              as String?)
          : null;
    }
    return Product(
      id: m['id'] as String,
      sku: (m['sku'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      description: m['description'] as String?,
      categoryId: m['category_id'] as String?,
      categoryName: cat is Map
          ? (((cat)['name_ar'] ?? (cat)['name']) as String?)
          : null,
      unitId: m['unit_id'] as String?,
      unitName:
          unit is Map ? (((unit)['name_ar'] ?? (unit)['name']) as String?) : null,
      purchasePrice: _num(m['purchase_price']),
      salePrice: _num(m['sale_price']),
      supplierId: m['supplier_id'] as String?,
      supplierName: sup is Map
          ? ((sup['name'] as String?) ?? '')
          : (m['supplier_name'] as String?),
      deviceType: m['device_type'] as String?,
      brand: m['brand'] as String?,
      model: m['model'] as String?,
      taxable: (m['taxable'] as bool?) ?? true,
      taxRate: _num(m['tax_rate']),
      minimumStock: _num(m['minimum_stock']),
      trackInventory: (m['track_inventory'] as bool?) ?? true,
      isCustomizable: (m['is_customizable'] as bool?) ?? false,
      isActive: (m['is_active'] as bool?) ?? true,
      primaryBarcode: barcode ?? m['primary_barcode'] as String?,
      barcodeMaterialId: m['barcode_material_id'] as String?,
      barcodeMaterialName: m['barcode_materials'] is Map
          ? ((((m['barcode_materials'] as Map)['name_ar'] ??
                      (m['barcode_materials'] as Map)['name']))
                  as String?)
          : null,
      labelLengthMm: m['label_length_mm'] == null
          ? null
          : _num(m['label_length_mm']),
      labelWidthMm: m['label_width_mm'] == null
          ? null
          : _num(m['label_width_mm']),
      qtyPerRoll: m['qty_per_roll'] == null
          ? null
          : _num(m['qty_per_roll']),
    );
  }
}

class ProductBarcode {
  final String id;
  final String productId;
  final String barcode;
  final String barcodeType;
  final bool isPrimary;

  const ProductBarcode({
    required this.id,
    required this.productId,
    required this.barcode,
    required this.barcodeType,
    required this.isPrimary,
  });

  factory ProductBarcode.fromMap(Map<String, dynamic> m) {
    return ProductBarcode(
      id: m['id'] as String,
      productId: m['product_id'] as String,
      barcode: (m['barcode'] as String?) ?? '',
      barcodeType: (m['barcode_type'] as String?) ?? 'EAN13',
      isPrimary: (m['is_primary'] as bool?) ?? false,
    );
  }
}

/// أنواع أجهزة فئة الإلكترونيات.
abstract final class DeviceTypes {
  static const receipt = 'RECEIPT';
  static const barcodePrinter = 'BARCODE_PRINTER';
  static const barcodeScanner = 'BARCODE_SCANNER';
  static const handheld = 'HANDHELD';

  static const all = [
    receipt,
    barcodePrinter,
    barcodeScanner,
    handheld,
  ];

  static String labelOf(String code) {
    return switch (code) {
      receipt => 'طابعة إيصالات (Receipt)',
      barcodePrinter => 'طابعة باركود',
      barcodeScanner => 'سكانر باركود',
      handheld => 'جهاز محمول (Handheld)',
      _ => code,
    };
  }
}

/// كود فئة الإلكترونيات المزروعة في الترحيل 0017.
const electronicsCategoryCode = 'ELEC';

/// كود فئة بكر الباركود المحمية (ترحيل 0025) — غير قابلة للمسح/الإيقاف.
const barcodeRollCategoryCode = 'BARCODE_ROLL';

bool isElectronicsCategory(ProductCategory? c) {
  if (c == null) return false;
  if (c.code == electronicsCategoryCode) return true;
  return (c.nameAr ?? '').trim() == 'إلكترونيات' ||
      c.name.trim().toLowerCase() == 'electronics';
}

bool isBarcodeRollCategory(ProductCategory? c) {
  if (c == null) return false;
  if (c.code == barcodeRollCategoryCode) return true;
  final ar = (c.nameAr ?? '').trim();
  final en = c.name.trim();
  final enLow = en.toLowerCase();
  // يطابق الاسم بالعربي سواء متخزن في name أو name_ar،
  // أو كود/اسم إنجليزي فيه barcode (للفئات اليدوية قبل الترحيل).
  if (ar == 'بكر الباركود' || en == 'بكر الباركود') return true;
  if (enLow.contains('barcode') && enLow.contains('roll')) return true;
  if (c.isSystem && enLow.contains('barcode')) return true;
  return false;
}

/// خامة باركود: سعر شراء/بيع ثابت لكل خامة.
/// حسبة سعر البكرة (المتفق عليها):
/// سعر البكرة = سعر الخامة × (الطول+3) × (العرض+3) × العدد
class BarcodeMaterial {
  final String id;
  final String name;
  final String? nameAr;
  final double purchasePrice;
  final double salePrice;
  final bool isActive;

  const BarcodeMaterial({
    required this.id,
    required this.name,
    this.nameAr,
    required this.purchasePrice,
    required this.salePrice,
    required this.isActive,
  });

  factory BarcodeMaterial.fromMap(Map<String, dynamic> m) {
    double toNum(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return BarcodeMaterial(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      nameAr: m['name_ar'] as String?,
      purchasePrice: toNum(m['purchase_price']),
      salePrice: toNum(m['sale_price']),
      isActive: (m['is_active'] as bool?) ?? true,
    );
  }

  String get display => (nameAr?.isNotEmpty == true ? nameAr! : name);
}

/// حاسبة سعر بكرة الاستيكر — نفس المعادلة في الفورم والتفاصيل.
/// سعر البكرة = سعر الخامة × (الطول+3) × (العرض+3) × العدد / معامل القسمة.
/// معامل القسمة يدوي (الافتراضي 100000) ويتظبط من الشيت.
abstract final class BarcodeRollPricing {
  static const double defaultDivisor = 100000;

  /// +3 ملي هالك/جاب على الطول والعرض، ثم القسمة على المعامل.
  static double rollPrice(
    double materialPrice,
    double lengthMm,
    double widthMm,
    double qty, [
    double divisor = defaultDivisor,
  ]) {
    if (materialPrice <= 0 ||
        lengthMm <= 0 ||
        widthMm <= 0 ||
        qty <= 0 ||
        divisor <= 0) {
      return 0;
    }
    return materialPrice * (lengthMm + 3) * (widthMm + 3) * qty / divisor;
  }
}
