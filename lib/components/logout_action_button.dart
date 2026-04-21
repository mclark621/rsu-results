import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/theme.dart';

class LogoutActionButton extends StatelessWidget {
  final Color? color;

  const LogoutActionButton({super.key, this.color});

  Future<void> _confirmAndLogout(BuildContext context) async {
    final appState = context.read<RsuAppState>();
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        const title = 'Log out?';
        const subtitle = 'This will clear your stored OAuth token on this device.';
        final textTheme = Theme.of(context).textTheme;

        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(subtitle, style: textTheme.bodyMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.actionOrange,
                        foregroundColor: AppColors.onActionOrange,
                        minimumSize: const Size.fromHeight(54),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        splashFactory: NoSplash.splashFactory,
                      ),
                      icon: const Icon(Icons.logout, color: AppColors.onActionOrange),
                      label: const Text('Log out', style: TextStyle(color: AppColors.onActionOrange)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => context.pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        splashFactory: NoSplash.splashFactory,
                      ),
                      child: Text('Cancel', style: TextStyle(color: cs.primary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    await appState.logout();
    if (!context.mounted) return;
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<RsuAppState>(
      builder: (context, state, _) {
        return IconButton(
          tooltip: 'Logout',
          onPressed: () => _confirmAndLogout(context),
          icon: Icon(Icons.logout, color: color ?? cs.primary),
        );
      },
    );
  }
}
