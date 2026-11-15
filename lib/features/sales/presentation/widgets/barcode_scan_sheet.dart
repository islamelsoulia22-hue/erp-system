import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera barcode scanner sheet. Returns raw barcode string via pop.
class BarcodeScanSheet extends StatefulWidget {
  const BarcodeScanSheet({super.key});

  @override
  State<BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

class _BarcodeScanSheetState extends State<BarcodeScanSheet>
    with SingleTickerProviderStateMixin {
  final _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  late final AnimationController _scanAnim;

  @override
  void initState() {
    super.initState();
    // خط الليزر يتحرك من فوق لتحت ويرجع يعيد.
    _scanAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _scanAnim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bound scanner height to available screen so the sheet never
    // overflows on small devices (was fixed 320 -> 103px overflow).
    // مكبّر عشان الكونتينر كله يبان.
    final screenH = MediaQuery.sizeOf(context).height;
    final scanH = (screenH * 0.58).clamp(320.0, 460.0);
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text('امسح الباركود',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'وجّه الكاميرا داخل المربع',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // ── كونتينر الاسكانر ──────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: scanH,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _ctrl,
                        onDetect: (capture) {
                          if (_done) return;
                          final code = capture
                              .barcodes.firstOrNull?.rawValue
                              ?.trim();
                          if (code != null && code.isNotEmpty) {
                            _done = true;
                            Navigator.of(context).pop(code);
                          }
                        },
                      ),
                      // تعتيم خفيف فوق وتحت عشان يبرز مربع المسح
                      _ScannerOverlay(),
                      // زوايا المربع
                      const _CornerBrackets(),
                      // خط الليزر الأحمر المتحرك من فوق لتحت
                      AnimatedBuilder(
                        animation: _scanAnim,
                        builder: (context, child) {
                          // 12px padding فوق وتحت عشان الخط مابيخرجش برا
                          final top = 12 +
                              _scanAnim.value * (scanH - 28);
                          return Positioned(
                            top: top,
                            left: 24,
                            right: 24,
                            child: child!,
                          );
                        },
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius:
                                BorderRadius.circular(99),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.redAccent
                                    .withValues(alpha: 0.9),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: Colors.red
                                    .withValues(alpha: 0.45),
                                blurRadius: 28,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'ابحث تلقائيًا عند التقاط الكود',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// تعتيم علوي وسفلي عشان الإحساس بمربع المسح في النص.
class _ScannerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: [
          Container(
              height: 56,
              color: Colors.black.withValues(alpha: 0.35)),
          const Spacer(),
          Container(
              height: 56,
              color: Colors.black.withValues(alpha: 0.35)),
        ],
      ),
    );
  }
}

/// 4 زوايا بيضا على شكل L لتحديد منطقة المسح.
class _CornerBrackets extends StatelessWidget {
  const _CornerBrackets();

  @override
  Widget build(BuildContext context) {
    const inset = 18.0;
    const len = 34.0;
    const thick = 4.0;
    const color = Colors.white;
    Border buildBorder({
      bool l = false,
      bool r = false,
      bool t = false,
      bool b = false,
    }) {
      return Border(
        left: l
            ? const BorderSide(color: color, width: thick)
            : BorderSide.none,
        right: r
            ? const BorderSide(color: color, width: thick)
            : BorderSide.none,
        top: t
            ? const BorderSide(color: color, width: thick)
            : BorderSide.none,
        bottom: b
            ? const BorderSide(color: color, width: thick)
            : BorderSide.none,
      );
    }

    Widget corner({required bool left, required bool top}) {
      return Positioned(
        left: left ? inset : null,
        right: left ? null : inset,
        top: top ? 68 : null,
        bottom: top ? null : 68,
        child: Container(
          width: len,
          height: len,
          decoration: BoxDecoration(
            border: buildBorder(
              l: left,
              r: !left,
              t: top,
              b: !top,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        children: [
          corner(left: true, top: true),
          corner(left: false, top: true),
          corner(left: true, top: false),
          corner(left: false, top: false),
        ],
      ),
    );
  }
}
