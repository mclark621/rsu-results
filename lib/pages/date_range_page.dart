import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/centered_surface_panel.dart';
import 'package:rsu_results/components/logout_action_button.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/theme.dart';

class DateRangePage extends StatefulWidget {
  const DateRangePage({super.key});

  @override
  State<DateRangePage> createState() => _DateRangePageState();
}

class _DateRangePageState extends State<DateRangePage> {
  DateTimeRange? _range;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<RsuAppState>();
    _range ??= app.dateRange;
  }

  Future<void> _pickRange() async {
    final initial = _range ?? DateTimeRange(start: DateTime.now(), end: DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initial,
      helpText: 'Select date range',
    );
    if (picked == null) return;
    setState(() => _range = picked);
  }

  Future<void> _continue() async {
    final range = _range;
    if (range == null) return;
    final app = context.read<RsuAppState>();
    await app.setDateRange(range);
    if (!mounted) return;
    context.go(AppRoutes.races);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final range = _range;

    return Scaffold(
      appBar: AppBar(
        title: null,
        actions: [
          IconButton(tooltip: 'Global settings', onPressed: () => context.push(AppRoutes.settingsGlobal), icon: Icon(Icons.manage_accounts_outlined, color: cs.primary)),
          const LogoutActionButton(),
        ],
      ),
      body: CenteredSurfacePanel(
        maxWidth: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pick a date range', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('We\'ll list races in this date range.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9))),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.actionOrange,
                foregroundColor: AppColors.onActionOrange,
                minimumSize: const Size.fromHeight(54),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                splashFactory: NoSplash.splashFactory,
              ),
              onPressed: _pickRange,
              icon: Icon(Icons.date_range, color: AppColors.onActionOrange),
              label: Text(
                range == null ? 'Select dates' : '${_fmt(range.start)} → ${_fmt(range.end)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onActionOrange, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.actionPurple,
                foregroundColor: AppColors.onActionPurple,
                minimumSize: const Size.fromHeight(54),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                splashFactory: NoSplash.splashFactory,
              ),
              onPressed: range == null ? null : _continue,
              icon: Icon(Icons.arrow_forward, color: AppColors.onActionPurple),
              label: Text('Continue', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.onActionPurple)),
            ),
            const SizedBox(height: 10),
            Text(
              'Tip: wider ranges may load more races.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
