// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class WebHtmlLogo extends StatefulWidget {
  final String url;
  final double height;
  final double width;
  final BorderRadius borderRadius;

  const WebHtmlLogo({super.key, required this.url, required this.height, required this.width, required this.borderRadius});

  @override
  State<WebHtmlLogo> createState() => _WebHtmlLogoState();
}

class _WebHtmlLogoState extends State<WebHtmlLogo> {
  static int _seq = 0;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'remote-logo-img-${_seq++}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final img = web.HTMLImageElement();
      img.src = widget.url;
      img.alt = 'Race logo';
      img.style.width = '100%';
      img.style.height = '100%';
      img.style.objectFit = 'contain';
      img.style.display = 'block';
      // NOTE: intentionally do NOT set crossOrigin. For CanvasKit/WebGL it can
      // break when the server doesn’t send CORS headers. Since this is a plain
      // DOM <img>, it will still display fine.

      final wrapper = web.HTMLDivElement();
      wrapper.style.width = '${widget.width}px';
      wrapper.style.height = '${widget.height}px';
      wrapper.style.overflow = 'hidden';
      wrapper.style.borderRadius = '${widget.borderRadius.topLeft.x}px';
      wrapper.append(img);
      return wrapper;
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(height: widget.height, width: widget.width, child: HtmlElementView(viewType: _viewType));
}
