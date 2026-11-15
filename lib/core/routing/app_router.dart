import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/backend_mode.dart';
import '../../features/dashboard/presentation/screens/app_shell.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/approvals/presentation/screens/approvals_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/customers/presentation/screens/customer_detail_screen.dart';
import '../../features/customers/presentation/screens/customer_form_screen.dart';
import '../../features/customers/presentation/screens/customers_list_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/payments/presentation/screens/payment_form_screen.dart';
import '../../features/payments/presentation/screens/payments_list_screen.dart';
import '../../features/procurement/presentation/screens/procurement_detail_screen.dart';
import '../../features/procurement/presentation/screens/procurement_form_screen.dart';
import '../../features/procurement/presentation/screens/procurement_list_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/returns/presentation/screens/purchase_return_detail_screen.dart';
import '../../features/returns/presentation/screens/purchase_return_form_screen.dart';
import '../../features/returns/presentation/screens/return_policy_screen.dart';
import '../../features/returns/presentation/screens/returns_hub_screen.dart';
import '../../features/returns/presentation/screens/sales_return_detail_screen.dart';
import '../../features/returns/presentation/screens/sales_return_form_screen.dart';
import '../../features/manufacturing/presentation/screens/cz_detail_screen.dart';
import '../../features/manufacturing/presentation/screens/cz_form_screen.dart';
import '../../features/manufacturing/presentation/screens/manufacturing_hub_screen.dart';
import '../../features/manufacturing/presentation/screens/mo_detail_screen.dart';
import '../../features/manufacturing/presentation/screens/mo_form_screen.dart';
import '../../features/products/presentation/screens/product_barcodes_screen.dart';
import '../../features/products/presentation/screens/product_categories_screen.dart';
import '../../features/products/presentation/screens/product_detail_screen.dart';
import '../../features/products/presentation/screens/product_form_screen.dart';
import '../../features/products/presentation/screens/product_suppliers_screen.dart';
import '../../features/products/presentation/screens/products_list_screen.dart';
import '../../features/products/presentation/screens/purchase_prices_screen.dart';
import '../../features/shortages/presentation/screens/shortages_screen.dart';
import '../../features/expenses/presentation/screens/expenses_list_screen.dart';
import '../../features/expenses/presentation/screens/expense_form_screen.dart';
import '../../features/expenses/presentation/screens/expense_detail_screen.dart';
import '../../features/expenses/presentation/screens/expense_categories_screen.dart';
import '../../features/expenses/presentation/screens/recurring_screens.dart';
import '../../features/expenses/presentation/screens/installment_screens.dart';
import '../../features/shipping/presentation/screens/shipment_detail_screen.dart';
import '../../features/shipping/presentation/screens/shipment_form_screen.dart';
import '../../features/shipping/presentation/screens/shipments_list_screen.dart';
import '../../features/purchases/presentation/screens/pi_detail_screen.dart';
import '../../features/purchases/presentation/screens/pi_form_screen.dart';
import '../../features/purchases/presentation/screens/po_detail_screen.dart';
import '../../features/purchases/presentation/screens/po_form_screen.dart';
import '../../features/purchases/presentation/screens/purchases_hub_screen.dart';
import '../../features/sales/presentation/screens/sales_detail_screen.dart';
import '../../features/sales/presentation/screens/sales_form_screen.dart';
import '../../features/sales/presentation/screens/sales_list_screen.dart';
import '../../features/serials/presentation/screens/verify_serial_screen.dart';
import '../../features/stock_alerts/presentation/screens/stock_alerts_screen.dart';
import '../../features/suppliers/presentation/screens/supplier_detail_screen.dart';
import '../../features/suppliers/presentation/screens/supplier_form_screen.dart';
import '../../features/suppliers/presentation/screens/suppliers_list_screen.dart';
import '../../features/warehouses/presentation/screens/inventory_overview_screen.dart';
import '../../features/warehouses/presentation/screens/warehouse_detail_screen.dart';
import '../../features/warehouses/presentation/screens/warehouse_form_screen.dart';
import '../../features/warehouses/presentation/screens/warehouses_list_screen.dart';
import '../../features/users/presentation/screens/users_screen.dart';
import '../../features/maintenance/presentation/screens/maintenance_screen.dart';

/// Router rebuilds when login state changes. RLS remains the real guard.
final appRouterProvider = Provider<GoRouter>((ref) {
  final loggedIn = ref.watch(isLoggedInProvider);
  ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: loggedIn ? '/' : '/login',
    redirect: (context, state) {
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      // نسخة الجهاز: المسارات المستبعدة (مصاريف/موافقات/تصنيع)
      // تُحوَّل للرئيسية.
      if (loggedIn &&
          resolveBackendMode() == BackendMode.local &&
          isLocalExcludedRoute(state.matchedLocation)) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/approvals',
            builder: (context, state) =>
                const ApprovalsScreen(),
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) => const SalesListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const SalesFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => SalesDetailScreen(
                    invoiceId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/serials/verify',
            builder: (context, state) =>
                const VerifySerialScreen(),
          ),
          GoRoute(
            path: '/purchases',
            builder: (context, state) =>
                const PurchasesHubScreen(),
          ),
          GoRoute(
            path: '/purchase-returns/new',
            builder: (context, state) {
              final inv =
                  state.uri.queryParameters['invoice'];
              return PurchaseReturnFormScreen(
                  invoiceId: inv);
            },
          ),
          GoRoute(
            path: '/purchase-orders/new',
            builder: (context, state) =>
                const PurchaseOrderFormScreen(),
          ),
          GoRoute(
            path: '/purchase-orders/:id',
            builder: (context, state) => PurchaseOrderDetailScreen(
                orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/purchase-invoices/new',
            builder: (context, state) =>
                const PurchaseInvoiceFormScreen(),
          ),
          GoRoute(
            path: '/purchase-invoices/:id',
            builder: (context, state) =>
                PurchaseInvoiceDetailScreen(
                    invoiceId:
                        state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const ProductFormScreen(),
              ),
              GoRoute(
                path: 'barcodes',
                builder: (context, state) =>
                    const ProductBarcodesScreen(),
              ),
              GoRoute(
                path: 'categories',
                builder: (context, state) =>
                    const ProductCategoriesScreen(),
              ),
              GoRoute(
                path: 'purchase-prices',
                builder: (context, state) =>
                    const PurchasePricesScreen(),
              ),
              GoRoute(
                path: 'suppliers',
                builder: (context, state) =>
                    const ProductSuppliersScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => ProductDetailScreen(
                    productId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => ProductFormScreen(
                        productId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomersListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const CustomerFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => CustomerDetailScreen(
                    customerId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => CustomerFormScreen(
                        customerId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) => const SuppliersListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const SupplierFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => SupplierDetailScreen(
                    supplierId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => SupplierFormScreen(
                        supplierId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/warehouses',
            builder: (context, state) => const WarehousesListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const WarehouseFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => WarehouseDetailScreen(
                    warehouseId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => WarehouseFormScreen(
                        warehouseId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) =>
                const InventoryOverviewScreen(),
          ),
          GoRoute(
            path: '/shortages',
            builder: (context, state) =>
                const ShortagesScreen(),
          ),
          GoRoute(
            path: '/stock-alerts',
            builder: (context, state) =>
                const StockAlertsScreen(),
          ),
          GoRoute(
            path: '/expenses',
            builder: (context, state) =>
                const ExpensesListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const ExpenseFormScreen(),
              ),
              GoRoute(
                path: 'categories',
                builder: (context, state) =>
                    const ExpenseCategoriesScreen(),
              ),
              GoRoute(
                path: 'recurring',
                builder: (context, state) =>
                    const RecurringListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) =>
                        const RecurringFormScreen(),
                  ),
                ],
              ),
              GoRoute(
                path: 'installments',
                builder: (context, state) =>
                    const InstallmentsScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) =>
                        const InstallmentFormScreen(),
                  ),
                ],
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    ExpenseDetailScreen(
                        expenseId:
                            state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/manufacturing',
            builder: (context, state) =>
                const ManufacturingHubScreen(),
          ),
          GoRoute(
            path: '/customized/new',
            builder: (context, state) =>
                const CustomizedFormScreen(),
          ),
          GoRoute(
            path: '/customized/:id',
            builder: (context, state) => CustomizedDetailScreen(
                itemId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/manufacturing-orders/new',
            builder: (context, state) {
              final cz = state.uri.queryParameters['cz'];
              return ManufacturingOrderFormScreen(
                  customizedId: cz);
            },
          ),
          GoRoute(
            path: '/manufacturing-orders/:id',
            builder: (context, state) =>
                ManufacturingOrderDetailScreen(
                    orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/procurement',
            builder: (context, state) =>
                const ProcurementListScreen(),
          ),
          GoRoute(
            path: '/procurement/new',
            builder: (context, state) =>
                const ProcurementFormScreen(),
          ),
          GoRoute(
            path: '/procurement/:id',
            builder: (context, state) => ProcurementDetailScreen(
                requestId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) =>
                const NotificationsScreen(),
          ),
          GoRoute(
            path: '/shipping',
            builder: (context, state) =>
                const ShipmentsListScreen(),
          ),
          GoRoute(
            path: '/shipping/new',
            builder: (context, state) {
              final inv =
                  state.uri.queryParameters['invoice'];
              return ShipmentFormScreen(invoiceId: inv);
            },
          ),
          GoRoute(
            path: '/shipping/:id',
            builder: (context, state) => ShipmentDetailScreen(
                shipmentId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/payments',
            builder: (context, state) =>
                const PaymentsListScreen(),
          ),
          GoRoute(
            path: '/payments/new',
            builder: (context, state) {
              final q = state.uri.queryParameters;
              return PaymentFormScreen(
                salesInvoiceId: q['sales'],
                purchaseInvoiceId: q['purchase'],
              );
            },
          ),
          GoRoute(
            path: '/returns',
            builder: (context, state) =>
                const ReturnsHubScreen(),
          ),
          GoRoute(
            path: '/sales-returns/new',
            builder: (context, state) {
              final inv =
                  state.uri.queryParameters['invoice'];
              return SalesReturnFormScreen(
                  invoiceId: inv);
            },
          ),
          GoRoute(
            path: '/sales-returns/:id',
            builder: (context, state) =>
                SalesReturnDetailScreen(
                    returnId:
                        state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/purchase-returns/new',
            builder: (context, state) {
              final inv =
                  state.uri.queryParameters['invoice'];
              return PurchaseReturnFormScreen(
                  invoiceId: inv);
            },
          ),
          GoRoute(
            path: '/purchase-returns/:id',
            builder: (context, state) =>
                PurchaseReturnDetailScreen(
                    returnId:
                        state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/settings/returns',
            builder: (context, state) =>
                const ReturnPolicyScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) =>
                const ReportsScreen(),
          ),
          GoRoute(
            path: '/users',
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: '/maintenance',
            builder: (context, state) =>
                const MaintenanceScreen(),
          ),
        ],
      ),
    ],
  );
});
