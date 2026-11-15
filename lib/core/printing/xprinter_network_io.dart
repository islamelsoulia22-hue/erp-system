import 'dart:io';

/// إرسال بايتات خام لطابعة شبكة (XPrinter واي فاي/LAN) عبر TCP 9100.
/// يعمل على: أندرويد / ويندوز / لينكس / macOS / iOS (pure Dart — بدون بلوجن).
Future<void> sendBytesToNetworkPrinter({
  required String ip,
  required int port,
  required List<int> bytes,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final socket = await Socket.connect(
    ip,
    port,
    timeout: timeout,
  );
  try {
    socket.add(bytes);
    await socket.flush();
    // مهلة قصيرة لاستقبال رد الطابعة (إن وجد) ثم إغلاق نظيف.
    await Future.delayed(const Duration(milliseconds: 300));
  } finally {
    try {
      await socket.close();
    } catch (_) {}
  }
}

/// فحص سريع: هل المنفذ مفتوح (الطابعة أونلاين)؟
Future<bool> checkNetworkPrinter({
  required String ip,
  required int port,
  Duration timeout = const Duration(seconds: 3),
}) async {
  try {
    final socket = await Socket.connect(ip, port, timeout: timeout);
    try {
      await socket.close();
    } catch (_) {}
    return true;
  } catch (_) {
    return false;
  }
}

/// مدعوم على كل المنصات الأصلية (غير الويب).
bool get kNetworkPrintingSupported => true;
