# تقرير تنفيذ نسخة الجهاز (BACKEND=local)

التاريخ: 2026-10-12
الهدف: نسخة الجهاز (`flutter run --dart-define=BACKEND=local`) تشغّل **نفس شاشات
السحابة بالظبط** (منتجات/مبيعات/مشتريات/مخازن/عملاء/موردين/مدفوعات/مرتجعات/
تقارير/سيريال/شحن/مستخدمين/داشبورد) على SQLite أوفلاين — **بدون**: المصاريف،
مركز الموافقات، التصنيع.

الفكرة المعمارية: كل الريبوزيتوري تأخذ `dynamic _client` وتنادي سلاسل
`from().select().eq().order()...` — المحول (`LocalDbClient`) ينفذ نفس الواجهة
على SQLite فيعمل كود السحابة **بدون تعديل**.

---

## 1) المصادقة اللوكال بنفس API

### سكيما v5 (`lib/core/local/local_database.dart`, `latestVersion = 5`)
- جداول: `roles / permissions / role_permissions / profiles / user_roles /
  user_permission_grants / user_page_overrides` (بدون FK صريحة عمدا —
  الترتيب الحر للإدخال أهم، ولا RLS محليا).
- `user_page_overrides` بمفتاح مركب `(user_id, route)` بلا `id` منفصل حتى
  يعمل `upsert onConflict user_id,route` كـ `replace`.
- view `user_permissions` (دور + منح فردي — مثل migration `0023`) يُعاد
  بناؤها بـ `DROP + CREATE` (حتى لا يبقى تعريف قديم).
- بذر: 3 أدوار + **29 صلاحية** (`0001` الأساس + `expenses.*` من `0019` +
  `serials.verify` من `0030`) + ربط `company_manager` بالكل + `sales_manager`
  و`purchase_manager` بمجموعتيهما + ملف مدير الجهاز بنفس `id` صف `users`
  ودور المدير. كله idempotent (`INSERT OR IGNORE`).

### `LocalAuthShim` (`lib/core/local/local_query.dart`)
- يدعم `signInWithPassword / signOut / onAuthStateChange / currentUser`
  **بأنواع gotrue الحقيقية** (`User/Session/AuthState/AuthResponse`).
- فشل الدخول يرمي `AuthException('Invalid login credentials')` → نفس
  `InvalidCredentialsFailure` عبر `mapSupabaseError` الموجود.
- فحص `is_active` يتم بعده في `AuthRepository` عبر `profiles` **مثل السحابة
  تماما** (الدخول ينجح ثم يُسجَّل الخروج + `UnauthorizedFailure`).
- البث broadcast عام (`static`) + حفظ الجلسة في جدول `local_session` +
  `LocalSession.restore()` تُنادى من `main` (بقاء الدخول بعد إعادة التشغيل).
- `user_page_overrides.visible` و`customer_addresses.is_default` و
  `payment_methods.is_active` أُضيفت لأعمدة البوليان (الـ `INT 0/1` كان
  سيُقرأ غلط في مقارنات `!= false`).

### التحويل (نفس نمط المنتجات)
- `AuthRepository`: `_client` أصبح `dynamic` (بدون أي تغيير منطقي) +
  `authRepositoryProvider` يفرّع حسب `BackendMode`.
- `currentUserIdProvider` يفرّع (كان سيُسقط التطبيق محليا لأن
  `Supabase.instance` غير مهيأ).
- درس: الاستدعاء عبر `dynamic` يفقد استدلال `Stream<User?>` وقت التشغيل —
  الحل cast صريح `as Stream<AuthState>` قبل `.map`.

---

## 2) سكيما v6 (`latestVersion = 6`)

### جداول جديدة (`migrationV5toV6`)
- `purchase_orders` + `purchase_order_items` بالشكل الكامل (لم يكونا في
  سكيما v1 أصلا — اللوكال القديم كان فواتير فقط).
- `customer_addresses` (شامل الفهرس الجزئي `UNIQUE(customer_id) WHERE
  is_default = 1`)، `serial_sales`، `shipments`، `attachments`.

### أعمدة ناقصة (`v6MissingColumns` عبر `ensureColumn`)
- `sales_invoices`: لقطات العميل + `taxable_amount` + `delivery_method` +
  `credit_*` + `created_by/approved_*/rejected_*` + `updated_at`.
- `sales_invoice_items`: حقول الأصناف الخاصة (`item_type/custom_*/length*/
  width_*/raw_material_*/qty_per_roll/custom_notes/customized_item_id`) +
  `tax_amount` + `serial_numbers` (TEXT يحمل `'[]'`, يُفك عبر `_jsonColumns`).
- `purchase_invoices`: لقطات المورد + `purchase_order_id` + `taxable_amount`
  + حقول الاعتماد/الرفض + `received_at`.
- `purchase_order_items`: `received_quantity` — `purchase_invoice_items`:
  `product_name_snapshot`/`sku_snapshot`/`tax_amount`.
- `sales/purchase_returns`: `reason/created_by/updated_at` — بنودهما:
  `sku/tax_amount`.
- `customers`: `customer_code/email/tax_number/credit_limit/.../company` —
  `suppliers`: نفسها + `address/supply_category_id`.
- `warehouses`: `location/manager_id/...` — `stock_movements`: `created_by`
  — `stock_alerts`: `ack_by/ack_at` — `shortages`: `source_*/notes/...`
  — `payments`: `payment_number/transaction_reference/payment_date/notes/...`
  — `shipments`: `delivery_method` (ترسله شاشة الشحن — عمود إضافي عن
  السحابة، لا يضر).

### إعادة بناء `warehouse_stock`
- نسخة v1 كانت بمفتاح مركب وبدون `id`/`available_quantity` — والشاشات
  (`StockLine.id`, `_stockSelect`) تحتاجهما.
- `rebuildWarehouseStock`: جدول جديد (`id TEXT PK` + `UNIQUE(warehouse,
  product)` + `available_quantity GENERATED ALWAYS AS (quantity -
  reserved_quantity) STORED`) مع نقل البيانات، مع إسقاط التريجر الحارس
  والـ view مؤقتا (SQLite يرفض تغيير السكيما مع وجودهما) ثم إعادة إنشائهما.

### view `low_stock_products` (مثل `0010`) + بذر `SHIPPING_COMPANY`.

### `ensureColumn` أصبحت متسامحة (تتجاهل الجداول الغائبة) بعدما كشفت
الاختبارات أن الصرامة تكسر الترقيات الجزئية.

---

## 3) دوال RPC المنقولة (`lib/core/local/local_trade_rpc.dart`)

21 دالة بنفس الأسماء/الباراميترات/رسائل الخطأ (`snake_case`) — النهائية
المعتمدة من المigrations:

| الدوال | المصدر |
|---|---|
| `recalc/submit/approve/reject_sales_invoice` | `0005` + لقطة التكلفة `0028` (`nullif`) + سيريال تلقائي `0032` (المتكرر يتخطى بصمت) + تسوية غير-الآجل |
| `recalc/submit/receive_purchase_order` | `0006` + متوسط مرجح `0020` (قبل زيادة الرصيد) |
| `recalc/submit/approve/reject_purchase_invoice` | `0006` + `0035` (تسوية + زيادة مخزون الفواتير **المباشرة فقط**، المرتبطة بطلب تتخطى) |
| `sales/purchase_returnable` | `0029` (تجميع per صنف + `remaining = max(0, invoiced − returned)`) |
| `complete_sales/purchase_return` | `0029` (نافذة `return_policy` من `app_settings` + `OVER_RETURN` + حركات `SALES_RETURN`/`PURCHASE_RETURN`) |
| `create_stock_adjustment/transfer` | `0004` (المحجوز لا يُمس في النقل + حركتان) |
| `create_payment` | `0033` (وراثة الطرف من الفاتورة + تسوية القديم + تحديث `payment_status`) |
| `customer/supplier_balance` + `total_customer/supplier_outstanding` | `0033` (per فاتورة مع `greatest(0, ...)`) |
| `ship/deliver_shipment` | `0009` (الشحن يخصم الكمية **والمحجوز** + حركة `SALE` + فحص `NOT_RESERVED`) |
| `verify/register_serial_sale` | `0030` + `0031` (مطابقة case-insensitive) |
| `reset_all_data_keep_users` | `0022` (يمسح التجاري + عدّادات `seq_*` ويُبقي المستخدمين/الأدوار/الإعدادات) |

- `check_stock_levels` النهائية (`0035` = `0034` + إقفال النواقص المغطاة
  `DONE`): تُنادى بعد كل حركة مخزون (تنبيهات `MINIMUM`/`OUT_OF_STOCK` +
  نواقص تلقائية). بدون إشعارات (جدول `notifications` خارج النطاق).
- فحص الصلاحيات محليا عبر view `user_permissions` + إعفاء `company_manager`
  من منع الذاتي (مثل السيرفر) + توافق legacy (مستخدم بلا أدوار = كل
  الصلاحيات، لاختبارات v4 القديمة).
- `mapSupabaseError`: فرع `StateError` يستخدم `_mapServerMessage` المشترك
  (نفس تعيين السحابة حرفيا).

### إضافات المحول (`local_query.dart`)
- أرقام تلقائية (`_numberSpecs` + عدّاد `seq_<table>__<col>` في
  `app_settings`, مقاوم للفجوات): `SAL-/PO-/PUR-/RET-SAL-/RET-PUR-/PAY-/
  SHP-YYYY-NNNNNN` و`CUST-/SUP-NNNNNN` و`WH-NNN`.
- `storage` شيم (ملفات تحت `Documents/sanad_local_files`) بنفس توقيع
  `uploadBinary(path, bytes, {fileOptions})` / `createSignedUrl` /
  `remove` — فيعمل `AttachmentsRepository` **بدون تعديل** (بعد جعل
  `_client` فيه `dynamic`).
- `functions` شيم (`create-user/delete-user`) بنفس البروتوكول
  (`{status, data}` و`{'error': code}`) — فيعمل `UsersRepository`
  **بدون تعديل**.
- الإيميل المحلي بلا TLD (`admin@local`) مقبول في `create-user` وفي
  `Validators.email` (مشروط بـ `String.fromEnvironment('BACKEND')` —
  السحابة كما هي).

---

## 4) نفس شاشات السحابة في نسخة الجهاز

- **18 مزودا** تفرّع بنفس النمط: sales/purchases/warehouses/customers/
  suppliers/payments/returns/reports/serials/shipping/users/maintenance/
  attachments (+ products/auth سابقا + الاحتياطي expenses/procurement/
  manufacturing حتى لا يسقط أي `watch`).
- **الاستبعاد** (`lib/core/backend/backend_mode.dart`:
  `localExcludedRoutes` + `isLocalExcludedRoute`): `/approvals`
  `/procurement` `/manufacturing` `/customized/*` `/manufacturing-orders/*`
  `/expenses*` — تُخفى من `NavSectionList` + تحويل الراوتر للرئيسية.
- `AppShell._ensureSubscribed`: عودة مبكرة محليا (لا realtime) —
  `NotificationsRepository.unreadCount`: `Stream.value(0)` محليا.
- `pendingApprovalsProvider`: يتخطى التوريد/التصنيع/المصروفات محليا
  (مبيعات + مشتريات فقط).
- فحص التحديث الإجباري كان معطلا أصلا (`early-return` في
  `updateCheckProvider`) — لا تغيير needed.
- `main` لوكال: `ready()` + استعادة الجلسة + `ErpApp()` (شاشات اللوكال
  القديمة باقية في الملفات لكن غير مستخدمة).

---

## 5) الاختبارات (46 + بناء ناجح)

| الملف | التغطية |
|---|---|
| `test/local_query_test.dart` (5) | المحول |
| `test/local_products_repo_test.dart` | الأصناف end-to-end |
| `test/local_auth_test.dart` (3) | سكيما v5 + دورة دخول/صلاحيات/أدوار/ملف/خروج + بث الحالة + قراءة المستخدمين |
| `test/local_cloud_flows_test.dart` (**10**) | بيع نقدي (اعتماد→تحصيل تلقائي→شحن→تسليم)، آجل + تحقق، منع الذاتي لغير المدير، شراء (استلام جزئي→متوسط→مباشرة تزيد المخزون)، مرتجع (متبقي + مخزون)، مخزون (تحقق + تنبيهات)، سيريال (تلقائي + مكرر + يدوي)، دوال المستخدمين + reset + تقارير، ترقية v6 للشكل القديم، مرفقات |
| `test/local_erpapp_smoke_test.dart` (3) | إقلاع `ErpApp` لوكال + الاستبعاد (يُشغَّل بـ `--dart-define=BACKEND=local`) |
| `test/local_full_login_test.dart` (1) | دخول حقيقي `admin@local` → داشبورد السحابة (المستبعد مخفي، المبيعات ظاهرة) |
| الباقي | باركود/قاعدة/تجارة قديمة/طابعات/ويدجت — كلها خضراء |

- `flutter build linux --release --dart-define=BACKEND=local` ناجح ✅
- `flutter analyze lib`: بلا أخطاء (متبقٍ `info` واحد سابق في
  `failures.dart`).
- معروف مسبقا وخارج النطاق: `test/receipt_label_test.dart` مكسور على
  الشجرة النظيفة أيضا.

## التشغيل

```bash
# نسخة الجهاز (أوفلاين، SQLite) — نفس شاشات السحابة
flutter run --dart-define=BACKEND=local -d linux
# الدخول: admin@local / admin123
# ملف القاعدة: ~/Documents/sanad_local.db  (انسخه للنسخ الاحتياطي)
# ملفات المرفقات: ~/Documents/sanad_local_files/attachments/

# نسخة السحابة (افتراضي)
flutter run -d linux
flutter build linux --release   # نسخة السحابة
flutter build linux --release --dart-define=BACKEND=local  # نسخة الجهاز
```

## الباقي الاختياري

- ترحيل بيانات السحابة → لوكال (تصدير أصناف/عملاء/موردين/مخزون من
  Supabase واستيرادها في SQLite).
- دمج/حذف شاشات اللوكال القديمة (`lib/core/local/local_*_screens.dart`)
  بعد الاستغناء الكامل عنها — ملفاتها ما زالت تُترجم لكن `main` لا
  يستخدمها.

## دروس مستفادة (تقنية)

- الجرد الدقيق أولا: RPC تُستدعى عبر متغير (`_rpc('ship_shipment', ...)`)
  لا يمسكها `grep .rpc('` — الجرد بـ `grep _rpc('` أيضا.
- `insert/update` بعدها `.select().single()` يعمل في المحول (الـ select
  يُتجاهل ويُرجع الصف الكامل).
- `ALTER TABLE ... RENAME` يفشل لو تريجر/view يشير للجدول — إسقاط مؤقت
  ثم إعادة الإنشاء.
- اختبارات الويدجت (FakeAsync): أي I/O حقيقي (ملفات/sqflite) يعلق —
  الإعداد في `setUpAll` والتفاعل اللمسي للقاعدة داخل `tester.runAsync`
  مع `path_provider_platform_interface` مزيّف.
- `purchase_invoice_items` السحابية بأسماء `product_name_snapshot` /
  `sku_snapshot` (ليست `product_name`/`sku`) — و`shipments` بلا
  `delivery_method` (الشاشة ترسله رغم ذلك).
- `sales_return_items` المحلية v3 كانت بلا `sku` — كشفها إدخال المرتجع.
