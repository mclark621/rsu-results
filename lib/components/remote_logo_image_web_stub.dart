import 'package:flutter/material.dart';

/// Non-web stub. This should never be used at runtime; web uses the real
/// implementation in `remote_logo_image_web.dart`.
class WebHtmlLogo extends StatelessWidget {
  final String url;
  final double height;
  final double width;
  final BorderRadius borderRadius;

  const WebHtmlLogo({super.key, required this.url, required this.height, required this.width, required this.borderRadius});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
