class VideoItem {
  final String url;
  final String title;
  final String duration;
  final String? thumb;

  const VideoItem({
    required this.url,
    required this.title,
    this.duration = '-',
    this.thumb,
  });

  String get viewkey {
    final m = RegExp(r'viewkey=([^&#]+)').firstMatch(url);
    return m?.group(1) ?? url;
  }

  VideoItem copyWith({
    String? url,
    String? title,
    String? duration,
    String? thumb,
  }) {
    return VideoItem(
      url: url ?? this.url,
      title: title ?? this.title,
      duration: duration ?? this.duration,
      thumb: thumb ?? this.thumb,
    );
  }
}

class StreamQuality {
  final int width;
  final int height;
  final String url;

  const StreamQuality({
    required this.width,
    required this.height,
    required this.url,
  });

  String get label {
    if (height > 0) return '${height}p';
    if (width > 0) return '${width}w';
    return 'auto';
  }

  int get pixels => width * height;
}

class VideoDetail {
  final String url;
  final String title;
  final String? description;
  final int durationSec;
  final String? thumb;
  final List<StreamQuality> streams;
  final bool unavailable;
  final bool countryBlocked;

  const VideoDetail({
    required this.url,
    required this.title,
    this.description,
    required this.durationSec,
    this.thumb,
    required this.streams,
    this.unavailable = false,
    this.countryBlocked = false,
  });

  String get durationLabel {
    if (durationSec <= 0) return '-';
    final h = durationSec ~/ 3600;
    final m = (durationSec % 3600) ~/ 60;
    final s = durationSec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  StreamQuality? get bestStream {
    if (streams.isEmpty) return null;
    final sorted = [...streams]..sort((a, b) => b.pixels.compareTo(a.pixels));
    return sorted.first;
  }

  /// Prefer <= 720p for mobile data / stability.
  StreamQuality? get preferredStream {
    if (streams.isEmpty) return null;
    final under720 = streams.where((s) => s.height > 0 && s.height <= 720).toList();
    if (under720.isNotEmpty) {
      under720.sort((a, b) => b.pixels.compareTo(a.pixels));
      return under720.first;
    }
    return bestStream;
  }
}
