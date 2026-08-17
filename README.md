<p align="center">
  <img src="https://oneapps.studio/one-apps/assets/onephoto-icon.png" width="96" alt="删图图标" />
</p>

<h1 align="center">删图 - OnePhoto</h1>

<p align="center">
  <strong>滑动筛选，删除前再统一确认。</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="AGPL-3.0" />
  <img src="https://img.shields.io/badge/iOS-16.0%2B-blue" alt="iOS 16.0+" />
  <img src="https://img.shields.io/badge/SwiftUI-✓-orange" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Privacy-本机处理-brightgreen" alt="本机处理" />
</p>

<p align="center">
  <a href="README.en.md">English</a>
  ·
  <a href="https://oneapps.studio/zh/apps/onephoto">产品页</a>
  ·
  <a href="https://apps.apple.com/cn/app/id6779493280">App Store</a>
</p>

<p align="center">
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/zh/hero-review-card.webp" width="280" alt="删图滑动整理界面" />
</p>

## 这是什么

删图（技术项目名 PhotoDelete）是一款本地优先的 iPhone 相册整理工具。你可以从全部照片、视频、截图、相册、时间或地点开始逐张判断去留。不想保留的内容会先进入待删除列表，检查完整批次后，才会通过系统相册真正执行。

核心整理免费，不需要账号，也没有广告追踪。照片不会离开手机。支持者版一次买断，解锁相似照片、大文件清理、本机压缩、长期统计和成就。

它是 [One Apps Studio](https://oneapps.studio) 里的一个小 App。完整介绍和截图在 [oneapps.studio/apps/onephoto](https://oneapps.studio/zh/apps/onephoto)。

## 界面

产品页上的真实界面：

<p align="center">
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/zh/review-card.jpg" width="220" alt="滑动或点按，快速做决定" />
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/zh/two-row-browser.jpg" width="220" alt="双排浏览" />
</p>
<p align="center">
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/zh/albums.jpg" width="220" alt="按相册整理" />
  <img src="https://oneapps.studio/one-apps/products/onephoto/v1.11/zh/privacy.jpg" width="220" alt="本机隐私保护" />
</p>

1. 滑动或点按，快速做决定
2. 双排浏览
3. 按相册整理
4. 本机隐私保护

## 为什么开源

Vibe coding 之后，同样的相册清理被重做了太多次。没有必要再从零造一轮。

你可以基于这份代码二次开发：改手势、改界面、改清理队列，做成自己的 App 也行。开源商用免费；闭源商用需要授权。

想系统学习怎么用 AI 把一个 App 做出来，可以看 [01MVP](https://01mvp.com)。

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

想申请闭源授权，请联系 [MakerJackie](https://x.com/makerjackie)。也可以直接扫下面的收款码：既是赞赏，也可以是 299 元闭源授权费。

<p align="center">
  <img src="site/assets/sponsor/wxpay.jpg" width="240" alt="微信支付" />
  <img src="site/assets/sponsor/alipay.jpg" width="240" alt="支付宝" />
</p>

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

## 关于作者

我是 [MakerJackie](https://makerjackie.com)。

- X / Twitter：[@makerjackie](https://x.com/makerjackie)
- AI 产品实战教程：[01MVP](https://01mvp.com)
- 世界的形状可视化：[shapeof.world](https://shapeof.world)
- App 工厂：[OneApps.Studio](https://oneapps.studio)
