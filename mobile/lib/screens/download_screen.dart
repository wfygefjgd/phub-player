import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/download_service.dart';
import 'local_player_screen.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _selectionMode = false;

  void _showSettings(BuildContext context) {
    final svc = context.read<DownloadService>();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title:
              const Text('下载设置', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('调用浏览器下载',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  svc.browserMode ? '当前：浏览器下载' : '当前：内部下载',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                value: svc.browserMode,
                activeTrackColor: const Color(0xFFFF6B35),
                onChanged: (v) async {
                  await svc.setBrowserMode(v);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定',
                  style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, DownloadTask t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('删除任务', style: TextStyle(color: Colors.white)),
        content: const Text('确定要删除这个下载任务吗？',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              context.read<DownloadService>().deleteTask(t);
              Navigator.pop(ctx);
            },
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
  }

  void _playLocal(DownloadTask t) {
    if (t.localPath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalPlayerScreen(
          filePath: t.localPath!,
          title: t.title,
        ),
      ),
    );
  }

  void _enterSelectionMode(DownloadService svc) {
    setState(() => _selectionMode = true);
    svc.clearSelection();
  }

  void _exitSelectionMode(DownloadService svc) {
    setState(() => _selectionMode = false);
    svc.clearSelection();
  }

  void _confirmBatchDelete(BuildContext context, DownloadService svc) {
    final count = svc.selectedCount;
    if (count == 0) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('批量删除', style: TextStyle(color: Colors.white)),
        content: Text('确定删除选中的 $count 个任务吗？',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              svc.deleteSelected();
              Navigator.pop(ctx);
              if (svc.selectedCount == 0) {
                setState(() => _selectionMode = false);
              }
            },
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final svc = context.watch<DownloadService>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(_selectionMode
            ? '已选 ${svc.selectedCount} 项'
            : '下载'),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _exitSelectionMode(svc),
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            TextButton(
              onPressed: () => svc.selectAll(),
              child: const Text('全选',
                  style: TextStyle(color: Color(0xFFFF6B35))),
            ),
            IconButton(
              tooltip: '删除选中',
              icon: const Icon(Icons.delete, color: Color(0xFFFF6B35)),
              onPressed: () => _confirmBatchDelete(context, svc),
            ),
          ] else ...[
            IconButton(
              tooltip: '管理',
              icon: const Icon(Icons.checklist),
              onPressed: () => _enterSelectionMode(svc),
            ),
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings),
              onPressed: () => _showSettings(context),
            ),
          ],
        ],
      ),
      body: _buildBody(svc),
    );
  }

  Widget _buildBody(DownloadService svc) {
    final active = svc.activeTasks;
    final done = svc.doneTasks;

    if (active.isEmpty && done.isEmpty) {
      return const Center(
        child: Text('暂无下载任务',
            style: TextStyle(color: Colors.grey, fontSize: 15)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (active.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('进行中',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          for (final t in active) _taskCard(context, t),
          const SizedBox(height: 16),
        ],
        if (done.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('已完成',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          for (final t in done) _taskCard(context, t),
        ],
      ],
    );
  }

  Widget _taskCard(BuildContext context, DownloadTask t) {
    final isDone = t.state == TaskState.done;
    final stateText = switch (t.state) {
      TaskState.pending => '等待中',
      TaskState.downloading => '下载中 ${_fmtBytes(t.downloadedBytes)}',
      TaskState.paused => '已暂停',
      TaskState.done => '已完成  ${_fmtBytes(t.totalBytes)}',
      TaskState.failed => '失败: ${t.failReason ?? "unknown"}',
    };

    return Card(
      color: const Color(0xFF2A2A2A),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _selectionMode
            ? () => context.read<DownloadService>().toggleSelection(t)
            : (isDone ? () => _playLocal(t) : null),
        onLongPress: _selectionMode
            ? null
            : () {
                if (isDone) _confirmDelete(context, t);
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: Icon(
                        t.isSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: t.isSelected
                            ? const Color(0xFFFF6B35)
                            : Colors.white38,
                        size: 22,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  if (t.state == TaskState.downloading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B35),
                        strokeWidth: 2,
                      ),
                    ),
                  if (isDone)
                    const Icon(Icons.check_circle,
                        color: Color(0xFFFF6B35), size: 18),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${t.quality}  ·  $stateText',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (t.localPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    t.localPath!.split('/').last,
                    style: const TextStyle(
                        color: Color(0xFFFF6B35), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 6),
              if (!_selectionMode && !isDone)
                Row(
                  children: [
                    if (t.state == TaskState.downloading)
                      _iconButton(Icons.pause, '暂停', () {
                        context.read<DownloadService>().pause(t);
                      }),
                    if (t.state == TaskState.paused)
                      _iconButton(Icons.play_arrow, '继续', () {
                        context.read<DownloadService>().resume(t);
                      }),
                    if (t.state == TaskState.failed)
                      _iconButton(Icons.refresh, '重试', () {
                        t.state = TaskState.pending;
                        t.failReason = null;
                        context.read<DownloadService>().resume(t);
                      }),
                    _iconButton(Icons.delete_outline, '删除', () {
                      _confirmDelete(context, t);
                    }),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, color: Colors.white70, size: 20),
        ),
      ),
    );
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
