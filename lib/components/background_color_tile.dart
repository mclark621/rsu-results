import 'package:flutter/material.dart';

class BackgroundColorTile extends StatelessWidget {
  final Color? color;
  final VoidCallback onTap;

  const BackgroundColorTile({super.key, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effective = color ?? Theme.of(context).scaffoldBackgroundColor;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: effective,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Page background', style: Theme.of(context).textTheme.titleSmall),
                  Text(color == null ? 'Theme default' : 'Custom', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.primary),
          ],
        ),
      ),
    );
  }
}
