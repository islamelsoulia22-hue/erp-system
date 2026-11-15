/// Granular permission keys. Mirror of DB `permissions.key`.
/// Used ONLY for UX (hide/show). DB RLS/RPC is the real security layer.
abstract final class Permissions {
  static const String salesCreate = 'sales.create';
  static const String salesEdit = 'sales.edit';
  static const String salesView = 'sales.view';
  static const String salesApprove = 'sales.approve';
  static const String salesDelete = 'sales.delete';
  static const String serialsVerify = 'serials.verify';

  static const String purchasesCreate = 'purchases.create';
  static const String purchasesEdit = 'purchases.edit';
  static const String purchasesView = 'purchases.view';
  static const String purchasesApprove = 'purchases.approve';

  static const String productsCreate = 'products.create';
  static const String productsEdit = 'products.edit';
  static const String productsView = 'products.view';

  static const String inventoryView = 'inventory.view';
  static const String inventoryAdjust = 'inventory.adjust';
  static const String inventoryTransfer = 'inventory.transfer';

  static const String customersCreate = 'customers.create';
  static const String customersEdit = 'customers.edit';
  static const String customersView = 'customers.view';

  static const String suppliersCreate = 'suppliers.create';
  static const String suppliersEdit = 'suppliers.edit';
  static const String suppliersView = 'suppliers.view';

  static const String usersManage = 'users.manage';
  static const String warehousesManage = 'warehouses.manage';
  static const String reportsView = 'reports.view';

  static const String expensesCreate = 'expenses.create';
  static const String expensesEdit = 'expenses.edit';
  static const String expensesView = 'expenses.view';
  static const String expensesApprove = 'expenses.approve';
}

/// Simple in-memory permission holder loaded from DB after login.
class PermissionSet {
  final Set<String> keys;

  /// Role keys (company_manager, sales_manager, ...). Empty when unknown.
  final Set<String> roles;

  const PermissionSet(this.keys, [this.roles = const {}]);

  bool can(String permission) => keys.contains(permission);

  /// مدير الشركة: معفي من منع الاعتماد الذاتي في السيرفر.
  bool get isCompanyManager => roles.contains('company_manager');

  bool get isManager =>
      isCompanyManager ||
      keys.contains(Permissions.usersManage) ||
      keys.contains(Permissions.salesApprove);
}
