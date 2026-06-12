# PhotoDelete 设计风格指南

## 概述
PhotoDeleteApp 采用黑白极简的苹果风格设计，注重简洁、优雅和功能性。本文档定义了应用的视觉设计规范，确保所有页面保持一致的用户体验。

## 配色方案

### 主色调
- **主背景色**: `#000000` (纯黑)
- **次级背景色**: `#111111` (深灰)
- **卡片背景色**: `#111111` 或 `#1a1a1a`
- **边框颜色**: `#333333`
- **分割线颜色**: `#374151` 或 `#4b5563`

### 文字颜色
- **主文字**: `#ffffff` (白色)
- **次级文字**: `#9ca3af` (浅灰)
- **辅助文字**: `#6b7280` (中灰)
- **禁用文字**: `#4b5563` (深灰)

### 功能色彩
- **蓝色** (`text-blue-400`): 总体数据、信息类
- **红色** (`text-red-400`): 删除、警告类
- **绿色** (`text-green-400`): 成功、节省类
- **紫色** (`text-purple-400`): 视频、媒体类
- **黄色** (`text-yellow-400`): 收藏、重要类
- **粉色** (`text-pink-400`): 喜爱、特殊类

## 布局规范

### 间距系统
- **页面边距**: `px-6` (24px)
- **组件间距**: `py-4` (16px) 或 `py-2` (8px)
- **元素内边距**: `p-3` (12px) 或 `p-4` (16px)
- **小间距**: `space-x-3` (12px) 或 `space-y-2` (8px)

### 圆角规范
- **卡片圆角**: `rounded-xl` (12px) 或 `rounded-2xl` (16px)
- **按钮圆角**: `rounded-lg` (8px)
- **小组件圆角**: `rounded-lg` (8px)
- **图标容器**: `rounded-lg` (8px)

## 组件规范

### 状态栏
```css
.status-bar {
    height: 44px;
    background: #000000;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 20px;
    color: #ffffff;
    font-size: 14px;
    font-weight: 600;
}
```

### 导航栏
- 背景: `bg-black`
- 边框: `border-b border-gray-800`
- 内边距: `px-6 py-4`
- 标题: `text-lg font-bold text-white`
- 副标题: `text-sm text-gray-400`

### 卡片组件
```css
.card {
    background: #111111;
    border: 1px solid #333333;
    border-radius: 12px;
    transition: all 0.2s ease;
}

.card:active {
    transform: scale(0.98);
}
```

### 按钮规范

#### 主要按钮
- 背景: `bg-red-500` 或对应功能色
- 文字: `text-white`
- 圆角: `rounded-lg`
- 内边距: `px-6 py-3`
- 激活效果: `transform: scale(0.98)`

#### 次要按钮
- 背景: `transparent`
- 边框: `border border-gray-600`
- 文字: `text-white`
- 激活效果: `transform: scale(0.98)`

#### 图标按钮
- 背景: 无或 `bg-gray-800`
- 悬停: `hover:text-gray-300`
- 内边距: `p-2`

### 底部导航栏
- 位置: `fixed bottom-0`
- 背景: `bg-black`
- 边框: `border-t border-gray-800`
- 内边距: `px-6 py-2 pb-4`
- 安全区域: 考虑不同设备的底部安全区域

## 交互规范

### 动画效果
- **过渡时间**: `transition: all 0.2s ease`
- **按压效果**: `transform: scale(0.98)` 或 `scale(0.95)`
- **悬停效果**: 颜色变化，避免过度动画

### 反馈机制
- 按钮按压有明显的缩放反馈
- 重要操作需要确认对话框
- 状态变化有适当的视觉反馈

## 字体规范

### 字体族
```css
font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
```

### 字体大小
- **大标题**: `text-lg` (18px) `font-bold`
- **中标题**: `text-base` (16px) `font-semibold`
- **小标题**: `text-sm` (14px) `font-medium`
- **正文**: `text-sm` (14px)
- **辅助文字**: `text-xs` (12px)
- **数据展示**: `text-xl` (20px) 或 `text-2xl` (24px) `font-bold`

## 图标规范

### 图标库
使用 Font Awesome 6.4.0

### 图标大小
- **导航图标**: `text-lg`
- **功能图标**: `text-base` 或 `text-lg`
- **小图标**: `text-sm`

### 图标颜色
- 默认: `text-gray-300`
- 激活: `text-white`
- 功能色: 根据功能使用对应颜色

## 响应式设计

### 移动端优先
- 设计以 iPhone 尺寸为基准
- 考虑不同屏幕尺寸的适配
- 确保触摸目标足够大 (最小 44px)

### 安全区域
- 顶部状态栏: 44px
- 底部安全区域: 根据设备调整
- 侧边安全边距: 24px

## 最佳实践

### 一致性原则
1. 所有页面使用相同的配色方案
2. 保持组件样式的一致性
3. 统一的交互反馈机制
4. 一致的间距和布局规范

### 可访问性
1. 确保足够的颜色对比度
2. 提供清晰的视觉层次
3. 合理的触摸目标大小
4. 清晰的状态反馈

### 性能考虑
1. 避免过度的动画效果
2. 优化图片和资源加载
3. 合理使用 CSS 过渡效果

## 示例代码

### 标准卡片组件
```html
<div class="bg-gray-900 rounded-xl p-4 border border-gray-800">
    <div class="flex items-center space-x-3">
        <div class="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center">
            <i class="fas fa-icon text-white text-sm"></i>
        </div>
        <div class="flex-1">
            <h4 class="font-semibold text-white text-sm">标题</h4>
            <p class="text-xs text-gray-400">描述文字</p>
        </div>
        <i class="fas fa-chevron-right text-gray-500"></i>
    </div>
</div>
```

### 统计数据展示
```html
<div class="text-center">
    <div class="text-xl font-bold text-blue-400 mb-1">1,234</div>
    <div class="text-xs text-gray-400">标签</div>
</div>
```

---

**注意**: 本设计指南应作为所有新页面和组件开发的参考标准，确保整个应用保持一致的视觉体验。