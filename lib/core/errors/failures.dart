import 'package:supabase_flutter/supabase_flutter.dart';

/// Domain-level failure with Arabic user-facing message.
/// Never expose raw Postgres errors to UI.
sealed class AppFailure implements Exception {
  final String messageAr;
  const AppFailure(this.messageAr);

  @override
  String toString() => messageAr;
}

class NetworkFailure extends AppFailure {
  const NetworkFailure()
      : super('لا يوجد اتصال بالإنترنت، برجاء المحاولة مرة أخرى.');
}

class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure()
      : super('لا تملك صلاحية تنفيذ هذه العملية.');
}

class InvalidCredentialsFailure extends AppFailure {
  const InvalidCredentialsFailure()
      : super('البريد الإلكتروني أو كلمة المرور غير صحيحة.');
}

class EmailNotConfirmedFailure extends AppFailure {
  const EmailNotConfirmedFailure()
      : super('برجاء تأكيد البريد الإلكتروني أولا ثم حاول الدخول.');
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure(String entityAr)
      : super('$entityAr غير موجود.');
}

class InsufficientStockFailure extends AppFailure {
  const InsufficientStockFailure()
      : super('الكمية المطلوبة غير متوفرة في المخزن.');
}

class SelfApprovalFailure extends AppFailure {
  const SelfApprovalFailure()
      : super('لا تملك صلاحية اعتماد هذه الفاتورة.');
}

class InvalidStatusFailure extends AppFailure {
  const InvalidStatusFailure()
      : super('الحالة الحالية لا تسمح بهذه العملية، حدّث الصفحة وحاول مجددا.');
}

class EmailExistsFailure extends AppFailure {
  const EmailExistsFailure()
      : super('هذا البريد مسجل بالفعل لحساب آخر.');
}

class InvalidUserInputFailure extends AppFailure {
  const InvalidUserInputFailure()
      : super('تحقق من البريد وكلمة المرور (6 أحرف على الأقل).');
}

class LinkedRecordFailure extends AppFailure {
  const LinkedRecordFailure()
      : super('لا يمكن الحذف النهائي لأنه مرتبط بمخزون أو حركات أخرى.');
}

class ReservedStockFailure extends AppFailure {
  const ReservedStockFailure()
      : super('لا يمكن الحذف: الصنف عليه كمية محجوزة لفاتورة معتمدة.');
}

class CannotDeleteSelfFailure extends AppFailure {
  const CannotDeleteSelfFailure()
      : super('لا يمكنك حذف حسابك الخاص.');
}

class UnknownFailure extends AppFailure {
  const UnknownFailure()
      : super('حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.');
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(String msg) : super(msg);
}

/// Maps Supabase/Postgres errors to Arabic failures.
AppFailure mapSupabaseError(Object error) {
  // أي عطل شبكة (DNS / TCP / TLS / Proxy / Timeout) — مهما كان نوع
  // الـ exception — يظهر كـ NetworkFailure. مهم جدا في نسخة Windows
  // الـ release لأن نفس العطل يأتي بأنواع مختلفة:
  // SocketException / HttpException / ClientException / TimeoutException
  // / HandshakeException / AuthRetryableFetchException ...
  if (_isNetworkError(error)) {
    return const NetworkFailure();
  }
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_grant')) {
      return const InvalidCredentialsFailure();
    }
    if (msg.contains('email not confirmed')) {
      return const EmailNotConfirmedFailure();
    }
    return const UnauthorizedFailure();
  }
  // نسخة الجهاز (SQLite): منع الحذف لوجود سجلات مرتبطة —
  // نفس رسالة LinkedRecordFailure في السحابة (code 23503).
  // triggers المحلية ترمي 'FOREIGN KEY constraint failed'.
  final localMsg = error.toString().toLowerCase();
  if (localMsg.contains('foreign key constraint failed') ||
      localMsg.contains('foreign key constraint')) {
    return const LinkedRecordFailure();
  }
  // نسخة الجهاز: دوال RPC المحلية ترمي StateError بنفس نصوص
  // السيرفر (snake_case) — نفس تعيين السحابة أدناه.
  if (error is StateError) {
    return _mapServerMessage(
      localMsg.replaceAll('_', ' '),
      '',
    );
  }
  if (error is PostgrestException) {
    // السيرفر بيرمي snake_case زي CANNOT_APPROVE_OWN — وحّدها لمسافات
    // عشان المطابقة تشتغل مع الشرط (_) ومع المسافات.
    final msg = error.message.toLowerCase().replaceAll('_', ' ');
    final code = error.code ?? '';
    return _mapServerMessage(msg, code);
  }
  return const UnknownFailure();
}

/// تعيين رسائل السيرفر/RPC (سحابة Postgrest أو محلية StateError)
/// لنفس الـ Failures — [msg] بحروف صغيرة ومسافات بدل (_).
AppFailure _mapServerMessage(String msg, String code) {
  if (msg.contains('system category')) {
    return const ValidationFailure(
        'فئة بكر الباركود محمية ولا يمكن مسحها أو إيقافها.');
  }
  if (code == '42501' ||
      msg.contains('row-level security') ||
      msg.contains('no permission') ||
      msg.contains('not authenticated') ||
      msg.contains('inactive user')) {
    return const UnauthorizedFailure();
  }
  // انتهاك مفتاح أجنبي: حذف سجل مرتبط بسجلات أخرى.
  // مهم: يتفحص قبل رسالة المخزون لأن رسالة Postgres نفسها
  // تحتوي اسم جدول مثل warehouse_stock فيخدع فحص contains('stock').
  if (code == '23503') {
    return const LinkedRecordFailure();
  }
  // فقط رسالة الرصيد غير الكافي — لا نطابق كلمة stock العامة
  // حتى لا تتحول أخطاء الـ FK (warehouse_stock) لرسالة مخزون مضللة.
  if (msg.contains('insufficient stock') ||
      msg.contains('insufficientstock')) {
    return const InsufficientStockFailure();
  }
  if (msg.contains('reserved stock') || msg.contains('has reserved')) {
    return const ReservedStockFailure();
  }
  if (msg.contains('self-approval') ||
      msg.contains('cannot approve own')) {
    return const SelfApprovalFailure();
  }
  if (msg.contains('invalid status')) {
    return const InvalidStatusFailure();
  }
  if (msg.contains('not found') ||
      msg.contains('product not found') ||
      code == 'P0002') {
    return const NotFoundFailure('السجل');
  }
  if (code == '23505' ||
      msg.contains('duplicate') ||
      msg.contains('unique')) {
    return const UnknownFailure();
  }
  return const UnknownFailure();
}

/// True when [error] is a connectivity failure (no DNS / no TCP / TLS /
/// proxy / firewall / timeout), regardless of the concrete exception type.
///
/// نسخة Windows الـ release ترمي نفس العطل بأنواع ورسائل مختلفة عن
/// الموبايل/الويب، لذلك نفحص النوع + النص معا.
bool _isNetworkError(Object error) {
  final typeName = error.runtimeType.toString().toLowerCase();
  // أنواع صريحة = شبكة مباشرة (تشمل AuthRetryableFetchException).
  if (typeName.contains('socketexception') ||
      typeName.contains('httpexception') ||
      typeName.contains('clientexception') ||
      typeName.contains('timeoutexception') ||
      typeName.contains('handshakeexception') ||
      typeName.contains('tlsexception') ||
      typeName.contains('networkexception') ||
      typeName.contains('retryable') ||
      typeName.contains('fetchexception')) {
    return true;
  }
  final msg = error.toString().toLowerCase();
  const markers = [
    'socketexception',
    'failed host lookup',
    'failed to lookup',
    'network is unreachable',
    'network unreachable',
    'host unreachable',
    'no address associated with hostname',
    'temporary failure in name resolution',
    'nodename nor servname',
    'name resolution',
    'unable to resolve',
    'dns',
    'connection refused',
    'connection timed out',
    'connection reset',
    'connection closed',
    'connection aborted',
    'no connection could be made',
    'software caused connection',
    'failed to connect',
    'connection error',
    'network error',
    'network request failed',
    'fetch failed',
    'failed to fetch',
    'fetchexception',
    'handshake',
    'certificate',
    'tls',
    'ssl',
    'proxy',
    'firewall',
    'unreachable',
    'timed out',
    'timedout',
    'timeout',
  ];
  for (final m in markers) {
    if (msg.contains(m)) return true;
  }
  return false;
}
