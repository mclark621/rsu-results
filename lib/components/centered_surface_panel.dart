import 'package:flutter/material.dart';

class CenteredSurfacePanel extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const CenteredSurfacePanel({super.key, required this.child, this.maxWidth = 560, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              (padding as EdgeInsets?)?.left ?? 16,
              (padding as EdgeInsets?)?.top ?? 16,
              (padding as EdgeInsets?)?.right ?? 16,
              ((padding as EdgeInsets?)?.bottom ?? 16) + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
                boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 10))],
              ),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), child: child),
            ),
          ),
        ),
      ),
    );
  }
}
