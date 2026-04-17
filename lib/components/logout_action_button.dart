import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';

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

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.pop(true),
                  icon: Icon(Icons.logout, color: cs.onPrimary),
                  label: Text('Log out', style: TextStyle(color: cs.onPrimary)),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => context.pop(false),
                  child: Text('Cancel', style: TextStyle(color: cs.primary)),
                ),
              ],
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
