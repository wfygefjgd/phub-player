import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../services/app_mode.dart';
import 'browser_tab_model.dart';
import 'privacy_engine.dart';
import 'privacy_web_view.dart';
import 'tab_manager.dart';

class PrivacyBrowserApp extends StatelessWidget {
  const PrivacyBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TabManager(maxTabs: 3),
      child: MaterialApp(
        title: 'Privacy Browser',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4FC3F7),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0B0B0D),
        ),
        home: const PrivacyBrowserShell(),
      ),
    );
  }
}

class PrivacyBrowserShell extends StatefulWidget {
  const PrivacyBrowserShell({super.key});

  @override
  State<PrivacyBrowserShell> createState() => _PrivacyBrowserShellState();
}

class _PrivacyBrowserShellState extends State<PrivacyBrowserShell>
    with WidgetsBindingObserver {
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();
  final Map<String, InAppWebViewController> _controllers = {};
  bool _resetting = false;
  bool _backgroundWiped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final tab = context.read<TabManager>().active;
    _addressCtrl.text = tab.addressText;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addressCtrl.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_backgroundWiped || _resetting) return;
      _backgroundWiped = true;
      _silentBackgroundWipe();
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundWiped) {
        _backgroundWiped = false;
        _rebuildAfterWipe();
      }
    }
  }

  Future<void> _silentBackgroundWipe() async {
    _controllers.clear();
    await PrivacyEngine.nuclearWipe(exitAfter: false);
    if (!mounted) return;
    context.read<TabManager>().hardResetTabs();
    _addressCtrl.clear();
  }

  void _rebuildAfterWipe() {
    if (!mounted) return;
    setState(() {});
    final tab = context.read<TabManager>().active;
    _addressCtrl.text = tab.addressText;
  }

  InAppWebViewController? get _activeController {
    final id = context.read<TabManager>().active.id;
    return _controllers[id];
  }

  Future<void> _go(String raw) async {
    var input = raw.trim();
    if (input.isEmpty) return;
    late WebUri uri;
    if (input.startsWith('http://') || input.startsWith('https://')) {
      uri = WebUri(input);
    } else if (input.contains(' ') || !input.contains('.')) {
      uri = WebUri(
        'https://duckduckgo.com/?q=${Uri.encodeComponent(input)}',
      );
    } else {
      uri = WebUri('https://$input');
    }
    final c = _activeController;
    if (c == null) return;
    await c.loadUrl(urlRequest: URLRequest(url: uri));
    _addressFocus.unfocus();
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text('重置浏览器', style: TextStyle(color: Colors.white)),
        content: const Text(
          '将清除全部网站数据、缓存、Cookie、本地文件与设置，并强制冷启动。等同于重新安装。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runHardReset();
  }

  Future<void> _switchToPlayer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text('切换到播放器', style: TextStyle(color: Colors.white)),
        content: const Text(
          '下次启动将进入视频播放器（不会启动全量擦除）。\n请完全退出后重新打开。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppModeStore.save(AppMode.player);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已设为播放器，请完全退出后重新打开')),
    );
  }

  Future<void> _runHardReset() async {
    if (_resetting) return;
    setState(() => _resetting = true);
    _controllers.clear();
    context.read<TabManager>().hardResetTabs();
    _addressCtrl.clear();
    await PrivacyEngine.resetAndRelaunch();
    if (mounted) {
      setState(() => _resetting = false);
    }
  }

  void _syncAddressFromTab() {
    final tab = context.read<TabManager>().active;
    if (!_addressFocus.hasFocus) {
      _addressCtrl.value = TextEditingValue(
        text: tab.addressText,
        selection: TextSelection.collapsed(offset: tab.addressText.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<TabManager>();
    final tab = tm.active;
    _syncAddressFromTab();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  controller: _addressCtrl,
                  focusNode: _addressFocus,
                  tab: tab,
                  canAdd: tm.canAdd,
                  onSubmit: _go,
                  onBack: () => _activeController?.goBack(),
                  onForward: () => _activeController?.goForward(),
                  onReload: () => _activeController?.reload(),
                  onStop: () => _activeController?.stopLoading(),
                  onReset: _confirmReset,
                  onSwitchPlayer: _switchToPlayer,
                  onAddTab: () {
                    if (tm.addTab()) {
                      _addressCtrl.clear();
                    }
                  },
                ),
                if (tab.isLoading)
                  LinearProgressIndicator(
                    value: tab.progress > 0 && tab.progress < 100
                        ? tab.progress / 100
                        : null,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: const Color(0xFF4FC3F7),
                  ),
                _TabStrip(
                  manager: tm,
                  onSelect: (i) {
                    tm.select(i);
                    final t = tm.active;
                    _addressCtrl.text = t.addressText;
                  },
                  onClose: (i) {
                    final id = tm.tabs[i].id;
                    _controllers.remove(id);
                    tm.closeTab(i);
                    _addressCtrl.text = tm.active.addressText;
                  },
                ),
                Expanded(
                  child: IndexedStack(
                    index: tm.activeIndex,
                    children: [
                      for (final t in tm.tabs)
                        PrivacyWebView(
                          key: ValueKey(t.id),
                          tab: t,
                          onChanged: () {
                            if (mounted) {
                              tm.notifyTabChanged();
                            }
                          },
                          onControllerReady: (c) {
                            _controllers[t.id] = c;
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_resetting)
              const ColoredBox(
                color: Color(0xCC000000),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF4FC3F7)),
                      SizedBox(height: 16),
                      Text('正在核清并冷启动…', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.focusNode,
    required this.tab,
    required this.canAdd,
    required this.onSubmit,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onStop,
    required this.onReset,
    required this.onSwitchPlayer,
    required this.onAddTab,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final BrowserTabModel tab;
  final bool canAdd;
  final void Function(String) onSubmit;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onSwitchPlayer;
  final VoidCallback onAddTab;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141418),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: '后退',
              onPressed: tab.canGoBack ? onBack : null,
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            ),
            IconButton(
              tooltip: '前进',
              onPressed: tab.canGoForward ? onForward : null,
              icon: const Icon(Icons.arrow_forward_ios, size: 18),
            ),
            IconButton(
              tooltip: tab.isLoading ? '停止' : '刷新',
              onPressed: tab.isLoading ? onStop : onReload,
              icon: Icon(tab.isLoading ? Icons.close : Icons.refresh, size: 20),
            ),
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'[\u0000]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '搜索或输入网址',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF222228),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: onSubmit,
                ),
              ),
            ),
            IconButton(
              tooltip: '新建标签',
              onPressed: canAdd ? onAddTab : null,
              icon: const Icon(Icons.add, size: 22),
            ),
            IconButton(
              tooltip: '切换到播放器',
              onPressed: onSwitchPlayer,
              icon: const Icon(Icons.play_circle_outline, size: 22),
            ),
            IconButton(
              tooltip: '重置浏览器',
              onPressed: onReset,
              icon: const Icon(Icons.delete_forever_outlined,
                  color: Colors.redAccent, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.manager,
    required this.onSelect,
    required this.onClose,
  });

  final TabManager manager;
  final void Function(int) onSelect;
  final void Function(int) onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: manager.tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final t = manager.tabs[i];
          final selected = i == manager.activeIndex;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 140, minWidth: 72),
              padding: const EdgeInsets.only(left: 10, right: 4),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF2A2A32) : const Color(0xFF1A1A20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? const Color(0xFF4FC3F7) : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.isBlank ? '新标签' : t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : Colors.white60,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => onClose(i),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14, color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
