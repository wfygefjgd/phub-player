# PHUB Player

PHub 视频播放器 — 桌面版 (Python) + 移动版 (Flutter)

## 版本

### Desktop (Python)
桌面端 GUI 应用，支持浏览、搜索、播放、字幕翻译。

```bash
python phub_gui_v2.py
```

### Mobile (Flutter)
跨平台移动端，Android / iOS 双端支持。

```bash
cd mobile
flutter pub get
flutter run
```

打包 APK：
```bash
flutter build apk --release
```

打包 IPA：
```bash
flutter build ios --release
```

## 目录结构

```
├── phub_gui_v2.py          # 桌面主程序
├── subtitle_translator.py  # 字幕翻译
├── mobile/                 # Flutter 移动端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/        # 推荐 / 搜索 / 播放
│   │   ├── services/       # API 抓取与解析
│   │   └── widgets/
│   ├── android/
│   └── ios/
└── README.md
```

## 功能

- 推荐列表 / 热门 / 亚洲分类浏览
- 中文搜索（自动转英文）
- HLS 多清晰度播放
- 标题批量翻译（Google 免费接口）
- 下载管理

## 注意

- 移动端需自行解决网络访问
- 成人内容，请勿上架应用商店，仅侧载自用
