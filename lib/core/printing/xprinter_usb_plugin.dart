import 'dart:async';
import 'dart:io';

import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import 'usb_receipt_printer.dart';

/// طابعة USB مكتشفة: اسم للعرض + معرّف ثابت + مقبض المنصة (io فقط).
class XUsbPrinterDevice {
  final String name;
  final String id;
  final Object? handle;
  const XUsbPrinterDevice({
    required this.name,
    required this.id,
    this.handle,
  });

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      other is XUsbPrinterDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// هل الطباعة عبر USB المباشر متاحة؟
/// - لينكس: ملف الجهاز (/dev/usb/lp*) — بدون مكتبة.
/// - أندرويد/ويندوز/macOS: عبر flutter_thermal_printer.
/// - الويب/iOS: غير متاح (استخدم الشبكة أو PDF).
bool get supportsXPrinterUsbDirect {
  try {
    return Platform.isAndroid ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;
  } catch (_) {
    return false;
  }
}

/// اكتشاف طابعات USB:
/// - لينكس: مسارات الأجهزة (/dev/usb/lp0...).
/// - أندرويد/ويندوز/macOS: مسح المكتبة (~4 ثوان).
Future<List<XUsbPrinterDevice>> discoverXPrinterUsbDevices() async {
  if (Platform.isLinux) {
    final paths = await findUsbReceiptPrinters();
    return [
      for (final p in paths)
        XUsbPrinterDevice(name: 'USB: $p', id: p),
    ];
  }
  if (!Platform.isAndroid &&
      !Platform.isWindows &&
      !Platform.isMacOS) {
    throw UnsupportedError(
      'الـ USB المباشر غير متاح على هذه المنصة — استخدم الشبكة أو PDF.',
    );
  }
  final mgr = FlutterThermalPrinter.instance;
  final found = <String, XUsbPrinterDevice>{};
  final sub = mgr.devicesStream.listen((list) {
    for (final p in list) {
      if (p.connectionType != ConnectionType.USB) continue;
      final label = (p.name?.isNotEmpty == true)
          ? p.name!
          : 'طابعة USB';
      final id =
          '${p.vendorId ?? '?'}:${p.productId ?? '?'}:${p.address ?? label}';
      found[id] = XUsbPrinterDevice(
        name: label,
        id: id,
        handle: p,
      );
    }
  });
  try {
    await mgr.getPrinters(
      connectionTypes: [ConnectionType.USB],
      refreshDuration: const Duration(seconds: 2),
    );
    await Future.delayed(const Duration(seconds: 4));
  } finally {
    await sub.cancel();
    try {
      await mgr.stopScan();
    } catch (_) {}
  }
  return found.values.toList();
}

/// إرسال بايتات خام (ESC/POS أو TSPL) لطابعة USB.
/// - [localPath]: مسار جهاز لينكس (/dev/usb/lp0) — أو معرّف جهاز
///   لينكس من الاكتشاف (يبدأ بـ /dev/).
/// - [device]: جهاز من الاكتشاف (أندرويد/ويندوز/macOS).
Future<void> sendBytesToXPrinterUsb({
  XUsbPrinterDevice? device,
  String? localPath,
  required List<int> bytes,
}) async {
  final path = localPath ??
      ((device != null && device.id.startsWith('/dev/'))
          ? device.id
          : null);
  if (path != null) {
    await writeBytesToUsbDevice(path, bytes);
    return;
  }
  if (!Platform.isAndroid &&
      !Platform.isWindows &&
      !Platform.isMacOS) {
    throw UnsupportedError(
      'الـ USB المباشر غير متاح هنا — استخدم الشبكة أو PDF.',
    );
  }
  final handle = device?.handle;
  if (handle is! Printer) {
    throw StateError('اختر طابعة USB من القائمة أولا.');
  }
  final mgr = FlutterThermalPrinter.instance;
  bool ok = false;
  try {
    // connect يطلب إذن USB من النظام (نافذة منبثقة) عند الحاجة.
    ok = await mgr.connect(handle).timeout(
          const Duration(seconds: 15),
          onTimeout: () => false,
        );
  } catch (e) {
    throw StateError('تعذر الاتصال بطابعة USB: $e');
  }
  if (!ok) {
    throw StateError(
      'تعذر الاتصال بطابعة USB.\n'
      'اتأكد إن الكابل متوصل (وعلى الموبايل: وصلة OTG)، '
      'ووافق على إذن USB لما يظهر.',
    );
  }
  try {
    await mgr.printData(handle, bytes);
  } catch (e) {
    throw StateError('تعذر الطباعة عبر USB: $e');
  }
}
