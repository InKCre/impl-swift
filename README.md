# D3LibMin - Library Notes App

一款基于SwiftUI开发的极简笔记收集应用，采用Dieter Rams风格设计，灵感来自Nothing和Teenage Engineering品牌的设计理念。

## 功能特性

### 主要页面
- **Library页面**: 垂直卡片列表，显示重要信息的标题和简短描述
- **Profile页面**: 用户头像、内存使用情况、连接设备状态

### 核心功能
- **信息分类**: 支持四种类型的信息筛选
  - Numbers (数字)
  - Profiles (联系人)
  - Files (文件)
  - Phrases (短语)

- **详情管理**: 点击卡片进入详情页面
  - 查看Essential Information
  - 编辑和重新排列内容
  - 删除不需要的信息

- **快速添加**: 主页底部的"+"按钮
  - 点击后弹出三个选项：文本、图片、文件
  - 带有优雅的动画效果和背景遮罩

### 设备连接
- **AR设备支持**: 连接Rokid AR Pro眼镜
- **实时状态显示**: 显示设备连接状态和最后连接时间

### 设计特色
- **Bento风格**: 简洁的卡片式布局
- **Dieter Rams美学**: 极简主义设计原则
- **现代化界面**: 清晰的视觉层次和优雅的交互
- **流畅动画**: 自然的过渡效果和微交互

## 技术栈
- SwiftUI
- iOS 18.5+
- Xcode 16

## 项目结构
```
D3LibMin/
├── Models.swift          # 数据模型
├── ContentView.swift     # 主视图容器
├── HomeView.swift        # 主页视图
├── UserProfileView.swift # 用户资料页面
├── InfoDetailView.swift  # 信息详情页面
└── D3LibMinApp.swift    # 应用入口
```

## 运行项目
1. 使用Xcode打开 `D3LibMin.xcodeproj`
2. 选择iOS模拟器或真机
3. 点击运行按钮或使用 `Cmd+R`

## 示例数据
应用包含以下示例数据：
- "605-1-3064" - Package pick up
- "Moonlight" - Piano scores  
- "John Smith" - Business contact
- "Project Alpha" - Design files
- "Meeting Notes" - Weekly team sync

## 设计参考
项目设计参考了paraflow文件夹中的原型设计，实现了：
- 简洁的筛选按钮
- 卡片式信息展示
- 用户资料页面布局
- 信息详情管理界面