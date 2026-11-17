import 'package:flutter/material.dart';

import '../permissions/permissions.dart';

/// Single ERP destination.
class ErpNavItem {
  final String title;
  final IconData icon;
  final String route;
  final String? permission;
  const ErpNavItem(this.title, this.icon, this.route,
      [this.permission]);

  bool visible(PermissionSet perms) =>
      permission == null || perms.can(permission!);
}

/// Sidebar section with grouped destinations.
class ErpNavSection {
  final String title;
  final List<ErpNavItem> items;
  const ErpNavSection(this.title, this.items);

  ErpNavSection visibleIn(PermissionSet perms) => ErpNavSection(
      title, items.where((i) => i.visible(perms)).toList());

  bool get isNotEmpty => items.isNotEmpty;
}

/// Full ERP navigation. Sections mirror the desktop sidebar spec.
/// Items without a dedicated route are intentionally omitted.
abstract final class ErpNav {
  static const sections = [
    ErpNavSection('الرئيسية', [
      ErpNavItem('لوحة التحكم', Icons.dashboard_outlined, '/'),
      ErpNavItem('مركز الموافقات', Icons.fact_check_outlined,
          '/approvals'),
      ErpNavItem('الإشعارات', Icons.notifications_outlined,
          '/notifications'),
    ]),
    ErpNavSection('المبيعات', [
      ErpNavItem('فواتير المبيعات', Icons.point_of_sale_outlined,
          '/sales', Permissions.salesView),
      ErpNavItem('تحقق من السيريال', Icons.verified_outlined,
          '/serials/verify', Permissions.serialsVerify),
      ErpNavItem('الشحن', Icons.local_shipping_outlined,
          '/shipping', Permissions.salesView),
      ErpNavItem('مرتجعات المبيعات',
          Icons.assignment_return_outlined, '/returns',
          Permissions.salesView),
    ]),
    ErpNavSection('المشتريات', [
      ErpNavItem('المشتريات', Icons.shopping_cart_outlined,
          '/purchases', Permissions.purchasesView),
      ErpNavItem('طلبات التوريد',
          Icons.request_quote_outlined, '/procurement',
          Permissions.purchasesView),
      ErpNavItem('مرتجعات المشتريات',
          Icons.assignment_return_outlined, '/returns',
          Permissions.purchasesView),
    ]),
    ErpNavSection('المخزون', [
      ErpNavItem('المخازن', Icons.warehouse_outlined,
          '/warehouses', Permissions.inventoryView),
      ErpNavItem('المخزون', Icons.inventory_outlined,
          '/inventory', Permissions.inventoryView),
      ErpNavItem('تنبيهات المخزون',
          Icons.notifications_active_outlined, '/stock-alerts',
          Permissions.inventoryView),
      ErpNavItem('النواقص', Icons.warning_amber_outlined,
          '/shortages', Permissions.purchasesView),
    ]),
    ErpNavSection('الأصناف', [
      ErpNavItem('الأصناف', Icons.inventory_2_outlined,
          '/products', Permissions.productsView),
      ErpNavItem('باركود الأصناف', Icons.barcode_reader,
          '/products/barcodes', Permissions.productsView),
    ]),
    ErpNavSection('الشركاء', [
      ErpNavItem('العملاء', Icons.people_outline, '/customers',
          Permissions.customersView),
      ErpNavItem('الموردين', Icons.handshake_outlined,
          '/suppliers', Permissions.suppliersView),
    ]),
    ErpNavSection('العمليات', [
      ErpNavItem('التصنيع', Icons.factory_outlined,
          '/manufacturing', Permissions.inventoryView),
    ]),
    ErpNavSection('المالية', [
      ErpNavItem('المصروفات', Icons.money_off_outlined,
          '/expenses', Permissions.expensesView),
      ErpNavItem('مصروفات متكررة', Icons.event_repeat_outlined,
          '/expenses/recurring', Permissions.expensesView),
      ErpNavItem('الأقساط', Icons.calendar_month_outlined,
          '/expenses/installments', Permissions.expensesView),
      ErpNavItem('المدفوعات', Icons.payments_outlined,
          '/payments', Permissions.salesView),
      ErpNavItem('التقارير', Icons.bar_chart_outlined,
          '/reports', Permissions.reportsView),
    ]),
    ErpNavSection('الإدارة', [
      ErpNavItem('المستخدمون',
          Icons.manage_accounts_outlined, '/users',
          Permissions.usersManage),
      ErpNavItem('سياسة المرتجعات',
          Icons.assignment_return_outlined, '/settings/returns',
          Permissions.usersManage),
      ErpNavItem('الصيانة والإصلاح',
          Icons.build_outlined, '/maintenance',
          Permissions.usersManage),
    ]),
  ];

  static List<ErpNavSection> visible(PermissionSet perms) => sections
      .map((s) => s.visibleIn(perms))
      .where((s) => s.isNotEmpty)
      .toList();

  /// Approvals entry is gated on approve rights, not just view.
  static bool approvalsVisible(PermissionSet perms) =>
      perms.can(Permissions.salesApprove) ||
      perms.can(Permissions.purchasesApprove) ||
      perms.can(Permissions.expensesApprove) ||
      perms.can(Permissions.usersManage);

  /// الصلاحية المطلوبة لإظهار route معين.
  /// null = ظاهرة دائما (الرئيسية/الإشعارات).
  /// '/approvals' ترجع null لأن لها منطق خاص (approvalsVisible).
  static String? permissionForRoute(String route) {
    for (final s in sections) {
      for (final i in s.items) {
        if (i.route == route) return i.permission;
      }
    }
    return null;
  }

  /// حزمة صلاحيات الصفحة: العرض + العمليات (إضافة/تعديل).
  /// تشغيل صفحة يمنح الحزمة كاملة عشان زرار "إضافة" يظهر —
  /// الاعتماد/الحذف/الإدارة حساسة ولا تُمنح تلقائيا.
  static List<String> permissionsBundleFor(String route) {
    switch (route) {
      case '/suppliers':
        return [
          Permissions.suppliersView,
          Permissions.suppliersCreate,
          Permissions.suppliersEdit
        ];
      case '/customers':
        return [
          Permissions.customersView,
          Permissions.customersCreate,
          Permissions.customersEdit
        ];
      case '/sales':
      case '/shipping':
        return [
          Permissions.salesView,
          Permissions.salesCreate,
          Permissions.salesEdit
        ];
      case '/serials/verify':
        return [Permissions.serialsVerify];
      case '/returns':
        return [
          Permissions.salesView,
          Permissions.salesCreate,
          Permissions.salesEdit
        ];
      case '/purchases':
      case '/procurement':
      case '/shortages':
        return [
          Permissions.purchasesView,
          Permissions.purchasesCreate,
          Permissions.purchasesEdit
        ];
      case '/products':
      case '/products/barcodes':
        return [
          Permissions.productsView,
          Permissions.productsCreate,
          Permissions.productsEdit
        ];
      case '/warehouses':
        return [
          Permissions.inventoryView,
          Permissions.warehousesManage
        ];
      case '/inventory':
      case '/manufacturing':
        return [
          Permissions.inventoryView,
          Permissions.inventoryAdjust,
          Permissions.inventoryTransfer
        ];
      case '/stock-alerts':
        return [Permissions.inventoryView];
      case '/expenses':
      case '/expenses/recurring':
      case '/expenses/installments':
        return [
          Permissions.expensesView,
          Permissions.expensesCreate,
          Permissions.expensesEdit
        ];
      case '/payments':
        return [
          Permissions.salesView,
          Permissions.salesCreate,
          Permissions.salesEdit
        ];
      case '/reports':
        return [Permissions.reportsView];
      case '/users':
      case '/settings/returns':
      case '/maintenance':
        return [Permissions.usersManage];
      case '/approvals':
        return [Permissions.salesApprove];
      default:
        final single = permissionForRoute(route);
        return single == null ? [] : [single];
    }
  }
}

/// الشريط السفلي المتحرك (YadBottomNav): 4 وجهات + "المزيد".
abstract final class BottomNav {
  static const items = [
    ErpNavItem('الرئيسية', Icons.home_outlined, '/'),
    ErpNavItem('المبيعات', Icons.receipt_long_outlined,
        '/sales', Permissions.salesView),
    ErpNavItem('المخزون', Icons.inventory_2_outlined,
        '/inventory', Permissions.inventoryView),
    ErpNavItem('الإشعارات', Icons.notifications_none_outlined,
        '/notifications'),
  ];
}

/// Route path → page title for the app bar.
String pageTitleFor(String path) {
  const titles = {
    '/': 'لوحة التحكم',
    '/approvals': 'مركز الموافقات',
    '/more': 'المزيد',
    '/sales': 'فواتير المبيعات',
    '/serials/verify': 'تحقق من السيريال',
    '/shipping': 'الشحن',
    '/returns': 'المرتجعات',
    '/purchases': 'المشتريات',
    '/procurement': 'طلبات التوريد',
    '/warehouses': 'المخازن',
    '/inventory': 'المخزون',
    '/stock-alerts': 'تنبيهات المخزون',
    '/shortages': 'النواقص',
    '/products': 'الأصناف',
    '/products/barcodes': 'باركود الأصناف',
    '/customers': 'العملاء',
    '/suppliers': 'الموردين',
    '/manufacturing': 'التصنيع',
    '/payments': 'المدفوعات',
    '/expenses/recurring': 'مصروفات متكررة',
    '/expenses/installments': 'الأقساط',
    '/expenses': 'المصروفات',
    '/reports': 'التقارير',
    '/notifications': 'الإشعارات',
    '/users': 'المستخدمون',
    '/settings/returns': 'سياسة المرتجعات',
    '/maintenance': 'الصيانة والإصلاح',
  };
  for (final e in titles.entries) {
    if (e.key == '/') continue;
    if (path == e.key || path.startsWith('${e.key}/')) {
      return e.value;
    }
  }
  return titles['/']!;
}
