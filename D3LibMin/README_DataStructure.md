# D3LibMin 数据结构设计文档

## 概述

D3LibMin 是一个个人信息聚合软件，采用"信息块"的概念来组织和管理各种类型的信息。每个信息块都是一个独立的数据单元，包含了完整的信息内容和使用场景。

## 核心数据结构

### 1. InfoBlock (信息块)

信息块是系统的核心数据结构，每个主页卡片对应一个信息块。

#### 属性说明

- **id**: UUID - 唯一标识符
- **title**: String - 主标题
- **subtitle**: String - 副标题  
- **type**: InfoType - 内容类别
- **createdAt**: Date - 生成时间
- **expiresAt**: Date? - 过期时间（可选）
- **needs**: [UsageNeed] - 使用场景组
- **infos**: [InfoContent] - 所有内容组

### 2. InfoContent (信息内容)

表示信息块中的具体内容项，采用"名称:内容"的格式。

#### 属性说明

- **id**: UUID - 唯一标识符
- **name**: String - 内容名称
- **content**: String - 具体内容
- **type**: ContentType - 内容类型（文本/文件）

### 3. UsageNeed (使用场景)

描述信息块的使用场景和目的。

#### 属性说明

- **id**: UUID - 唯一标识符
- **name**: String - 场景名称
- **description**: String? - 场景描述（可选）

### 4. InfoType (内容类别)

枚举定义了信息块的内容类别：

- **Numbers**: 号码类信息（房间号、取件码等）
- **Profiles**: 身份类信息（联系人、个人信息等）
- **Files**: 文件类信息（文档、图片等）
- **Phrases**: 碎片类信息（笔记、备忘录等）
- **Others**: 其他类型信息

### 5. ContentType (内容类型)

枚举定义了内容项的类型：

- **text**: 文本内容
- **file**: 文件内容（链接形式）

## 数据管理

### DataManager 类

`DataManager` 是数据管理的核心类，提供了完整的 CRUD 操作：

#### 主要方法

- `addInfoBlock(_:)` - 添加信息块
- `updateInfoBlock(_:)` - 更新信息块
- `deleteInfoBlock(_:)` - 删除信息块
- `getInfoBlock(by:)` - 根据ID获取信息块
- `getInfoBlocks(by:)` - 根据类型获取信息块
- `searchInfoBlocks(query:)` - 搜索信息块
- `getExpiredInfoBlocks()` - 获取过期信息块
- `getExpiringSoonInfoBlocks(within:)` - 获取即将过期的信息块

#### API 集成准备

DataManager 已经为未来的 API 集成做好了准备：

- 所有 CRUD 操作都有对应的 API 调用占位符
- 支持异步数据加载和错误处理
- 提供了数据刷新机制

## 用户界面更新

### InfoDetailView 改进

1. **双输入框设计**: 将单一的输入框改为并排的两个输入框
   - 第一个输入框：内容名称
   - 第二个输入框：具体内容

2. **智能光标跳转**:
   - 在名称输入框按回车时，光标跳转到内容输入框
   - 在内容输入框按回车时，保存当前条目并跳转到下一个名称输入框

3. **数据验证**: 只有当名称和内容都不为空时才能添加条目

## 向后兼容性

为了确保平滑过渡，系统提供了向后兼容机制：

### InfoItem 兼容层

- 保留了原有的 `InfoItem` 结构
- 提供了 `InfoItem(from:)` 构造器，从 `InfoBlock` 创建 `InfoItem`
- 提供了 `toInfoBlock()` 方法，将 `InfoItem` 转换为 `InfoBlock`

### 数据转换

```swift
// 从 InfoBlock 创建 InfoItem
let infoItem = InfoItem(from: infoBlock)

// 从 InfoItem 转换为 InfoBlock
let infoBlock = infoItem.toInfoBlock()
```

## 示例数据结构

### 酒店房间信息块

```swift
InfoBlock(
    title: "Room 6836",
    subtitle: "Meikai Hotel",
    type: .numbers,
    needs: [
        UsageNeed(name: "Hotel Check-in", description: "For hotel registration"),
        UsageNeed(name: "Room Access", description: "For room key card")
    ],
    infos: [
        InfoContent(name: "Room Number", content: "6836"),
        InfoContent(name: "Hotel Name", content: "Meikai Hotel"),
        InfoContent(name: "Check-in Date", content: "2025-01-15"),
        InfoContent(name: "Check-out Date", content: "2025-01-18")
    ]
)
```

### 联系人信息块

```swift
InfoBlock(
    title: "Lanzhi Jiang",
    subtitle: "New contact",
    type: .profiles,
    needs: [
        UsageNeed(name: "Contact Management", description: "For contact information"),
        UsageNeed(name: "Communication", description: "For messaging and calls")
    ],
    infos: [
        InfoContent(name: "Full Name", content: "Lanzhi Jiang"),
        InfoContent(name: "Phone", content: "+86 138-1234-5678"),
        InfoContent(name: "Email", content: "lanzhi.jiang@example.com"),
        InfoContent(name: "Company", content: "Tech Solutions Inc."),
        InfoContent(name: "Position", content: "Senior Developer")
    ]
)
```

## 未来扩展

### API 集成

1. **RESTful API**: 设计标准的 REST API 接口
2. **数据同步**: 实现多设备数据同步
3. **离线支持**: 支持离线数据存储和同步

### 高级功能

1. **智能分类**: 基于内容自动分类
2. **过期提醒**: 自动提醒即将过期的信息
3. **搜索优化**: 全文搜索和智能推荐
4. **数据导出**: 支持多种格式的数据导出

## 技术实现

### 架构模式

- **MVVM**: 使用 SwiftUI 的 MVVM 架构
- **ObservableObject**: 数据管理器实现 ObservableObject 协议
- **Combine**: 使用 Combine 框架进行数据绑定

### 数据持久化

- **UserDefaults**: 本地数据存储
- **Core Data**: 复杂数据关系管理（未来）
- **CloudKit**: 云端数据同步（未来）

### 性能优化

- **懒加载**: 使用 LazyVStack 优化列表性能
- **内存管理**: 合理使用 @StateObject 和 @ObservedObject
- **异步处理**: 使用 DispatchQueue 处理耗时操作 