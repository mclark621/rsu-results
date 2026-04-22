import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'nav.dart';
import 'rsu/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? firebaseInitError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e, st) {
    firebaseInitError = e;
    debugPrint('Firebase.initializeApp failed: $e');
    debugPrint('$st');
  }
  runApp(RsuResultsRoot(firebaseInitError: firebaseInitError));
}

/// When Firebase fails to initialize, we show a dedicated screen instead of a broken app.
class RsuResultsRoot extends StatelessWidget {
  final Object? firebaseInitError;

  const RsuResultsRoot({super.key, this.firebaseInitError});

  @override
  Widget build(BuildContext context) {
    if (firebaseInitError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (context) {
            final tt = Theme.of(context).textTheme;
            final err = Theme.of(context).colorScheme.error;
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 56, color: err),
                        const SizedBox(height: 16),
                        Text('Firebase failed to initialize', style: tt.titleLarge, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        SelectableText('$firebaseInitError', style: tt.bodyMedium, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return const MyApp();
  }
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
