import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_tab_model.dart';

typedef TabChanged = void Function();

class PrivacyWebView extends StatefulWidget {
  const PrivacyWebView({
    super.key,
    required this.tab,
    required this.onChanged,
    required this.onControllerReady,
  });

  final BrowserTabModel tab;
  final TabChanged onChanged;
  final void Function(InAppWebViewController controller) onControllerReady;

  @override
  State<PrivacyWebView> createState() => _PrivacyWebViewState();
}

class _PrivacyWebViewState extends State<PrivacyWebView>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;

  static final InAppWebViewSettings _settings = InAppWebViewSettings(
    incognito: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: false,
    cacheEnabled: false,
    thirdPartyCookiesEnabled: false,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    allowsBackForwardNavigationGestures: true,
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: false,
    useWideViewPort: true,
    loadWithOverviewMode: true,
    transparentBackground: false,
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );

  @override
  bool get wantKeepAlive => true;

  Future<void> _syncNav() async {
    final c = _controller;
    if (c == null) return;
    widget.tab.canGoBack = await c.canGoBack();
    widget.tab.canGoForward = await c.canGoForward();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return InAppWebView(
      key: widget.tab.viewKey,
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: _settings,
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onControllerReady(controller);
      },
      onLoadStart: (controller, url) {
        widget.tab.isLoading = true;
        widget.tab.progress = 0;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        widget.onChanged();
      },
      onProgressChanged: (controller, progress) {
        widget.tab.progress = progress;
        widget.tab.isLoading = progress < 100;
        widget.onChanged();
      },
      onLoadStop: (controller, url) async {
        widget.tab.isLoading = false;
        widget.tab.progress = 100;
        final s = url?.toString() ?? '';
        if (s.isNotEmpty) {
          widget.tab.url = s;
          if (s != 'about:blank') {
            widget.tab.addressText = s;
          }
        }
        final title = await controller.getTitle();
        if (title != null && title.trim().isNotEmpty) {
          widget.tab.title = title.trim();
        } else if (widget.tab.isBlank) {
          widget.tab.title = '新标签';
        }
        await _syncNav();
      },
      onTitleChanged: (controller, title) {
        if (title != null && title.trim().isNotEmpty) {
          widget.tab.title = title.trim();
          widget.onChanged();
        }
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        final s = url?.toString() ?? '';
        if (s.isNotEmpty && s != 'about:blank') {
          widget.tab.url = s;
          widget.tab.addressText = s;
        }
        await _syncNav();
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
