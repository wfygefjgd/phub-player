import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings.dart';

/// Shared settings sheet: skip intro, stall prompt, local proxy, quality.
Future<void> showPlayerSettingsSheet(
  BuildContext context, {
  VoidCallback? onQualityChanged,
  VoidCallback? onProxyChanged,
  List<int>? qualityHeights,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: 16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Consumer<AppSettings>(
            builder: (_, settings, __) {
              final heights = <int>{
                0,
                ...(qualityHeights ?? const [360, 480, 720, 1080]),
              };
              final options = heights.toList()..sort();
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const ListTile(
                      title: Text('设置',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      dense: true,
                    ),
                    SwitchListTile(
                      title: const Text('跳过片头约 15 秒',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                        '跳过片头广告；短视频自动关闭。',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFFFF6B35),
                      value: settings.skipIntro,
                      onChanged: settings.setSkipIntro,
                    ),
                    SwitchListTile(
                      title: const Text('卡顿时询问降画质',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                        '播放卡顿时弹窗询问；点「继续」则不切换。',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFFFF6B35),
                      value: settings.promptOnStall,
                      onChanged: settings.setPromptOnStall,
                    ),
                    const Divider(color: Colors.white12),
                    const ListTile(
                      title: Text('本地代理（非 TUN 时用）',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      subtitle: Text(
                        '本 App 无内置节点。开启后列表/详情/翻译走你填写的代理。'
                        '模拟器→电脑代理：主机 10.0.2.2；手机本机代理：127.0.0.1。'
                        '端口填 Clash/V2 的 HTTP 或 SOCKS 端口（如 7890）。',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      dense: true,
                    ),
                    SwitchListTile(
                      title: const Text('启用本地代理',
                          style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        settings.proxySummary,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      activeThumbColor: const Color(0xFFFF6B35),
                      value: settings.proxyEnabled,
                      onChanged: (v) async {
                        await settings.setProxyEnabled(v);
                        onProxyChanged?.call();
                      },
                    ),
                    if (settings.proxyEnabled)
                      _ProxyEditor(
                        settings: settings,
                        onApplied: onProxyChanged,
                      ),
                    const Divider(color: Colors.white12),
                    const ListTile(
                      title: Text('画质',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      dense: true,
                    ),
                    for (final h in options)
                      ListTile(
                        title: Text(
                          h == 0 ? '自动（偏好 ≤720p）' : '${h}p',
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: settings.qualityCap == h
                            ? const Icon(Icons.check, color: Color(0xFFFF6B35))
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          await settings.setQualityCap(h);
                          onQualityChanged?.call();
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class _ProxyEditor extends StatefulWidget {
  const _ProxyEditor({required this.settings, this.onApplied});

  final AppSettings settings;
  final VoidCallback? onApplied;

  @override
  State<_ProxyEditor> createState() => _ProxyEditorState();
}

class _ProxyEditorState extends State<_ProxyEditor> {
  late final TextEditingController _host;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.settings.proxyHost);
    _port = TextEditingController(text: '${widget.settings.proxyPort}');
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    await widget.settings.setProxyHost(_host.text);
    await widget.settings
        .setProxyPort(int.tryParse(_port.text.trim()) ?? 7890);
    widget.onApplied?.call();
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('代理已应用：${widget.settings.proxySummary}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChoiceChip(
                label: const Text('HTTP'),
                selected: s.proxyType == 'http',
                onSelected: (_) async {
                  await s.setProxyType('http');
                  widget.onApplied?.call();
                  setState(() {});
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('SOCKS5'),
                selected: s.proxyType == 'socks5',
                onSelected: (_) async {
                  await s.setProxyType('socks5');
                  widget.onApplied?.call();
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _host,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: '主机',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: '模拟器 10.0.2.2 / 真机 127.0.0.1',
              hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _port,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '端口',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: '7890',
              hintStyle: TextStyle(color: Colors.white30),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
            ),
            child: const Text('保存并应用代理'),
          ),
        ],
      ),
    );
  }
}
