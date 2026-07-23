# PHUB Player

PHub 视频播放器 — 桌面版 (Python) + 移动版 (Flutter)

## 版本

当前源码：`mobile/pubspec.yaml` → **1.6.1+16**（默认播放器 + 可选隐私浏览器）。  
桌面成品包常见为 **1.5.3～1.5.7**（以本机 `PHUB-Player-v*.apk/ipa` 为准）。

**发布说明 / 版本对照：** 见 [CHANGELOG.md](./CHANGELOG.md)  
（1.5.x 细项由产物时间线 + 源码注释补全；其中 iOS 多版多为随安卓同步打包。）

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

## 免责声明

- 本软件仅供学习、研究和技术交流目的使用。
- 使用者须自行遵守所在地法律法规，自行解决网络访问问题。
- 所有视频内容来自第三方网站，版权归原作者或相关权利人所有。
- 开发者不对软件的使用后果承担任何责任，包括但不限于数据丢失、设备损坏或法律纠纷。
- 严禁将本软件用于任何商业用途或非法目的。
- 成人内容请勿上架任何应用商店，仅限个人侧载自用。
- 如您不同意以上条款，请立即停止使用并删除本软件。
