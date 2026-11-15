# خطة نقل السيستم اللوكال لنفس UI/UX السحابة

الهدف: نسخة الجهاز (`BACKEND=local`) تشغّل **نفس شاشات السحابة بالظبط**
(منتجات/مبيعات/مشتريات/مخازن/عملاء/موردين/مدفوعات/مرتجعات/تقارير/سيريال/
شحن/مستخدمين/داشبورد) على SQLite أوفلاين — **بدون**: المصاريف، مركز
الموافقات، التصنيع.

## الفكرة المعمارية (مهم)

الريبوزيتوري في السحابة تأخذ `dynamic _client` وتنادي سلاسل
`from().select().eq().order()...`. بدل إعادة كتابة كل ريبوزيتوري،
عملنا **محول** ينفذ نفس الواجهة على SQLite فيشتغل كود السحابة بدون تعديل:

- `lib/core/local/local_query.dart` — `LocalDbClient` + `LocalTableQuery`
  (يدعم: select بما فيها embeds متداخلة `products!inner(...)` و`!inner`،
  eq/neq/gt/gte/lt/lte/like/ilike/in_/inFilter/is_/or/not، order، range،
  limit، single، maybeSingle، count، insert/update/delete/upsert مع إرجاع
  الصفوف، ملء افتراضيات السيرفر `id/created_at/updated_at`، تحويل
  البوليان INT→bool، فك أعمدة JSON مثل `app_settings.value`).
- `lib/core/local/local_rpc_registry.dart` — سجل دوال RPC المنقولة لـ Dart.
- `LocalDbClient.auth.currentUser?.id` شغال عبر `LocalSession`
  (يضبط عند الدخول/الخروج اللوكال).
- أخطاء FK في SQLite (`FOREIGN KEY constraint failed`) تتحول
  لـ `LinkedRecordFailure` في `lib/core/errors/failures.dart` زي السحابة.
- التحويل في كل مزود ريبوزيتوري بنفس النمط:
  ```dart
  if (resolveBackendMode() == BackendMode.local) {
    return ProductsRepository(LocalDbClient(() => LocalDatabase.instance.db));
  }
  return ProductsRepository(ref.watch(supabaseClientProvider));
  ```

## ما تم إنجازه ✅

1. **المحول** + 5 اختبارات (`test/local_query_test.dart`) — كلها ناجحة.
2. **سكيما v4** (`LocalDatabase.applyV4` + `latestVersion = 4`):
   جداول `product_categories/units/barcode_materials/app_settings/
   product_serials/audit_logs` + كل أعمدة `products` الناقصة +
   `product_barcodes.created_at` + فهرس primary-partial + trigger منع
   حذف الصنف المرتبط بمخزون + بذور (وحدات/فئات/BARCODE_ROLL/خامات/ضريبة)
   + `PRAGMA foreign_keys = ON`.
3. **الأصناف end-to-end**: `ProductsRepository` الحقيقي يعمل على SQLite
   (`test/local_products_repo_test.dart`: إنشاء/بحث/باركود/فئات/وحدات/
   خامات/سيريال/منع حذف مرتبط/حذف قسري عبر RPC).
4. **اختيار طابعة USB لكل نوع** (ريسيت/ملصقات) + خط Cairo ثابت في الطباعة.
5. **مسار TSPL أصلي** للباركود 128 + شيت XPrinter فيه USB مباشر.
6. **الباركود في شاشات اللوكال القديمة** (`test/local_barcode_test.dart`).
7. **المصادقة اللوكال بنفس API** ✅ (`test/local_auth_test.dart` — 3):
   سكيما v5 (`latestVersion = 5`: `roles/permissions/role_permissions/
   profiles/user_roles/user_permission_grants/user_page_overrides` +
   view `user_permissions` + بذر 29 صلاحية + مدير `company_manager`)،
   `LocalAuthShim` يدعم `signInWithPassword/signOut/onAuthStateChange`
   بأنواع gotrue الحقيقية، `AuthRepository` و`currentUserIdProvider`
   يفرّعان حسب الوضع — كود السحابة بدون تعديل.
8. **كل التدفقات التجارية محليا** ✅ (`test/local_cloud_flows_test.dart`
   — 10): سكيما v6 (`latestVersion = 6`: جداول `customer_addresses/
   serial_sales/shipments/attachments/purchase_orders/items` +
   كل الأعمدة الناقصة + إعادة بناء `warehouse_stock` بالشكل السحابي
   + view `low_stock_products`)، RPC منقولة (`lib/core/local/
   local_trade_rpc.dart`: بيع/شراء/مرتجع/مخزون/مدفوعات/شحن/سيريال/
   أرصدة/صيانة + `check_stock_levels` + أرقام تلقائية SAL-/PO-...).
9. **نسخة الجهاز = نفس شاشات السحابة** ✅: كل المزودات تفرّع
   (sales/purchases/warehouses/customers/suppliers/payments/returns/
   reports/serials/shipping/users/maintenance/attachments + الاحتياطي
   expenses/procurement/manufacturing)، `storage`/`functions` محلية
   (ملفات الجهاز + create-user/delete-user)، إخفاء المصاريف/الموافقات/
   التصنيع من القوائم + تحويل الراوتر للرئيسية، تعطيل realtime،
   `main` لوكال يشغّل `ErpApp`، `Validators.email` يقبل `admin@local`
   محليا — (`test/local_full_login_test.dart`: دخول → داشبورد حقيقي،
   `test/local_erpapp_smoke_test.dart`: إقلاع + استبعاد).

## الباقي (اختياري) ⏳

### ترحيل بيانات السحابة → لوكال
تصدير (أصناف/عملاء/موردين/مخزون) من Supabase واستيرادها في SQLite.

## التشغيل والاختبار

```bash
# نسخة الجهاز (أوفلاين، SQLite)
flutter run --dart-define=BACKEND=local -d linux
# الدخول: admin@local / admin123
# ملف القاعدة: ~/Documents/sanad_local.db  (انسخه للنسخ الاحتياطي)

# نسخة السحابة (افتراضي)
flutter run -d linux
flutter build linux --release   # نسخة السحابة
flutter build linux --release --dart-define=BACKEND=local  # نسخة الجهاز

# الاختبارات
flutter test test/local_query_test.dart        # المحول (5)
flutter test test/local_products_repo_test.dart # الأصناف الحقيقي
flutter test test/local_barcode_test.dart test/local_database_test.dart
flutter test test/local_auth_test.dart          # المصادقة (3)
flutter test test/local_cloud_flows_test.dart   # التدفقات (10)
flutter test --dart-define=BACKEND=local test/local_erpapp_smoke_test.dart
flutter test --dart-define=BACKEND=local test/local_full_login_test.dart
flutter test test/xprinter_logic_test.dart      # الطباعة (9)
```

## ملاحظات تقنية (دروس مستفادة)

- أعمدة SQLite الجديدة: `ADD COLUMN` بدون `IF NOT EXISTS` → استخدم
  `LocalDatabase.ensureColumn` (يفحص PRAGMA أولا).
- الجداول القائمة لا تقبل FK جديدة → استخدم triggers للمنع مع رسالة
  تحتوي `FOREIGN KEY constraint failed`.
- `update/delete` بدون شرط مرفوضة في المحول (للأمان).
- `or('...')` يدعم `and()` متداخلة بمستوى واحد.
- `insert` بقائمة يعمل؛ `upsert` يدعم `onConflict` أو replace.
- `insert/update` بعدها `.select().single()` يعمل (الـ select يُتجاهل
  ويرجع الصف الكامل).
- استدعاء RPC عبر متغير (`_rpc('ship_shipment', ...)`) يحتاج تنفيذا
  محليا بنفس الاسم — الجرد بـ `grep _rpc('` وليس `.rpc('` فقط.
- أخطاء RPC المحلية `StateError('CODE: ...')` تُعيَّن عبر
  `_mapServerMessage` المشترك (نفس نصوص السحابة).
- `authState()` عبر `dynamic` يفقد استدلال النوع وقت التشغيل —
  cast صريح `as Stream<AuthState>` قبل `.map`.
- `Validators.email` السحابي يرفض `admin@local` — استرخاء مشروط
  بـ `String.fromEnvironment('BACKEND')` في نفس الملف.
- اختبارات الويدجت (FakeAsync): أي I/O حقيقي (ملفات/sqflite) يعلق —
  الإعداد في `setUpAll` والتفاعل اللمسي للقاعدة داخل
  `tester.runAsync`، مع `path_provider_platform_interface` مزيّف.
- اختبارات sqflite: استخدم **ملف مؤقت** لكل تست (الـ in-memory المشتركة
  تتعارض بين التستات) وocclude `throwsA` مع Futures — استخدم try/catch.
- الطابعات: الريسيت `/dev/usb/lp2` (EUCCOI-80)، الملصقات `/dev/usb/lp1`
  (XP-420B) — التطبيق يحفظ اختيار كل نوع بعد أول حوار اختيار.
- مقاس ليبل XPrinter المجرب: 38×25 TSPL (باركود 128 أصلي + شريط عربي).
- تعريف CUPS لـ XP-420B غلط (HP Designjet) — التطبيق يطبع USB مباشر،
  ولو عمل تعارض: `sudo lpadmin -x XP-420B`.
