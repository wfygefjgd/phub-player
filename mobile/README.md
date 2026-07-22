# PHUB Player (Flutter 纯客户端)

方案 A：无后端、无内置代理。手机直接访问源站，网络由用户自行解决。

## 功能

- 推荐列表（首页/热门等页面抓取）
- 搜索 + 加载更多
- 详情解析 `flashvars` → HLS 多清晰度
- `media_kit` 播放（带 Referer / UA）
- 标题批量翻译（Google 免费接口）

## 环境

1. 安装 [Flutter](https://docs.flutter.dev/get-started/install)（本机可用 `C:\Users\96335\flutter`）
2. Android SDK / 模拟器或真机
3. 手机能直接访问 pornhub.com（VPN 等自行处理）

## 运行

```bash
cd mobile
flutter pub get
flutter run
```

打包 APK：

```bash
flutter build apk --release
```

## 目录

```
lib/
  main.dart
  models/video_item.dart
  services/phub_api.dart      # 抓取与解析
  services/translator.dart
  screens/                   # 推荐 / 搜索 / 播放
  widgets/video_card.dart
```

## 说明

- 不依赖 Python / phub 后端
- 站点改版可能导致解析失败，需改 `phub_api.dart`
- 成人内容勿上架 Google Play，仅侧载自用

## 免责声明

- 本软件仅供学习、研究和技术交流目的使用。
- 使用者须自行遵守所在地法律法规，自行解决网络访问问题。
- 所有视频内容来自第三方网站，版权归原作者或相关权利人所有。
- 开发者不对软件的使用后果承担任何责任。
- 严禁将本软件用于任何商业用途或非法目的。
- 如您不同意以上条款，请立即停止使用并删除本软件。
