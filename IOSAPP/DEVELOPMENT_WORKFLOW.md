# iOS 开发工作流程指南

本文档为新手开发者提供 PhotoDelete 项目的基础开发流程说明。

## 开发环境设置

### 必需工具
- **Xcode**: 最新版本（推荐 15.0+）
- **iOS 模拟器**: iPhone 15/16 系列
- **Git**: 版本控制

### 项目结构
```
PhotoDeleteAPP/
├── IOSAPP/                 # iOS 应用主目录
│   ├── PhotoDelete/          # 源代码目录
│   │   ├── *.swift        # Swift 源文件
│   │   └── Assets.xcassets/ # 资源文件
│   └── PhotoDelete.xcodeproj # Xcode 项目文件
└── Prototype/             # HTML 原型
```

## 日常开发流程

### 1. 代码修改后的标准操作
```bash
# 修改代码后的步骤：
1. 保存文件 (Cmd+S)
2. 构建项目 (Cmd+B) - 检查编译错误
3. 运行应用 (Cmd+R) - 构建并在模拟器中运行
```

### 2. 常用 Xcode 快捷键
- **Cmd+B**: 仅构建，检查编译错误
- **Cmd+R**: 构建并运行应用
- **Cmd+.**: 停止当前运行的应用
- **Cmd+Shift+K**: 清理构建缓存
- **Cmd+Shift+O**: 快速打开文件
- **Cmd+/**: 注释/取消注释代码

### 3. 模拟器使用

#### 正常开发流程
- **无需重启模拟器**: 代码修改后直接 Cmd+R 即可
- **自动更新**: Xcode 会自动重新安装应用到模拟器

#### 何时需要重启模拟器
- 模拟器卡死或响应缓慢
- 内存不足导致性能问题
- 系统级别设置更改（权限、语言等）
- 模拟器出现异常行为

### 4. 问题排查顺序

当遇到问题时，按以下顺序排查：

1. **检查编译错误** (Cmd+B)
   - 查看 Xcode 左侧导航栏的红色错误标记
   - 修复语法错误和类型错误

2. **清理构建缓存** (Cmd+Shift+K)
   - 清理旧的构建文件
   - 重新构建项目

3. **重新运行应用** (Cmd+R)
   - 强制重新安装应用

4. **重启 Xcode**
   - 关闭 Xcode 并重新打开项目

5. **重启模拟器**（最后选择）
   - Device → Erase All Content and Settings
   - 或者关闭模拟器重新启动

## SwiftUI 开发技巧

### 1. 实时预览
- 使用 **Canvas 预览**: 右侧面板的预览功能
- 无需运行模拟器即可查看 UI 变化
- 点击 "Resume" 按钮启用实时预览

### 2. 调试技巧
- **断点调试**: 点击行号设置断点
- **打印调试**: 使用 `print()` 输出调试信息
- **视图检查器**: 模拟器中点击 Debug → View Debugging

## Git 工作流程

### 1. 基本命令
```bash
# 查看状态
git status

# 添加文件
git add .

# 提交更改
git commit -m "描述你的更改"

# 推送到远程
git push
```

### 2. 分支管理
```bash
# 创建新分支
git checkout -b feature/new-feature

# 切换分支
git checkout main

# 合并分支
git merge feature/new-feature
```

## 常见问题解决

### 1. 编译错误
- **语法错误**: 检查拼写、括号匹配
- **类型错误**: 确保变量类型正确
- **导入错误**: 检查 `import` 语句

### 2. 运行时错误
- **崩溃**: 查看 Xcode 控制台的错误信息
- **权限问题**: 检查 Info.plist 中的权限声明
- **资源找不到**: 确保文件已添加到项目中

### 3. 模拟器问题
- **应用不更新**: 尝试 Clean Build (Cmd+Shift+K)
- **模拟器卡顿**: 重启模拟器或选择不同设备
- **权限重置**: Device → Erase All Content and Settings

## 代码规范

### 1. 命名规范
- **变量**: camelCase (例: `userName`)
- **函数**: camelCase (例: `handleButtonTap`)
- **类型**: PascalCase (例: `UserProfile`)
- **常量**: UPPER_CASE (例: `MAX_COUNT`)

### 2. 代码组织
- 每个文件只包含一个主要类型
- 使用 `// MARK: -` 分组相关代码
- 保持函数简短，单一职责

### 3. 注释规范
```swift
// MARK: - Properties
private var userName: String = ""

// MARK: - Lifecycle
override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
}

// MARK: - Private Methods
private func setupUI() {
    // 设置用户界面
}
```

## 性能优化建议

### 1. 构建优化
- 避免频繁的 Clean Build
- 使用增量编译
- 关闭不必要的 Xcode 功能

### 2. 调试优化
- 优先使用 SwiftUI 预览
- 减少不必要的 print 语句
- 使用条件断点

### 3. 模拟器优化
- 选择合适的模拟器设备
- 定期清理模拟器数据
- 关闭不使用的模拟器

## 学习资源

### 官方文档
- [Swift 官方文档](https://docs.swift.org/swift-book/)
- [SwiftUI 教程](https://developer.apple.com/tutorials/swiftui)
- [Xcode 用户指南](https://developer.apple.com/documentation/xcode)

### 推荐教程
- Apple 官方 SwiftUI 教程
- Stanford CS193p 课程
- Ray Wenderlich iOS 教程

---

**记住**: 开发是一个迭代过程，遇到问题时保持耐心，善用搜索引擎和官方文档。每次修改代码后，只需要 **Cmd+R** 即可看到更改，无需重启模拟器！