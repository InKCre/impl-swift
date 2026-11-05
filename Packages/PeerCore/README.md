# PeerCore

`PeerCore` 是可被独立 Swift 程序链接的 SDK product；当前支持 macOS 15+、Swift 6.2，使用原生 PostgreSQL/PostgresNIO。它提供连接与事务、InfoBase/Storage、Source Job、Peer 参与，以及可独立选用的原生扩展生命周期。Keychain 和连接文件持久化直接属于库能力，不要求另建平台适配层。

消费者在 SwiftPM 中依赖本 package，并且只选择 `.product(name: "PeerCore", package: "PeerCore")`。最小独立消费者见 [`Examples/CoreConsumer`](../../Examples/CoreConsumer/Package.swift)；在仓库根运行 `bash scripts/check-core.sh` 可构建并运行该消费者，不连接数据库、不启动 UI。

调用方创建 `PeerDatabase(applicationVersion:name:labels:)`，通过显式 `ConnectionTarget` 与凭据发起操作，结束时 `await database.shutdown()`。构造本身不联网、不注册 Peer；注册和租约是明确的方法调用。借用数据库的 Capture/Local Files 客户端不关闭它；第一方 App 将一个实例放入 `PeerHostContext`，在各扩展停止后统一关闭。独立消费者可以创建彼此隔离的实例，不继承 App 的 Bundle 身份、机器名称或进程单例。

`PeerMacUI` 是同一 package 中的应用 UI product，提供宿主 UI 协作和连接表单编辑。仅链接 `PeerCore` 不会拉入该 target。窗口、表单输入与授权交互策略由 App/PeerMacUI 拥有；`NativeExtension` 只要求业务生命周期，不要求显示主窗口。具体扩展的界面仍属于相应扩展。

本次候选尚未发布，`PeerDatabase.shared` 已删除。客户端构造函数要求传入数据库；表单型 `ConnectionSettings.saveEdited` 的消费者需 `import PeerMacUI`。数据库协议、图形状与扩展业务身份保持原合同。
