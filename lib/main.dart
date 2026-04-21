import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'nav.dart';
import 'rsu/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e, st) {
    debugPrint('Firebase.initializeApp failed: $e');
    debugPrint('$st');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final s = RsuAppState();
        // Kick off bootstrap immediately so deep links (e.g. /login) still load saved credentials.
        // Errors are handled internally and won’t crash the app.
        unawaited(s.bootstrap());
        return s;
      },
      child: Consumer<RsuAppState>(
        builder: (context, app, _) {
          final bg = app.pageBackgroundColor;
          final resolvedLight = bg == null ? lightTheme : lightTheme.copyWith(scaffoldBackgroundColor: bg);
          final resolvedDark = bg == null ? darkTheme : darkTheme.copyWith(scaffoldBackgroundColor: bg);
          return MaterialApp.router(
            title: 'Bay City Timing & Events',
            debugShowCheckedModeBanner: false,
            theme: resolvedLight,
            darkTheme: resolvedDark,
            themeMode: ThemeMode.system,
            routerConfig: AppRouter.router,
          );
        },
      ),
    );
  }
}
