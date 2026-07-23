import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings.dart';

/// Shared settings sheet: skip intro, stall prompt, quality.
/// [onQualityChanged] — called after user picks a quality (e.g. replay current).
Future<void> showPlayerSettingsSheet(
  BuildContext context, {
  VoidCallback? onQualityChanged,
  List<int>? qualityHeights,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Consumer<AppSettings>(
            builder: (_, settings, __) {
              final heights = <int>{0, ...(qualityHeights ?? const [360, 480, 720, 1080])};
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
