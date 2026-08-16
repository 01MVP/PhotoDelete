<p align="center">
  <img src="IOSAPP/PhotoDelete/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" width="120" alt="删图应用图标" />
</p>

<h1 align="center">删图 - OnePhoto</h1>

<p align="center">
  <strong>用滑动整理相册，先加入候选，确认后再真正删除。</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="AGPL-3.0" />
  <img src="https://img.shields.io/badge/iOS-16.0%2B-blue" alt="iOS 16.0+" />
  <img src="https://img.shields.io/badge/SwiftUI-✓-orange" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Privacy-On--Device-brightgreen" alt="本机处理" />
  <img src="https://img.shields.io/badge/Core-Free-green" alt="核心功能免费" />
</p>

<p align="center">
  <a href="README.md">English</a>
  ·
  <a href="https://oneapps.studio/apps/onephoto">OneApps.Studio</a>
  ·
  <a href="https://apps.apple.com/app/id6779493280">App Store</a>
</p>

<p align="center">
  <img src="site/assets/photodelete-home.jpg" width="320" alt="删图首页" />
</p>

## 这是什么

删图（技术项目名：PhotoDelete）是一款本地优先的 iPhone 相册整理工具。你可以从全部照片、视频、截图、相册、时间或地点开始逐张判断去留。不想保留的内容会先进入待删除列表，检查完整批次后，才会通过系统相册真正执行。

核心整理免费，不需要账号，也没有广告追踪。照片不会离开手机。支持者版通过 StoreKit 一次性买断，解锁相似照片、大文件清理、本机压缩、长期统计和成就。

它是 [One Apps Studio](https://oneapps.studio) 里的一个小 App。那是 MakerJackie 的 App 工厂，里面大部分产品都把基础功能做成免费。

## 为什么开源

Vibe coding 之后，同样的相册清理被重做了太多次。没有必要再从零造一轮。

你可以基于这份代码二次开发：改手势、改界面、改清理队列，做成自己的 App 也行。只要按 AGPL-3.0 继续开源，就可以商用。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| 滑动删图 | 默认左滑删除、右滑保留、上滑收藏、下滑跳过；手势可自定义，支持撤销 |
| 候选确认 | 删除和收藏先暂存，复核后再统一提交 |
| 浏览模式 | 单张卡片，或双行浏览 |
| 整理入口 | 全部照片、视频、截图、实况照片、收藏、相册、时间、地点 |
| 相似照片 | 找出连拍和几乎重复的那几张 |
| 大文件清理 | 先处理最占空间的照片和视频 |
| 本机压缩 | 在手机上压缩图片和视频 |
| 隐私 | 不需要账号，不上传照片，整理决策留在本机 |

## 快速开始

要求：

- Xcode 16.4+
- iOS 16.0+
- 模拟器适合做界面；Photos、iCloud 照片、有限照片库、真实删除/收藏建议用真机验证

```bash
cd IOSAPP
open PhotoDelete.xcodeproj
```

选择模拟器或真机后按 Cmd+R。

命令行构建：

```bash
SIMULATOR_DESTINATION="$(scripts/resolve-ios-simulator-destination.sh)"
xcodebuild -project IOSAPP/PhotoDelete.xcodeproj -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData \
  clean build
```

运行测试：

```bash
SIMULATOR_DESTINATION="$(scripts/resolve-ios-simulator-destination.sh)"
xcodebuild test \
  -project IOSAPP/PhotoDelete.xcodeproj \
  -scheme PhotoDelete \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath IOSAPP/DerivedData
```

## 项目结构

| 路径 | 用途 |
| --- | --- |
| `IOSAPP/PhotoDelete.xcodeproj` | Xcode 项目 |
| `IOSAPP/PhotoDelete/` | SwiftUI 源码 |
| `IOSAPP/PhotoDeleteTests/` | 单元测试 |
| `IOSAPP/PhotoDeleteUITests/` | UI smoke tests |
| `IOSAPP/Config/PhotoDelete-Info.plist` | 权限和 Bundle 配置 |
| `site/` | 官网和隐私政策 |
| `scripts/` | 模拟器解析和 TestFlight 发布脚本 |

## 许可证

默认协议是 [GNU Affero General Public License v3.0](LICENSE)。

- **开源商用：免费。** 基于这份代码做产品、收费都可以，只要你的代码同样按 AGPL-3.0 开源。
- **闭源商用：¥299。** 如果要商用且闭源，需要获得作者授权，授权费 299 元，一次买断。

想申请闭源授权，请联系 MakerJackie。

Copyright (c) 2025-2026 MakerJackie / 01MVP.

## 更多 App

都可以在 [OneApps.Studio](https://oneapps.studio) 下载：

- **OneZen**：简洁好用的冥想 App
- **OneScan**：纸质文件扫描成 PDF
- **OneVoice**：AI 语音记录与转写
- **OneStarter**：快速启动 SwiftUI App
- **OneFocus**：Mac 与 iPhone 联动专注
- **OneTune**：乐器调音器
- **OneMusic**：免费离线音乐播放器
