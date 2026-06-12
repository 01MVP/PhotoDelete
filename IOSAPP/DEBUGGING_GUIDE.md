# PhotoDelete 调试指南

## 概述

PhotoDelete 当前使用 Photos 框架访问真实照片库。模拟器可以导入测试照片，真机可以验证完整照片库、受限照片库和 iCloud 照片等真实场景。

## 调试环境选择

### 1. iOS 模拟器调试

**优点：**
- 快速部署和测试
- 支持断点调试
- 可以添加测试照片

**限制：**
- 照片库内容有限
- 某些硬件功能无法测试
- 性能与真机有差异

**模拟器照片库设置：**

#### 方法一：通过Safari添加照片
1. 在模拟器中打开 Safari
2. 搜索图片并长按保存到照片库
3. 重复添加多张不同类型的照片

#### 方法二：拖拽照片到模拟器
1. 从Mac的文件夹中选择照片
2. 直接拖拽到iOS模拟器的照片应用中
3. 照片会自动保存到模拟器的照片库

#### 方法三：使用Xcode添加照片
1. 在Xcode中选择 `Device and Simulator`
2. 选择对应的模拟器
3. 在 `Photos` 部分添加照片

**推荐测试照片类型：**
- 普通照片 (10-20张)
- 视频文件 (3-5个)
- 截图 (拍摄模拟器截图)
- 不同尺寸的图片

### 2. 真机调试

**优点：**
- 访问真实的照片库
- 真实的性能表现
- 完整的硬件功能

**要求：**
- iOS 16.0 或更高版本
- 签名证书配置正确
- 开发者账号

**真机调试步骤：**

#### 步骤1：配置Xcode项目
```bash
cd /Users/jackiexiao/code/01mvp/PhotoDeleteAPP/IOSAPP
open PhotoDelete.xcodeproj
```

#### 步骤2：设置签名
1. 在Xcode中选择项目根目录
2. 选择 `PhotoDelete` target
3. 在 `Signing & Capabilities` 中设置Team
4. 确保Bundle Identifier唯一

#### 步骤3：连接设备
1. 用USB连接iPhone到Mac
2. 在iPhone上信任此电脑
3. 在Xcode中选择连接的设备

#### 步骤4：运行应用
1. 点击Xcode的运行按钮
2. 应用会自动安装到iPhone上

## 权限配置

### 照片库访问权限

**Info.plist 配置：**
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>PhotoDelete需要访问您的照片库来帮助您整理和管理照片。我们不会上传或分享您的照片。</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>PhotoDelete需要权限来把照片加入您选择的相册。</string>
```

**权限请求流程：**
1. 应用首次启动时不会自动请求权限
2. 用户选择"我的照片库"时会请求权限
3. 用户授权"受限访问"时，应用只会整理已授权的照片，并可在设置中管理授权范围

**权限类型说明：**
- `Limited Access` - 只能访问用户选择的照片，适合最小权限测试
- `Full Access` - 可以访问完整的照片库（推荐）

## 功能测试

### 1. 基础功能测试

**真实照片模式：**
- [x] 权限请求流程
- [x] 照片库扫描和分类
- [x] 真实照片显示
- [x] 删除/收藏操作

### 2. 手势操作测试

| 手势 | 操作 | 预期结果 |
|------|------|----------|
| 左滑 | 删除照片 | 照片移到垃圾桶，统计更新 |
| 右滑 | 保留照片 | 照片标记为保留，进入下一张 |
| 上滑 | 添加收藏 | 照片加入收藏，统计更新 |
| 下滑 | 跳过照片 | 跳过当前照片，进入下一张 |

### 3. 性能测试

**大量照片处理：**
- 测试1000+张照片的加载速度
- 检查内存使用情况
- 验证滑动流畅性

**照片加载优化：**
- 缩略图快速加载
- 全尺寸图片按需加载
- 内存管理正确

## 常见问题解决

### 1. 编译错误

**问题：** Build失败
```bash
# 清理项目
cd IOSAPP
rm -rf DerivedData
xcodebuild clean -project PhotoDelete.xcodeproj -scheme PhotoDelete
```

**问题：** 签名错误
- 检查开发者账号配置
- 更新Provisioning Profile
- 确保Bundle ID唯一

### 2. 权限问题

**问题：** 无法访问照片库
- 在设置中检查应用权限
- 重新授权照片库访问
- 如果选择"受限访问"，确认已把测试照片加入授权范围

**问题：** 照片无法删除
- 检查是否有删除权限
- 验证PHAssetChangeRequest使用正确

### 3. 性能问题

**问题：** 应用卡顿
- 检查主线程是否被阻塞
- 优化图片加载策略
- 减少内存占用

**问题：** 照片加载慢
- 使用合适的缩略图尺寸
- 启用网络访问权限
- 检查PHImageRequestOptions配置

## 调试工具

### 1. Xcode调试器

**断点调试：**
```swift
// 在关键方法中设置断点
func deleteCurrentRealPhoto() {
    // 断点位置
    guard let currentPhoto = getCurrentRealPhoto() else { return }
    // ...
}
```

**控制台输出：**
```swift
print("当前照片数量: \(photoLibraryManager.totalPhotosCount)")
print("授权状态: \(photoLibraryManager.authorizationStatus)")
```

### 2. Instruments

**内存分析：**
- 使用Allocations工具检查内存泄漏
- 监控PHAsset对象的生命周期
- 检查图片缓存使用情况

**性能分析：**
- Time Profiler检查CPU使用
- Time Profiler 分析 Photos fetch、时间分组和图片缓存路径
- Network检查iCloud照片同步

### 3. 照片库工具

**Photos.framework调试：**
```swift
// 检查照片库变化
PHPhotoLibrary.shared().register(self)

func photoLibraryDidChange(_ changeInstance: PHChange) {
    print("照片库发生变化: \(changeInstance)")
}
```

## 推荐调试流程

### 开发阶段
1. **模拟器开发** - 导入测试照片后快速迭代 UI
2. **添加测试照片** - 在模拟器中添加各种类型的测试照片
3. **功能验证** - 测试所有手势和操作

### 测试阶段
1. **真机测试** - 在真实设备上测试完整功能
2. **权限测试** - 验证权限请求流程
3. **性能测试** - 测试大量照片的处理性能

### 发布前
1. **兼容性测试** - 在不同iOS版本上测试
2. **权限合规** - 确保权限描述准确
3. **用户体验** - 验证完整的用户流程

## 总结

- **模拟器**适合快速开发和UI调试
- **真机**必须用于完整功能测试和性能验证
- **模拟器测试照片**提供可重复的基础测试环境
- **真机真实照片**验证实际使用场景

建议开发时主要使用模拟器 + 测试照片，在关键节点使用真机 + 真实照片进行验证。
