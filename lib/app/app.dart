import 'package:flutter/material.dart';

import 'router/app_router.dart';
import 'theme/app_styles.dart';

class NagoMusicApp extends StatelessWidget {
  const NagoMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NagoMusic',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
      ),
      scrollBehavior: const AppScrollBehavior(),
      initialRoute: AppRouter.initialRoute,
      routes: AppRouter.routes,
    );
  }
}
