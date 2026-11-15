// Stub للويب: dart:io غير متاح، فالطباعة المباشرة TCP غير مدعومة.
// البديل على الويب: طباعة PDF بمقاس الملصق واختيار XPrinter من حوار النظام.
Future<void> sendBytesToNetworkPrinter({
  required String ip,
  required int port,
  required List<int> bytes,
  Duration timeout = const Duration(seconds: 5),
}) {
  throw UnsupportedError(
    'الطباعة الشبكية المباشرة غير مدعومة على الويب — استخدم "PDF بمقاس الملصق" واختر طابعة XPrinter من حوار الطباعة.',
  );
}

Future<bool> checkNetworkPrinter({
  required String ip,
  required int port,
  Duration timeout = const Duration(seconds: 3),
}) async => false;

bool get kNetworkPrintingSupported => false;
