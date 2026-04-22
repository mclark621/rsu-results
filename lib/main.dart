import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final RsuAppState _appState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _appState = RsuAppState();
    _router = AppRouter.createRouter(_appState);
  }

  @override
  void dispose() {
    _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
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
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
