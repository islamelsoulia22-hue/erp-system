// Stub للويب/iOS: لا يوجد USB مباشر — البديل الشبكة أو PDF.
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

bool get supportsXPrinterUsbDirect => false;

Future<List<XUsbPrinterDevice>> discoverXPrinterUsbDevices() async =>
    throw UnsupportedError(
      'الـ USB المباشر غير متاح على الويب — استخدم الشبكة أو "PDF بمقاس الملصق".',
    );

Future<void> sendBytesToXPrinterUsb({
  XUsbPrinterDevice? device,
  String? localPath,
  required List<int> bytes,
}) =>
    throw UnsupportedError(
      'الـ USB المباشر غير متاح على الويب — استخدم الشبكة أو "PDF بمقاس الملصق".',
    );
