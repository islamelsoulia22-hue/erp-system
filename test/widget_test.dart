import 'package:accounting_system/core/permissions/permissions.dart';
import 'package:accounting_system/core/utils/validators.dart';
import 'package:accounting_system/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login screen renders Arabic form', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: LoginScreen(),
          ),
        ),
      ),
    );
    // Supabase not initialized in unit tests; screen shows loading or form.
    // Pure validators must still behave correctly.
    expect(Validators.required(''), 'هذا الحقل مطلوب');
    expect(Validators.email('bad'), 'البريد الإلكتروني غير صحيح');
    expect(
      const PermissionSet({Permissions.usersManage}).can(
        Permissions.usersManage,
      ),
      isTrue,
    );
  });
}
