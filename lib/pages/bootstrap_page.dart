import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:rsu_results/components/centered_surface_panel.dart';
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
          final minted = await RsuFirebaseAuthService().signInWithRsuAccessToken(rsuAccessToken: accessToken);
          if ((state.rsuUserId ?? '').trim().isEmpty && minted.rsuUserId.trim().isNotEmpty) {
            await state.setRsuIdentity(rsuUserId: minted.rsuUserId, email: minted.email, firstName: minted.firstName, lastName: minted.lastName);
          }
        }

        // Now that FirebaseAuth is established, hydrate timer credentials from Firestore.
        await state.hydrateTimerCredentialsFromFirestore(overwriteLocal: true);
      } catch (e) {
        // If this fails we can still run the app with RSU token-only (Option 1 behavior).
        // But we log it so it's diagnosable.
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
      appBar: AppBar(title: const Text('Runsignup Results')),
      body: CenteredSurfacePanel(
        maxWidth: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 40, color: cs.primary),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Preparing…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Setting up your session.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
