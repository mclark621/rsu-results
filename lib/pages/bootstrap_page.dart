import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:rsu_results/rsu/rsu_firebase_auth_service.dart';

import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/nav.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_navigated) return;
    _navigated = true;

    final state = context.read<RsuAppState>();
    state.bootstrap().then((_) async {
      if (!mounted) return;
      final accessToken = state.accessToken;
      if (accessToken == null) {
        context.go(AppRoutes.login);
        return;
      }

      // If we have an RSU token but no Firebase session (e.g. first load on a new device),
      // mint a Firebase Custom Token and sign in silently.
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await RsuFirebaseAuthService().signInWithRsuAccessToken(rsuAccessToken: accessToken);
        }

        // Now that FirebaseAuth is established, retry Firestore hydration for timer credentials.
        await state.hydrateTimerCredentialsFromFirestoreIfMissing();
      } catch (e) {
        // If this fails we can still run the app with RSU token-only (Option 1 behavior).
        // But we log it so it’s diagnosable.
        debugPrint('Bootstrap Firebase sign-in/hydration failed (ignored): $e');
      }

      if (!mounted) return;
      context.go(AppRoutes.dates);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, size: 40, color: cs.primary),
              const SizedBox(height: 14),
              Text('Preparing…', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
