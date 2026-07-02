# One 系列产品品牌规范

状态：第一版
日期：2026-06-26
范围：适用于 MakerJackie 后续所有 `One*` 系列产品，包括 App Store 名称、设备显示名、官网、截图、内购展示名和中文传播口径。

## 核心结论

所有产品统一进入 `One*` 系列品牌体系。

默认规则：

- 设备桌面显示名通常只使用英文品牌名，例如 `OneSay`、`OneWish`、`OneZen`；若产品为了搜索采用拆词命名，以当前落地标准为准。
- App Store 主名称使用“品牌名 + 本地化功能词”。
- 中文别名只作为解释、搜索和传播辅助，不再作为主品牌。
- 官网、截图、Logo、导航、多产品合集页统一使用 `One*` 主品牌。
- 旧中文名可以在过渡期保留为解释词，但不能形成第二套正式品牌。

## 品牌架构

`One` 是系列母品牌，后面的英文词是单品品牌。

命名结构：

```text
One + ProductWord
```

示例：

```text
OneSay
OneWish
OneZen
```

命名目标：

- 一眼看出属于同一产品系列。
- 在手机桌面、官网导航、截图角标中保持统一。
- 在海外市场不依赖中文名也能传播。
- 在中文市场用本地化功能词补足理解和搜索，不牺牲系列感。

## 名称层级

每个产品必须同时定义四个名称层级。

| 层级 | 用途 | 规则 | 示例 |
| --- | --- | --- | --- |
| Series Name | 系列母品牌 | 固定为 `One` | `One` |
| Product Brand | 单品主品牌 | `One` + 一个英文词，或按产品检索需要拆词 | `OnePhoto` |
| App Store Name | 商店搜索和转化 | 品牌 + 本地化功能词；若精准品牌名被占用，记录实际可用名 | `OnePhoto` / `删图` |
| Chinese Alias | 中文解释别名 | 只解释，不做主品牌 | `删图`、`一言`、`一愿` |

## 设备显示名

设备显示名指安装到 iPhone、iPad、Mac 或桌面后，图标下方显示的名字。

统一规则：

- 中文系统显示英文主品牌。
- 英文系统显示英文主品牌。
- 不使用中文别名作为图标名。
- 不使用“品牌 + 功能词”的长名作为图标名。

正确示例：

```text
OneSay
OneWish
OneZen
```

不推荐：

```text
删图
一言
删图
Photo Cleaner
```

原因：

- 设备桌面是品牌识别场，不是搜索场。
- 系列产品放在同一屏时，`One*` 命名能形成资产。
- 中文别名会让系列断裂，海外截图和中文截图也会出现两套品牌。

## App Store 名称

App Store 名称承担两个任务：品牌识别和搜索转化。

命名格式：

```text
英文区：OneProduct: Core Keyword，或记录已验证可用的检索名
中文区：OneProduct 中文功能词，或记录已验证可用的本地化名
```

规则：

- 英文区优先保留品牌，必要时后接高意图英文关键词。
- 中文区优先保留品牌，后接短中文功能词。
- 不堆叠多个关键词。
- 不把中文别名放在品牌前面。
- 不使用纯功能名作为 App Store 名称。
- 名称要控制在 App Store 当前限制内，发布前必须重新检查字符数。

OnePhoto 当前标准：

```text
英文 App Store：OnePhoto
中文 App Store：删图
英文设备显示名：OnePhoto
中文设备显示名：删图
```

不推荐：

```text
删图 - 旧品牌相册清理
删图 照片清理
旧品牌: Swipe Cleaner
Photo Cleaner
```

## Subtitle 和关键词

Subtitle 不重复主标题里的品牌词，优先解释动作和差异。

OnePhoto 示例：

```text
英文 Subtitle：Swipe, review, then delete
中文 Subtitle：滑动整理，确认后删除
```

关键词规则：

- App Store name 放最高价值搜索词。
- Subtitle 放补充动作或利益点。
- Keywords 字段放剩余同义词，不重复堆主标题。
- 不写竞品名。
- 不写无法证明的词，例如“最强”“全网第一”“AI 自动清理”，除非产品真实实现且可被审核材料证明。

## 中文别名规则

中文别名可以存在，但只在需要解释时使用。

适合使用中文别名的场景：

- 第一次介绍产品时：

```text
删图，一款用滑动方式删图和整理相册的工具。
```

- 中文 App Store 名称中的功能词：

```text
删图
```

- 中文文章标题或小红书/公众号说明：

```text
我做了 删图：一个删除前可确认的删图工具
```

- SEO/ASO 关键词：

```text
删图、照片清理、相册整理、截图清理
```

不适合使用中文别名的场景：

- App 图标下方。
- Logo 主视觉。
- 官网导航品牌位。
- 产品截图左上角品牌角标。
- 多产品合集页。
- 海外宣传。
- 内购产品主品牌。

## 中文旧名处理

已有中文名的产品不要立刻全部抹掉，但要降级为解释性别名。

建议迁移方式：

| 产品 | 旧中文名 | 主品牌 | 以后怎么写 |
| --- | --- | --- | --- |
| OneSay | 一言 | OneSay | `OneSay，一款语音/记录工具` |
| OneWish | 一愿 | OneWish | `OneWish，帮你生成和保存愿望画面` |
| OneZen | 可保留中文解释词 | OneZen | `OneZen，冥想、呼吸与专注练习` |
| OnePhoto | 删图 | OnePhoto | `删图` 用于中文 App Store 和中文区品牌位 |

迁移原则：

- 不制造“两个正式名字”。
- 不在同一页面频繁并列中英文名。
- 老用户熟悉的中文词可以出现在介绍句里，但品牌位必须回到 `One*`。
- 新产品从第一天就只建立一个主品牌。

## 官网与落地页

官网首屏必须让用户同时理解品牌和用途。

推荐结构：

```text
H1：OnePhoto
副文案：Swipe through your camera roll, review before deleting, and keep cleanup on device.
```

中文页推荐：

```text
H1：删图
副文案：用滑动方式整理照片，删除前统一确认。
```

导航品牌位：

```text
OnePhoto
```

Footer：

```text
© 2026 OnePhoto
```

不推荐：

```text
删图 - 相册清理助手 | 旧品牌
旧品牌: Swipe Cleaner
```

## 截图与营销素材

截图和营销素材的品牌位统一使用当前产品展示名。

规则：

- 英文素材使用 `OnePhoto`。
- 中文素材使用 `删图`。
- 中文卖点可以写中文，但品牌不翻译。
- 不在同一张图里同时出现 `OnePhoto`、`删图`、旧品牌三套名字。
- 若需要中文解释，用一句功能说明承接。

正确示例：

```text
OnePhoto
滑动整理照片，确认后再删除
```

不推荐：

```text
删图
Photo Delete
旧品牌
```

三者同时出现会稀释品牌。

## 内购与付费命名

内购展示名跟随主品牌。

格式：

```text
OneProduct Supporter
OneProduct Pro
OneProduct Plus
```

OnePhoto 当前标准：

```text
英文：OnePhoto Supporter
中文：删图支持者版
```

规则：

- 不把基础功能描述成订阅专属。
- 如果是一次性买断，不写 subscription、weekly、yearly 等误导词。
- 内购 Product ID 可以保留历史技术 ID，不为品牌改名随意更换。
- App Store Connect 的内购展示名要和本地 StoreKit 配置一致。

## 代码与配置要求

每次改名必须检查以下位置：

- `CFBundleDisplayName`：设备图标显示名。
- `CFBundleName`：包内显示名，通常跟主品牌一致。
- `InfoPlist.strings` 或 `.xcstrings`：多语言设备显示名和权限弹窗。
- App 内 `AppConstants.appDisplayName` 或等价常量。
- `Localizable.xcstrings`：设置页、反馈邮件、关于页、权限说明、支持者页。
- StoreKit 本地配置和 App Store Connect 内购展示名。
- App Store metadata 文档。
- 官网首页、隐私政策页、Open Graph title/description。
- App Store 截图、视频、社媒封面、邮件反馈 subject。
- UI tests 中依赖品牌文案的断言。

不建议改的内容：

- Bundle ID。
- 已上线内购 Product ID。
- 历史数据目录名。
- target、scheme、module 名。
- 已存在的 UserDefaults key。

除非有充分迁移计划，否则这些技术标识保持稳定。

## 新产品命名流程

新产品立项时按这个顺序定名：

1. 先确定 `OneProduct` 主品牌。
2. 检查 App Store 是否存在同名或强近似名。
3. 检查英文是否好读、好拼、没有负面含义。
4. 确定英文 App Store 名称。
5. 确定中文 App Store 名称。
6. 只在必要时定义中文解释别名。
7. 确定设备显示名，默认就是 `OneProduct`。
8. 更新官网、截图、内购、权限弹窗和反馈邮件。
9. 发布前用真机或构建产物确认图标名和权限弹窗。

## 命名评估标准

一个名字必须同时通过以下检查：

- 系列感：是否明显属于 `One*` 系列。
- 可读性：英语用户能否直接读出来。
- 可搜索：App Store 名称是否包含核心功能词。
- 可解释：中文用户是否能在第一屏知道用途。
- 可扩展：以后做官网、图标、视频封面是否好用。
- 不撞车：App Store 和搜索引擎里没有明显强冲突。
- 不误导：名字不暗示产品没有实现的 AI、云同步、自动删除等能力。

## 语言风格

One 系列的语气应该是克制、直接、可信。

推荐：

- 说清楚用户能完成什么。
- 强调隐私、确认、可控、低负担。
- 用短句，避免夸张营销词。
- 中文文案保留生活感，但品牌位统一英文。

避免：

- “全球第一”“最强”“神器”等无法证明的词。
- “AI 自动帮你决定”这类与产品实际不一致的表达。
- 过度堆关键词。
- 中英文品牌混排过多。
- 同一页面出现多个主品牌。

## OnePhoto 当前落地规范

OnePhoto 是本规范的第一批落地产品。

当前标准：

```text
英文设备显示名：OnePhoto
中文设备显示名：删图
英文 App Store：OnePhoto
中文 App Store：删图
英文内购：OnePhoto Supporter
中文内购：删图支持者版
```

中文介绍口径：

```text
删图是一款用滑动方式整理照片的 iPhone 工具。删除不会立刻执行，所有待删照片都会先进入确认页。
```

英文介绍口径：

```text
OnePhoto helps you clean up your iPhone photo library with a safe swipe workflow. Swipe to queue decisions, then review before anything changes.
```

## 发布前检查清单

每次品牌命名或改名发布前，必须确认：

- 设备图标名在中文系统和英文系统都显示 `OneProduct`。
- App Store Connect 各语言 App name 已按本地化规则填写。
- Subtitle 没有重复堆品牌词。
- App 内设置页、关于页、反馈邮件、权限说明没有旧主品牌。
- 内购展示名已经同步。
- 官网首页、隐私政策、Open Graph 元数据已经同步。
- 截图和视频素材没有旧品牌。
- 构建产物里的 Info.plist 和本地化 InfoPlist 字符串正确。
- 自动化测试里旧品牌断言已更新。
- 没有为了改品牌破坏 Bundle ID、Product ID 或本地数据 key。

## 决策记录

2026-06-26 决定：

- One 系列以后统一英文主品牌。
- 中文别名保留解释价值，但不再作为设备显示名和主品牌。
- OnePhoto 原计划使用 `OnePhoto` 作为英文 App Store 名称，但该名称已被 App Store Connect 占用，实际英文 App Store 名称改为 `OnePhoto`。
- OnePhoto 使用 `删图` 作为中文 App Store 名称。
- OnePhoto 安装到英文用户手机上显示 `OnePhoto`，安装到中文用户手机上显示 `删图`。
