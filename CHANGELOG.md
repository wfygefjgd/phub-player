# PHUB Player 发布说明

> 说明：仓库内原先**没有**按版本的发布记录；Git 目前仅见大提交 `v1.6.0`。  
> 下文根据桌面成品包时间线、体积变化与源码注释整理，**1.5.x 细项为推断**，便于对照安装包。

---

## [1.6.1] — 优化（源码，待打包）

### 通用
- **双入口**：默认启动 **播放器**；设置可切到 **隐私浏览器**（需重启生效，双向可切）。
- **启动擦除仅浏览器模式**：播放器不再 `wipeOnLaunch`，设置/画质等得以保留。
- **统一 Dio**：`AppHttpClient` + `AppHttpHeaders`，三源 API / 翻译共用工厂。
- **Feed 减负**：列表默认最多试 **5** 页、有限并发 3，首屏更快、少 403。
- **发布**：自用继续 **debug 签名** 即可，不强制正式证书（见文末说明）。

### Android / iOS
- 无单独平台破坏性变更；Impeller 关闭与安卓不全屏强横屏策略保持。

---

## 版本与产物一览（桌面 `C:\Users\96335\Desktop`）

| 版本 | Android APK | iOS IPA | 说明 |
|------|-------------|---------|------|
| 1.5.3 | 有（约 53.3 MB） | 无 | 仅安卓 |
| 1.5.4 | 有（体积与 1.5.3 相同） | 无 | 仅安卓 |
| 1.5.5 | 有（体积微变） | 有（约 7.5 MB） | 双端 |
| 1.5.6 | 有（体积再微变） | 有 | 双端 |
| 1.5.7 | 有（当前 1.5 线最新包） | 有 | 双端 |
| 1.6.0 | 源码已标 `1.6.0+15`，桌面未见同名成品包 | 同左 | 产品形态切换（见下） |

**结论（与「只改安卓」相关）：**

- **1.5.3～1.5.4**：只有 Android 包 → 明确是安卓侧迭代/试修。
- **1.5.5～1.5.7**：每次 Android 打完后约数分钟内会打 iOS IPA → 更像**同源码一起出包**，iOS **未必有独立功能变更**，多为**同步打包抬版本号**。
- 若当时目标是修 **Android 15 闪退**，iOS 连打多版**确实没有单独修 iOS 的必要**；保留 IPA 主要是侧载分发/版本号对齐。

---

## [1.6.0] — 源码当前（git `f5a12d3`）

**主题：** Extreme privacy browser（偏 iOS 侧载 / 强清理）

### 变更
- 入口改为隐私浏览器壳（`PrivacyBrowserApp` + `flutter_inappwebview`）。
- 启动执行 `PrivacyEngine.wipeOnLaunch()`：清 Cookie / Web 缓存 / SharedPreferences / 应用目录等。
- 增加 `privacy_browser/*`、原生通道 `privacy_browser/engine`（如 Android `nuclearWipe` / `exitApp`）。
- 增加 GitHub Actions：`.github/workflows/ios-ipa.yml`。
- `pubspec`：`version: 1.6.0+15`，描述改为 Privacy Browser。

### 说明
- 播放器相关源码（`phub_api`、feeds、search 等）仍在仓库中，但**默认启动路径已不是视频主页**。
- 桌面目录下**尚未看到** `PHUB-Player-v1.6.0-*.apk/ipa` 成品（以你本机文件为准）。

---

## [1.5.7] — 2026-07-23（成品包）

### Android
- 继续 1.5.x 修复线收尾打包（体积相对 1.5.6 略有变化）。
- **推断目标**：巩固 Android 15 相关稳定性（见下方「跨 1.5.x 的安卓修复点」）。

### iOS
- 同步打出 IPA（时间紧挨 Android 包）。
- **推断**：无独立 iOS 缺陷说明；主要为版本号对齐 + 侧载分发。

---

## [1.5.6] — 2026-07-23（成品包）

### Android
- 再次微调打包（体积略降）。
- **推断**：仍属 Android 15 / 播放器稳定性修补或配置微调。

### iOS
- 同步 IPA；**推断**同 1.5.7，无单独 iOS 功能 changelog。

---

## [1.5.5] — 2026-07-23（成品包）

### Android
- 体积相对 1.5.4 有极小差异（非空包拷贝）。
- **推断**：继续修安卓闪退/渲染相关问题后的有效构建。

### iOS
- **本线首次出现 IPA**（约 Android 之后 13 分钟）。
- **推断**：开始「安卓修完顺手打 iOS」，而非 iOS 专修。

---

## [1.5.4] — 2026-07-23（成品包）

### Android only
- 与 1.5.3 **文件大小完全一致**（可能是同构建重打、仅改元数据，或改动未影响包体）。
- **推断**：针对 Android 15 闪退的再尝试打包。

### iOS
- 无包。

---

## [1.5.3] — 2026-07-23（成品包）

### Android only
- 可见的 1.5.x 起点安装包。
- **推断**：进入「密集修 Android 15」阶段的第一枪。

### iOS
- 无包。

---

## 跨 1.5.x 的安卓修复点（源码中可核对）

以下写在代码注释/清单里，**高度吻合「修 Android 15 闪退」**：

1. **关闭 Impeller，改用 Skia**  
   - `AndroidManifest.xml`：`io.flutter.embedding.android.EnableImpeller = false`  
   - 注释：Impeller 会导致 Android 15 横屏模拟器 / 宿主进程挂掉。

2. **避免在 Android 上强制横屏**  
   - `player_chrome.dart`：全屏时仅 iOS 设置 `preferredOrientations`；Android 保持设备当前方向。  
   - 注释：Android 上强改方向可能 hard-crash Android 15 模拟器 / GPU host。

3. **网络 / 权限**  
   - 清稿流量、媒体权限等常规移动端配置（非 15 专有，但是播放器基线）。

这些修改对 **iOS 无对等闪退叙事**，因此 **iOS 多版本更像版本号 + 重打包**，而不是「iOS 也修了四五版同等问题」。

---

## 产品基线（1.5 播放器阶段，简述）

- 纯客户端抓取（无自建后端、无内置代理；依赖系统 VPN）。
- 推荐 / 搜索 / 详情 / HLS 播放（`media_kit` 或 `video_player` 等依版本）。
- 多源相关代码后续进入仓库（如 `phub_api` / `xvideos_api` / `mitao_api`）。
- 不做会员登录；站点改版可能导致解析失效。

---

## 维护约定（建议）

以后每打一个对外安装包，在本文件顶部追加一节，至少写：

```text
## [x.y.z] — YYYY-MM-DD
### Android
- 改了什么 / 修了什么
### iOS
- 有实质修改 → 写清
- 仅同步打包 → 写「同步重打包，无独立变更」
```

避免再出现「安卓连修多版、iOS 只抬版本号却无说明」的情况。

---

## 自用签名说明（正式证书可跳过）

**只自己用 / 小范围侧载：用 debug 签名完全够。**

当前 `android/app/build.gradle.kts` 里 release 仍指向 debug key，因此：

```bash
flutter build apk --release
```

打出来的包和日常 `flutter run` 是同一套签名，**卸载重装可覆盖**（同一台机器、同一 debug keystore）。

### 什么时候才需要「正式签名」
- 要给很多人分发、且希望 **换电脑打包仍能覆盖安装**
- 或以后要上架商店（本项目不建议上架）

### 若以后真要正式签名（可选，费事）
1. 本机生成一次 keystore（只做一次）：
   ```bash
   keytool -genkey -v -keystore phub-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias phub
   ```
2. 在 `android/` 下放 `key.properties`（**勿提交 git**）：
   ```
   storePassword=***
   keyPassword=***
   keyAlias=phub
   storeFile=../phub-release.jks
   ```
3. 在 `build.gradle.kts` 的 `release` 里改用该 signingConfig。

**结论：个人小范围分发 → 保持 debug 签名，不必折腾正式证书。**

---

## 免责声明

本软件仅供学习研究；使用者自行合规与网络访问；勿上架应用商店商用。详见 `README.md`。
