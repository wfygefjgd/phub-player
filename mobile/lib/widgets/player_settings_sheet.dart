import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings.dart';

/// Shared settings sheet: skip intro, proxy, quality (manual only).
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
                    const Divider(color: Colors.white12),
                    // C: 代理状态一眼懂
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.networkStatusTitle,
                            style: const TextStyle(
                              color: Color(0xFFFF6B35),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            settings.networkStatusDetail,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const ListTile(
                      title: Text('网络代理',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      subtitle: Text(
                        '默认跟随系统代理（不写死地址）。读不到则直连。'
                        '已开 TUN 可关掉此项。列表通但播不动时，可开 TUN 或换 HTTP 代理。',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      dense: true,
                    ),
                    SwitchListTile(
                      title: const Text('使用系统/本地代理',
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
    final s = widget.settings;
    _host = TextEditingController(text: s.proxyHost);
    _port = TextEditingController(
      text: s.proxyPort > 0 ? '${s.proxyPort}' : '',
    );
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    await widget.settings.setProxyHost(_host.text);
    final p = int.tryParse(_port.text.trim());
    await widget.settings.setProxyPort(p ?? 0);
    widget.onApplied?.call();
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(widget.settings.proxySummary),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _redetect() async {
    await widget.settings.refreshSystemProxy();
    _host.text = widget.settings.proxyHost;
    _port.text =
        widget.settings.proxyPort > 0 ? '${widget.settings.proxyPort}' : '';
    widget.onApplied?.call();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(widget.settings.proxySummary),
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
              const Spacer(),
              TextButton(
                onPressed: _redetect,
                child: const Text('重新检测系统代理'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _host,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: '主机（可空=未配置）',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: '由系统检测或手动填写',
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
              labelText: '端口（可空）',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: '不写死默认端口',
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
            child: const Text('保存手动代理'),
          ),
        ],
      ),
    );
  }
}
