import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableErrorPanel extends StatelessWidget {
  const CopyableErrorPanel({super.key, required this.message, this.title});

  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: cs.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title ?? 'Error',
                  style: textTheme.titleSmall?.copyWith(color: cs.onErrorContainer),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(content: Text('Copied error details to clipboard'), behavior: SnackBarBehavior.floating),
                    );
                },
                icon: Icon(Icons.content_copy, color: cs.onErrorContainer),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectionArea(
            child: SelectableText(
              message,
              style: textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class CopyableSnackBar {
  static void show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          action: SnackBarAction(
            label: 'COPY',
            onPressed: () => Clipboard.setData(ClipboardData(text: message)),
          ),
        ),
      );
  }
}
