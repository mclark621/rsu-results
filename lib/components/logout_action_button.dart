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
    final requiredCode = appState.logoutCode;

    // If a logout code is set, require it first
    if (requiredCode != null && requiredCode.isNotEmpty) {
      final codeValid = await _promptForLogoutCode(context, requiredCode);
      if (!codeValid) return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
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
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9))),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.actionOrange,
                    foregroundColor: AppColors.onActionOrange,
                    minimumSize: const Size.fromHeight(54),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    splashFactory: NoSplash.splashFactory,
                  ),
                  onPressed: () => context.pop(true),
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
                  ),
                  onPressed: () => context.pop(false),
                  child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    // Clear the logout code on logout
    await appState.clearLogoutCode();
    await appState.logout();
    if (!context.mounted) return;
    context.go(AppRoutes.login);
  }

  Future<bool> _promptForLogoutCode(BuildContext context, String requiredCode) async {
    final cs = Theme.of(context).colorScheme;
    final codeController = TextEditingController();
    String? errorText;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter Logout Code', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'A logout code is required to exit kiosk mode.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Logout Code',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  errorText: errorText,
                ),
                onChanged: (_) => setSheetState(() => errorText = null),
                onSubmitted: (_) {
                  if (codeController.text.trim() == requiredCode) {
                    Navigator.of(ctx).pop(true);
                  } else {
                    setSheetState(() => errorText = 'Incorrect code');
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.actionOrange,
                  foregroundColor: AppColors.onActionOrange,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  if (codeController.text.trim() == requiredCode) {
                    Navigator.of(ctx).pop(true);
                  } else {
                    setSheetState(() => errorText = 'Incorrect code');
                  }
                },
                child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
                ),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );

    return result == true;
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
