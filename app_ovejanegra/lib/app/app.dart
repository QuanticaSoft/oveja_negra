import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class OvejaNegraApp extends ConsumerWidget {
  const OvejaNegraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'OVEJA_NEGRA',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
