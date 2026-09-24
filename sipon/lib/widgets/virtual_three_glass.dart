import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/virtual_drinking_models.dart';
import 'virtual_drinking_canvas.dart';

/// Flutter owns interaction state; the embedded renderer only draws the glass.
class VirtualThreeGlass extends StatefulWidget {
  const VirtualThreeGlass({
    super.key,
    required this.catalog,
    required this.drink,
    required this.glass,
    required this.iceCode,
    required this.remaining,
    required this.tilt,
    required this.pageVisible,
    required this.apiBaseUrl,
    required this.fallbackMotion,
    required this.fallbackFill,
  });

  final VirtualDrinkingCatalog catalog;
  final VirtualDrink drink;
  final VirtualGlass glass;
  final String iceCode;
  final double remaining;
  final bool tilt;
  final bool pageVisible;
  final String apiBaseUrl;
  final Animation<double> fallbackMotion;
  final Animation<double> fallbackFill;

  static bool canRender(VirtualDrinkingCatalog catalog, VirtualGlass glass) {
    if (catalog.modelRendererVersion != '1' ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    return catalog.asset(glass.modelAssetCode)?.kind == 'glass_model' &&
        glass.liquidProfile.length >= 2;
  }

  @override
  State<VirtualThreeGlass> createState() => _VirtualThreeGlassState();
}

class _VirtualThreeGlassState extends State<VirtualThreeGlass> {
  WebViewController? _controller;
  bool _scriptLoaded = false;
  bool _modelReady = false;
  bool _failed = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    if (VirtualThreeGlass.canRender(widget.catalog, widget.glass)) {
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    try {
      final script = await rootBundle.loadString(
        'assets/virtual_drinking/three/scene.bundle.js',
      );
      if (!mounted) return;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel('SiponThree', onMessageReceived: _message);
      setState(() => _controller = controller);
      _timeout = Timer(const Duration(seconds: 18), () {
        if (mounted && !_modelReady) _fail();
      });
      await controller.loadHtmlString('''<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}canvas{display:block;width:100%;height:100%}</style></head>
<body><script>$script</script></body></html>''');
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() => _failed = true);
    final controller = _controller;
    if (_scriptLoaded && controller != null) {
      unawaited(
        controller
            .runJavaScript('window.siponScene.setVisible(false);')
            .catchError((Object _) {}),
      );
    }
  }

  void _message(JavaScriptMessage message) {
    if (!mounted) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      switch (data['type']) {
        case 'loaded':
          _scriptLoaded = true;
          _sendState();
          _sendVisible();
          return;
        case 'ready':
          _timeout?.cancel();
          setState(() => _modelReady = true);
          return;
        case 'error':
          _fail();
          return;
      }
    } catch (_) {
      _fail();
    }
  }

  @override
  void didUpdateWidget(covariant VirtualThreeGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drink.code != widget.drink.code ||
        oldWidget.glass.code != widget.glass.code ||
        oldWidget.iceCode != widget.iceCode ||
        oldWidget.remaining != widget.remaining ||
        oldWidget.tilt != widget.tilt) {
      if (oldWidget.glass.code != widget.glass.code) {
        _modelReady = false;
        _failed = !VirtualThreeGlass.canRender(widget.catalog, widget.glass);
        if (!_failed) _sendVisible();
      }
      _sendState();
    }
    if (oldWidget.pageVisible != widget.pageVisible) _sendVisible();
  }

  Map<String, Object?> _payload() {
    final ice = widget.catalog.iceOptions
        .where((option) => option.code == widget.iceCode)
        .firstOrNull;
    final base = Uri.tryParse(widget.apiBaseUrl);
    final safeBase =
        base != null && (base.scheme == 'https' || base.scheme == 'http')
        ? base.origin
        : '';
    return {
      'baseUrl': safeBase,
      'assets': widget.catalog.assets
          .map(
            (asset) => {
              'code': asset.code,
              'kind': asset.kind,
              'url': asset.url,
            },
          )
          .toList(growable: false),
      'glass': {
        'assetCode': widget.glass.modelAssetCode,
        'profile': widget.glass.liquidProfile,
      },
      'drink': {
        'color':
            '#${widget.drink.liquidColor.toARGB32().toRadixString(16).substring(2)}',
        'opacity': widget.drink.opacity,
        'foam': widget.drink.foam,
        'foamColor':
            '#${widget.drink.foamColor.toARGB32().toRadixString(16).substring(2)}',
        'bubbles': widget.drink.bubbles,
        'garnish': widget.drink.garnish,
      },
      'ice': {
        'code': widget.iceCode,
        'renderer': ice?.renderer ?? '',
        'assetCode': ice?.modelAssetCode ?? '',
      },
      'remaining': widget.remaining,
      'tilt': widget.tilt,
    };
  }

  void _sendState() {
    final controller = _controller;
    if (!_scriptLoaded || controller == null || _failed) return;
    unawaited(
      controller
          .runJavaScript(
            'window.siponScene.setState(${jsonEncode(_payload())});',
          )
          .catchError((Object _) {}),
    );
  }

  void _sendVisible() {
    final controller = _controller;
    if (!_scriptLoaded || controller == null) return;
    unawaited(
      controller
          .runJavaScript('window.siponScene.setVisible(${widget.pageVisible});')
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _timeout?.cancel();
    final controller = _controller;
    if (_scriptLoaded && controller != null) {
      unawaited(
        controller
            .runJavaScript('window.siponScene.dispose();')
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_failed && _controller != null)
          IgnorePointer(child: WebViewWidget(controller: _controller!)),
        if (!_modelReady || _failed)
          AnimatedBuilder(
            animation: Listenable.merge([
              widget.fallbackFill,
              widget.fallbackMotion,
            ]),
            builder: (_, _) => VirtualGlassCanvas(
              drink: widget.drink,
              glass: widget.glass,
              iceCode: widget.iceCode,
              remaining: widget.fallbackFill.value,
              progress: widget.fallbackMotion.value,
            ),
          ),
      ],
    );
  }
}
