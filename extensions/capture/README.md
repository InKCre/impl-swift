# Capture Swift 分发

`inkcre/capture` 的 first-party 原生分发，独立 Swift Package。`Capture` 拥有材料、图、SQLite 待办、事务编排与恢复；`CaptureMac` 提供 macOS 选区／剪贴板／截图和原生采集界面。各平台遵守共享 Capture 合同，图结构不由宿主 Core 定义。

待办在冻结材料和目标的同一 SQLite 事务内分配入队序号。同一信息库中，符合重试条件的待办按首次提交顺序处理；草稿创建时间、材料采集时间和后续重试都不会改变这个顺序。记录页仍按最近更新显示。序号只属于本机存储，不进入共享 Capture 合同。当前未发布格式为 SQLite `user_version=2`，遇到其他已标记版本会拒绝打开并保留原文件，不执行隐式迁移。

Host 提供 PeerCore 的数据库、标准图／Storage、持久目录、凭据和扩展生命周期。精确分发身份来自 `Sources/Capture/Resources/extension.json`；随签名应用交付并独立启停，不依赖另一个 Peer 执行收入。

在仓库根执行 `swift test`；本包可通过 `swift build --package-path extensions/capture` 单独构建。Cida 选区读取与采集协调改编的 Apache-2.0 许可见 Legal/Cida；BetterShot 应用内选区与冻结图组件的 BSD-3-Clause 许可、固定版本和修改说明见 Legal/BetterShot。冻结帧只在截图会话内存中存在，确认后裁剪原图 PNG；停用关闭选区并丢弃会话，不调用系统截图工具栏。原创代码见 LICENSE。
