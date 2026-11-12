# PeerCore

`PeerCore` 是可被独立 Swift 程序链接的 SDK product；当前支持 macOS 15+、Swift 6.2，使用原生 PostgreSQL/PostgresNIO。它提供连接与事务、InfoBase/Storage、Source Job、Peer 参与，以及可独立选用的原生扩展生命周期。Keychain 和连接文件持久化直接属于库能力，不要求另建平台适配层。

消费者在 SwiftPM 中依赖本 package，并且只选择 `.product(name: "PeerCore", package: "PeerCore")`。最小独立消费者见 [`Examples/CoreConsumer`](../../Examples/CoreConsumer/Package.swift)；在仓库根运行 `bash scripts/check-core.sh` 可构建并运行该消费者，不连接数据库、不启动 UI。

调用方创建 `PeerDatabase(applicationVersion:name:labels:)`，通过显式 `ConnectionTarget` 与凭据发起操作，结束时 `await database.shutdown()`。构造本身不联网、不注册 Peer；注册和租约是明确的方法调用。借用数据库的 `CaptureWriter` / `LocalFilesRepository` 不关闭它；第一方 App 将一个实例放入 `PeerHostContext`，在各扩展停止后统一关闭。独立消费者可以创建彼此隔离的实例，不继承 App 的 Bundle 身份、机器名称或进程单例。

持续运行的 Keychain 消费者传递 `DatabaseCredentials.keychain(store)`。`PeerDatabase` 在没有会话时取得一次密码，后续数据库操作与续租直接复用已授权 client，不查询 Keychain。`.password` 和 `password:` 入口同样只提供冷启动凭据；它们不能让旧业务引用覆盖新认证或把运行角色切回旧配置。显式更新认证使用 `database.authorize(target, password:)`，相同密码与数据库配置继续复用 client；`database.invalidate(id)` 或 `shutdown()` 结束会话。独立 Core 消费者应自行持有并关闭数据库实例。

App 的 Host、Capture 和 Local Files 共享同一个 `PeerHostContext` 与数据库实例。连接表单及 Capture 待办的密码修复通过 `context.savePassword` 持久化并更新该会话；相同密码及只修改名称／Web 地址继续复用 client。连接表单留空密码保存时通过 `context.reauthorize` 明确重新取密；同密码继续复用 client，失败则撤销会话。Keychain 锁定、删项或外部修改不撤销已建立的会话，重新授权或下次启动才重新检查。

`CredentialStore.read` 始终直接读取，不自行缓存。现有凭据继续保存在原 file-based Keychain，不迁移存储或引入对 SDK 宿主签名／entitlement 的新要求。`CredentialStore(service:keychain:)` 可将访问限定到明确的文件型密钥串；省略 keychain 时沿用系统搜索列表。

`PeerMacUI` 是同一 package 中的应用 UI product，提供宿主 UI 协作和连接表单编辑。仅链接 `PeerCore` 不会拉入该 target。窗口、表单输入与授权交互策略由 App/PeerMacUI 拥有；`NativeExtension` 只要求业务生命周期，不要求显示主窗口。具体扩展的界面仍属于相应扩展。

本次候选尚未发布，`PeerDatabase.shared` 已删除。扩展写入与数据访问接口的构造函数要求传入数据库；表单型 `ConnectionSettings.saveEdited` 的消费者需 `import PeerMacUI`。数据库协议、图形状与扩展业务身份保持原合同。

应用与运行参与者分别称为 App、Peer。Capture 的持久化接口使用 `CaptureWriting` / `CaptureWriter`，Local Files 的数据访问接口使用 `LocalFilesRepository`；它们直接遵守数据库协议，不是另一应用的远程代理。PostgreSQL 驱动自身的 `PostgresClient` 和 `PeerDatabase.client(for:password:)` 仍使用协议客户端术语。尚未发布的候选接口同步改名，不保留旧业务名称别名。
