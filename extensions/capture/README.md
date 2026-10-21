# Capture Swift 分发

`inkcre/capture` 的 first-party 原生分发，独立 Swift Package。`Capture` 拥有材料、图、SQLite 待办、事务编排与恢复；`CaptureMac` 提供 macOS 选区／剪贴板／截图和原生采集界面。各平台遵守共享 Capture 合同，图结构不由宿主 Core 定义。

Host 提供 PeerCore 的数据库、标准图／Storage、持久目录、凭据和扩展生命周期。精确分发身份来自 `Sources/Capture/Resources/extension.json`；随签名应用交付并独立启停，不依赖另一个 Peer 执行收入。

在仓库根执行 `swift test`；本包可通过 `swift build --package-path extensions/capture` 单独构建。Cida 来源和 Apache-2.0 许可见 Legal/Cida，原创代码见 LICENSE。
