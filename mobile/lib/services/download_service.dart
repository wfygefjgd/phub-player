import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TaskState { pending, downloading, paused, done, failed }

class DownloadTask {
  final String url;
  final String quality;
  final Map<String, String> headers;
  final String title;
  final DateTime createdAt;
  String? localPath;
  int downloadedBytes;
  int totalBytes;
  TaskState state;
  String? failReason;
  CancelToken? cancelToken;
  bool isSelected;

  DownloadTask({
    required this.url,
    required this.quality,
    required this.headers,
    required this.title,
    DateTime? createdAt,
    this.localPath,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.state = TaskState.pending,
    this.failReason,
    this.isSelected = false,
  }) : createdAt = createdAt ?? DateTime.now();

  String get id => '${url}_$quality';
}

class DownloadService extends ChangeNotifier {
  static const _keyMode = 'download_mode_browser';
  static const _keyTasks = 'download_tasks_done';

  final Dio _dio;
  final List<DownloadTask> _tasks = [];
  bool _processing = false;
  bool _browserMode = false;

  DownloadService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 60),
              ),
            ) {
    _loadMode();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyTasks);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      var removed = false;
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final path = m['localPath'] as String?;
        if (path != null && path.isNotEmpty && !File(path).existsSync()) {
          removed = true;
          continue;
        }
        _tasks.add(DownloadTask(
          url: m['url'] ?? '',
          quality: m['quality'] ?? '',
          headers: {},
          title: m['title'] ?? '',
          createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
          localPath: path,
          downloadedBytes: m['downloadedBytes'] ?? 0,
          totalBytes: m['totalBytes'] ?? 0,
          state: TaskState.done,
        ));
      }
      if (removed) await _saveTasks();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveTasks() async {
    final done = _tasks.where((t) => t.state == TaskState.done).toList();
    final list = done.map((t) => {
      'url': t.url,
      'quality': t.quality,
      'title': t.title,
      'createdAt': t.createdAt.toIso8601String(),
      'localPath': t.localPath,
      'downloadedBytes': t.downloadedBytes,
      'totalBytes': t.totalBytes,
    }).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTasks, jsonEncode(list));
  }

  Future<void> _loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    _browserMode = prefs.getBool(_keyMode) ?? false;
  }

  Future<void> setBrowserMode(bool v) async {
    _browserMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMode, v);
    notifyListeners();
  }

  bool get browserMode => _browserMode;
  List<DownloadTask> get tasks => _tasks;
  List<DownloadTask> get activeTasks => _tasks.where((t) => t.state != TaskState.done).toList();
  List<DownloadTask> get doneTasks => _tasks.where((t) => t.state == TaskState.done).toList();

  Future<void> enqueue(DownloadTask task) async {
    if (_browserMode) return;
    _tasks.add(task);
    notifyListeners();
    _process();
  }

  void pause(DownloadTask task) {
    if (task.state != TaskState.downloading) return;
    task.cancelToken?.cancel();
    task.state = TaskState.paused;
    notifyListeners();
  }

  void resume(DownloadTask task) {
    if (task.state != TaskState.paused) return;
    task.state = TaskState.pending;
    task.cancelToken = null;
    notifyListeners();
    _process();
  }

  void deleteTask(DownloadTask task) {
    task.cancelToken?.cancel();
    if (task.localPath != null) {
      File(task.localPath!).delete().ignore();
    }
    _tasks.remove(task);
    _saveTasks();
    notifyListeners();
  }

  int get selectedCount => _tasks.where((t) => t.isSelected).length;

  void deleteSelected() {
    final toDelete = _tasks.where((t) => t.isSelected).toList();
    for (final t in toDelete) {
      t.cancelToken?.cancel();
      if (t.localPath != null) File(t.localPath!).delete().ignore();
      _tasks.remove(t);
    }
    _saveTasks();
    notifyListeners();
  }

  void selectAll() {
    for (final t in _tasks) {
      t.isSelected = true;
    }
    notifyListeners();
  }

  void clearSelection() {
    for (final t in _tasks) {
      t.isSelected = false;
    }
    notifyListeners();
  }

  void toggleSelection(DownloadTask t) {
    t.isSelected = !t.isSelected;
    notifyListeners();
  }

  void _process() async {
    if (_processing) return;
    _processing = true;
    while (true) {
      final task = _tasks.cast<DownloadTask?>().firstWhere(
            (t) => t!.state == TaskState.pending,
            orElse: () => null,
          );
      if (task == null) break;
      try {
        task.state = TaskState.downloading;
        task.cancelToken = CancelToken();
        notifyListeners();
        await _downloadTask(task);
        task.state = TaskState.done;
        _saveTasks();
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          // paused – state already set
        } else {
          task.state = TaskState.failed;
          task.failReason = e.message ?? e.toString();
        }
      } catch (e) {
        task.state = TaskState.failed;
        task.failReason = e.toString();
      }
      task.cancelToken = null;
      notifyListeners();
    }
    _processing = false;
  }

  Future<void> _downloadTask(DownloadTask task) async {
    final dir = Directory('/storage/emulated/0/Download/phub_player');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeTitle = _sanitize(task.title);
    final base = '${dir.path}/${safeTitle}_${task.quality}';

    // Resolve the real segment playlist URL (handle master → sub-playlist)
    final segmentsPlaylist = await _resolveSegmentsPlaylist(task.url, task.headers, task.cancelToken);
    if (segmentsPlaylist == null) {
      // Not HLS — direct download
      final outPath = '$base.mp4';
      await _dio.download(
        task.url,
        outPath,
        options: Options(headers: task.headers),
        cancelToken: task.cancelToken,
      );
      task.downloadedBytes = await File(outPath).length();
      task.totalBytes = task.downloadedBytes;
      task.localPath = outPath;
      return;
    }

    // segmentsPlaylist is (playlistUrl, m3u8Content)
    final baseUri = Uri.parse(segmentsPlaylist.$1);
    final segments = _parseSegments(segmentsPlaylist.$2, baseUri);
    if (segments.isEmpty) throw Exception('No segments found in playlist');

    final outPath = '$base.mp4';
    final sink = File(outPath).openWrite();
    try {
      for (var i = 0; i < segments.length; i++) {
        final segRes = await _dio.get<List<int>>(
          segments[i],
          options: Options(
            headers: task.headers,
            responseType: ResponseType.bytes,
            followRedirects: true,
          ),
          cancelToken: task.cancelToken,
        );
        final data = segRes.data ?? [];
        sink.add(data);
        task.downloadedBytes += data.length;
        notifyListeners();
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    task.totalBytes = task.downloadedBytes;
    task.localPath = outPath;
  }

  /// Resolves the final segment-level playlist URL.
  /// Returns (playlistUrl, m3u8Content) or null for non-HLS content.
  Future<(String, String)?> _resolveSegmentsPlaylist(
    String url,
    Map<String, String> headers,
    CancelToken? cancelToken,
  ) async {
    final res = await _dio.get<String>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
      cancelToken: cancelToken,
    );
    final m3u8 = res.data ?? '';
    if (!m3u8.contains('#EXTM3U')) return null;

    // Check if this is a master/variant playlist
    if (m3u8.contains('#EXT-X-STREAM-INF')) {
      // Pick the highest bandwidth variant
      final variants = <(int, String)>[];
      final lines = m3u8.split('\n').map((l) => l.trim()).toList();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF:')) {
          final bwM = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
          final bw = bwM != null ? int.tryParse(bwM.group(1)!) ?? 0 : 0;
          if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
            final subUrl = _resolveUrl(lines[i + 1], url);
            variants.add((bw, subUrl));
          }
        }
      }
      if (variants.isEmpty) throw Exception('No variant streams found');
      variants.sort((a, b) => b.$1.compareTo(a.$1));
      // Recursively resolve the best variant's playlist
      return _resolveSegmentsPlaylist(variants.first.$2, headers, cancelToken);
    }

    return (url, m3u8);
  }

  String _resolveUrl(String relative, String base) {
    final uri = Uri.tryParse(relative);
    if (uri != null && uri.hasScheme) return relative;
    final baseUri = Uri.parse(base);
    return baseUri.resolve(relative).toString();
  }

  List<String> _parseSegments(String m3u8, Uri baseUri) {
    return m3u8
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .map((l) {
      final uri = Uri.tryParse(l);
      if (uri == null || !uri.hasScheme) return baseUri.resolve(l).toString();
      return l;
    }).toList();
  }

  String _sanitize(String s) {
    final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }
}
