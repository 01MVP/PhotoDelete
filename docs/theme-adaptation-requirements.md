# PhotoDelete 主题颜色适配需求文档

状态：已实现第一版完整主题适配
日期：2026-06-18
范围：iOS App 内的主题色系统，不包含 App Store 素材、官网、截图模板。

## 实现记录

2026-06-18 已完成第一版完整主题适配：

- `PhotoDeleteTheme` 扩展为角色色 token，覆盖背景、surface、主色、辅助色、语义色、按钮、tab、toolbar、选择态、搜索/图标相关 token。
- `PhotoDeleteStyle.accent/surface/hairline/cardStroke/positive/warning/destructive` 等旧入口改为当前主题感知，现有页面的大量按钮、图标、进度条和选中态会自动跟随主题。
- 根 app、tab、共享按钮、icon tile、toast、授权卡、UIKit 双排浏览器颜色已接入主题。
- 设置页主题说明已更新为“色调会影响背景、图标、按钮和选中状态。”
- 删除、警告、成功、收藏仍保持语义方向，不被主题主色覆盖。

## 背景

当前已经新增 `PhotoDeleteTheme`，包含清透蓝、鼠尾草绿、暖砂色、石墨灰四套色调。现有实现主要覆盖了：

- 页面背景渐变
- 卡片背景、描边、分割线
- 主按钮背景和文字色
- 底部 Tab 选中色
- 设置页里的主题入口和主题选择器

但这还不是完整的主题适配。大量 UI 仍直接使用 `PhotoDeleteStyle.accent`、`positive`、`warning`、`destructive` 或硬编码系统色，导致切换主题后，图标、按钮、进度条、选择态、工具栏操作和部分卡片高亮仍然保留默认蓝色或固定语义色，整体观感不统一。

## 目标

主题切换后，用户应该明确感受到整套界面的主色调变化，而不是只有背景变色。主题色需要影响所有“品牌/操作主色”相关控件，同时保留删除、警告、成功等系统语义色的辨识度。

目标体验：

- 清透蓝：默认清爽、照片管理工具感较轻。
- 鼠尾草绿：柔和、偏自然，减少纯工具界面的冷感。
- 暖砂色：更温暖，适合长时间整理。
- 石墨灰：中性克制，突出照片内容和信息层级。

## 设计原则

1. 主题色只接管“品牌主色”和“中性操作色”，不强行改写危险、警告、成功等语义色。
2. 删除永远保持红色系，警告保持橙/黄系，成功/完成可以保持绿系，但可以按主题微调明度和背景透明度。
3. 所有新颜色必须通过共享 token 使用，不允许页面直接写 `.blue`、`UIColor.systemBlue` 或新的散落 RGB。
4. 主题要同时支持浅色、深色、跟随系统外观。
5. 主题切换应立即反映到当前可见页面，不需要重启 App。
6. 适配 iOS 26 Liquid Glass：优先让系统控件继承 `.tint(theme.primaryAccent)`，不要用大面积不透明自绘覆盖系统 bar。

## 主题 Token 需求

建议把 `PhotoDeleteThemePalette` 扩展为更完整的角色色，而不是继续只暴露 `readableAccent` 和 `warmAccent`。

### 基础层

- `backgroundTop`：页面背景顶部色。
- `backgroundBottom`：页面背景底部色。
- `surface`：普通卡片/列表容器背景。
- `elevatedSurface`：浮起卡片、按钮、菜单背景。
- `cardStroke`：卡片描边。
- `hairline`：分割线。
- `floatingShadow`：浮层阴影。

### 主色层

- `primaryAccent`：全局主色，替代当前多数 `PhotoDeleteStyle.accent`。
- `primaryAccentPressed`：主按钮按下态。
- `primaryAccentSoftFill`：图标底、选中 chip、轻量高亮背景。
- `primaryAccentSoftStroke`：轻量高亮描边。
- `primaryAccentOnFill`：主色实底上的文字/图标色。
- `secondaryAccent`：辅助强调色，用于渐变、次级图标、统计卡片。
- `secondaryAccentSoftFill`：辅助强调色浅底。

### 系统语义层

- `success`：保留/完成/已选等正向状态。
- `successSoftFill`
- `warning`
- `warningSoftFill`
- `danger`
- `dangerSoftFill`
- `favorite`：收藏心形，不一定跟随主题，可以保持粉/玫红辨识度。

语义色可以每套主题微调明度和饱和度，但不应变成主题主色，避免用户误判删除、警告、完成状态。

### 控件层

- `buttonPrimaryFill`
- `buttonPrimaryText`
- `buttonSecondaryFill`
- `buttonSecondaryText`
- `buttonSecondaryStroke`
- `toolbarAction`
- `tabSelected`
- `tabUnselected`
- `progressTint`
- `selectionTint`
- `searchFieldFill`
- `searchFieldStroke`
- `iconTileFill`
- `iconTileStroke`
- `navigationTint`

控件层可以映射到基础层和主色层，但页面应该优先使用控件 token，避免每个页面自己拼 opacity。

## 必须适配的 UI 范围

### 全局

- App `.tint`
- NavigationStack 里的 toolbar action，例如“完成”“恢复购买”等文字按钮
- TabBar 选中色、未选中色、iOS 26 之前的 tab appearance
- Toast 的 neutral 样式和撤销按钮
- ProgressView 默认 tint
- Search field 背景、边框、光标/取消按钮 tint
- Empty state 图标和主要操作按钮

### 共享组件

- `PhotoDeleteIconTile`
  - 增加默认主题 tint，调用方不传色时自动用当前主题主色。
  - soft/solid/plain 三种样式都要用主题 token。
- `PhotoDeletePrimaryButtonStyle`
  - 背景、按下态、禁用态、文字色跟随主题。
- `PhotoDeleteSecondaryButtonStyle`
  - 背景、描边、文字色跟随主题。
- `PhotoDeleteToastView`
  - neutral/favorite/positive/warning/destructive 分清楚主题色与语义色。
- 通用 section heading、link、inline action
  - 中性 action 使用主题主色。

### 整理页

- 开始整理主按钮
- 快速入口中“全部照片/截图”等中性图标
- 加载进度条
- 初次引导卡片里的主图标和确认按钮
- 按时间整理入口中的中性 icon 和 chevron 高亮

删除、收藏、保留手势仍使用语义色：删除红、保留绿、收藏粉/玫红。

### 相册页

- 右上角排序、创建相册按钮
- 搜索框背景、边框、光标、取消按钮
- 相册列表中默认文件夹占位图标
- 加载进度条
- 编辑/重命名 swipe action 可用主题主色，删除 swipe action 保持红色
- 整理进度百分比：普通/中性进度使用主题主色，完成或成功状态可使用 success

### 进阶页

- 锁定态 CTA、解锁按钮、恢复购买按钮
- 时间范围 segmented/chip 选中态
- 进度环、进度条、月份/年份选中状态
- 大文件清理、相似照片清理、截图、视频压缩等入口：
  - 默认中性入口用主题主色或辅助强调色
  - 大文件仍可用 warning
  - 视频压缩/完成类仍可用 success
- paywall 底部浮层按钮和辅助链接
- iCloud 信息卡、说明卡中的中性图标

### 设置页

- 使用统计四列中“整理次数/照片/删除/节省空间”需要区分：
  - 中性统计跟随主题
  - 删除保持 danger
  - 节省空间/完成可用 success
  - 提醒类用 warning
- 偏好设置里的手势、语言、触感反馈等中性 icon 跟随主题
- 主题与外观入口跟随当前主题
- 数据与权限、关于与支持里的中性 icon 跟随主题
- 当前主题选择器文案需更新：
  - 从“色调会影响背景、卡片和主要按钮。”
  - 改为“色调会影响背景、图标、按钮和选中状态。”

### Onboarding / 支持者页面

- Onboarding 页码、主 CTA、非语义图标跟随主题。
- SupporterView 的解锁 CTA、included 状态、权益图标、统计卡片中性项跟随主题。
- 付费能力表里的“包含/可用”可使用主题主色或 success；不可用保持 secondary/tertiary，不要用红色制造负面感。

## 不纳入主题适配的内容

- 真实照片、视频缩略图、相册封面。
- 删除确认、危险操作、系统权限弹窗中的系统红色。
- 成功、警告、错误状态的基本语义，不因为主题切换而变成同一色。
- App 图标本身，除非后续单独做多主题图标。
- App Store 截图和官网配色。

## 实施方案建议

### 阶段 1：补齐主题 token

- 扩展 `PhotoDeleteThemePalette`，新增主色层、语义层、控件层 token。
- 将 `readableAccent` 重命名或兼容映射为 `primaryAccent`。
- 保留现有四套主题，但补齐每套浅色/深色 token。
- 给 token 增加命名注释，避免后续误用。

### 阶段 2：改造共享组件

- `PhotoDeletePrimaryButtonStyle`、`PhotoDeleteSecondaryButtonStyle` 完整使用控件 token。
- `PhotoDeleteIconTile` 支持主题默认 tint。
- 增加主题化的 ProgressView helper，例如 `photoDeleteProgressTint()`.
- Toast、AuthorizationCard、通用 card/link/action 使用主题 token。

### 阶段 3：替换主页面中性 accent

按页面替换 `PhotoDeleteStyle.accent` 的中性使用点：

1. `HomeView`
2. `AlbumsView`
3. `AdvancedView`
4. `SettingsView`
5. `SupporterView`
6. `ContentView`
7. `BatchReviewViews`
8. `CleanupAchievementsView`

替换时不要机械全局替换，要区分：

- 中性/品牌 action：改成主题主色。
- 删除：保留 danger。
- 完成/保留/成功：保留 success。
- 警告/大文件：保留 warning。
- 收藏：保留 favorite。

### 阶段 4：清理旧色源

- 降低 `PhotoDeleteStyle.accent` 的直接使用频率，保留为默认蓝 fallback 或迁移期兼容。
- 新代码禁止直接使用 `.blue`、`UIColor.systemBlue`、散落 RGB 主色。
- `PhotoDeleteStyle.iconTint(for:)` 改为接收 theme 或迁移到主题 token resolver。

### 阶段 5：视觉验收

至少截图对比以下组合：

- 4 套主题 x 浅色
- 4 套主题 x 深色
- 主 tab：整理、相册、进阶、设置
- 关键详情：相册搜索展开、进阶锁定 paywall、主题选择页、照片整理页、批量确认页

每张截图检查：

- 主按钮、图标、进度、选中态是否跟随主题。
- 删除/警告/成功状态是否仍可一眼区分。
- 深色模式下文字和图标对比度是否足够。
- 主题切换后没有残留突兀蓝色。
- iOS 26 系统 bar 不被自绘背景破坏。

## 验收标准

1. 切换任意主题后，当前页面的背景、主按钮、默认图标、进度条、选中态、toolbar action、tab selected 都同步变化。
2. 主流程页面不再出现固定蓝色作为中性主色，除非当前主题就是清透蓝。
3. 删除、警告、成功、收藏等语义色不会被主题主色覆盖。
4. `rg "systemBlue|\\.blue|PhotoDeleteStyle\\.accent"` 后，剩余结果都能解释为兼容 fallback、清透蓝 palette 或明确的语义例外。
5. 浅色/深色模式下，主按钮文字、图标 tile、选中 chip、搜索框边框都有足够对比度。
6. 主题选择页文案准确描述影响范围。
7. 不新增内部说明到 UI 文案，不引入三方依赖。

## 风险与注意事项

- 如果所有语义色都跟随主题，会牺牲删除/警告的安全辨识度，不建议这样做。
- 如果所有页面直接读取 `@Environment(\.photoDeleteTheme)`，代码会变散；优先通过共享组件和 token resolver 收口。
- 大范围替换 `PhotoDeleteStyle.accent` 有误伤风险，需要按页面人工判断。
- iOS 26 Liquid Glass 下，过重的自绘 tab/search/toolbar 背景会破坏系统质感，适配要以系统 tint 和材质为主。

## 建议决策点

需要先确认三件事：

1. 语义色是否允许按主题轻微调明度，但保持红/绿/橙/粉的语义方向。
2. 石墨灰主题是否允许更低饱和度，还是也要有明显“主题主色”。
3. 是否把主题作为免费外观能力，还是未来部分主题进入支持者权益。
