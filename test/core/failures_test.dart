import 'package:accounting_system/core/errors/failures.dart';
import 'package:accounting_system/core/permissions/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manager permission set detects approval rights', () {
    const perms = PermissionSet({Permissions.salesApprove});
    expect(perms.can(Permissions.salesApprove), isTrue);
    expect(perms.can(Permissions.purchasesApprove), isFalse);
    expect(perms.isManager, isTrue);
  });

  test('sales user cannot approve (UX check)', () {
    const perms = PermissionSet({Permissions.salesCreate});
    expect(perms.can(Permissions.salesApprove), isFalse);
    expect(perms.isManager, isFalse);
  });

  test('unknown errors map to Arabic generic message', () {
    final f = mapSupabaseError(Exception('boom'));
    expect(f, isA<UnknownFailure>());
    expect(f.messageAr.isNotEmpty, isTrue);
  });
}
