import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rsu_results/components/remote_logo_image_web.dart' if (dart.library.io) 'package:rsu_results/components/remote_logo_image_web_stub.dart';

/// Displays a remote logo image.
///
/// On Flutter web (CanvasKit), some CDNs serve images without CORS headers.
/// Those images still open fine in a browser tab, but CanvasKit may fail to
/// paint them onto a WebGL canvas.
///
/// To make logos render reliably on web, we fall back to an HTML `<img>`
/// element via [HtmlElementView].
class RemoteLogoImage extends StatelessWidget {
  final String url;
  final double height;

  /// Used to compute a stable width so the layout doesn’t jump.
  final double aspectRatio;

  final BorderRadius borderRadius;

  const RemoteLogoImage({super.key, required this.url, required this.height, this.aspectRatio = 2.2, this.borderRadius = const BorderRadius.all(Radius.circular(12))});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cleaned = url.trim();
    final width = height * aspectRatio;

    if (cleaned.isEmpty) {
      return Container(
        height: height,
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surface, borderRadius: borderRadius, border: Border.all(color: cs.outline.withValues(alpha: 0.18))),
        child: Center(child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant, size: 32)),
      );
    }

    if (kIsWeb) return WebHtmlLogo(url: cleaned, height: height, width: width, borderRadius: borderRadius);
    return ClipRRect(borderRadius: borderRadius, child: _NativeNetworkLogo(url: cleaned, height: height, width: width));
  }
}

class _NativeNetworkLogo extends StatelessWidget {
  final String url;
  final double height;
  final double width;

  const _NativeNetworkLogo({required this.url, required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Image.network(
      url,
      height: height,
      width: width,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        if (frame != null) return child;
        return Container(
          height: height,
          width: width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.18))),
          child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
        );
      },
      errorBuilder: (context, error, stack) {
        debugPrint('RemoteLogoImage failed to load: $error (url=$url)');
        return Container(
          height: height,
          width: width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.error.withValues(alpha: 0.35))),
          child: Center(child: Icon(Icons.broken_image_outlined, color: cs.error, size: 32)),
        );
      },
    );
  }
}
