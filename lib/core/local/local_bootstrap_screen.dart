import 'package:flutter/material.dart';

import 'local_home_screen.dart';

/// تطبيق النسخة اللوكال (BACKEND=local): بوابة دخول ثم
/// رئيسية — بدون سوبابيز وبدون إنترنت.
class LocalBootstrapApp extends StatelessWidget {
  const LocalBootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سند — نسخة الجهاز',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
        // خط Cairo المضمّن — للعربي في الشاشات والطباعة (أوفلاين).
        fontFamily: 'Cairo',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: LocalGate(),
      ),
    );
  }
}
