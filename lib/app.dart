import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_states.dart';
import 'features/updates/presentation/providers/update_providers.dart';
import 'features/updates/presentation/screens/force_update_screen.dart';

class ErpApp extends ConsumerWidget {
  const ErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final updateCheck = ref.watch(updateCheckProvider);
    return MaterialApp.router(
      title: 'SANAD — سند',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: updateCheck.maybeWhen(
            // تحديث إجباري متوفر = حجب التطبيق حتى التحديث.
            data: (d) => d.updateRequired && d.manifest != null
                ? ForceUpdateScreen(decision: d)
                : (child ?? const SizedBox.shrink()),
            // أثناء الفحص أو أي عطل = ادخل عادي (fail-open).
            orElse: () => child ?? const LoadingSkeleton(rows: 8),
          )),
      routerConfig: router,
    );
  }
}
