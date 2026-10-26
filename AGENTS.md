# InKCre Mac Peer

使用中文与人沟通。未明确要求时不提交或推送。

本仓库拥有原生 macOS 采集 Peer。共享状态属于 info-base；Mac 自己校验材料、构图并通过共享数据库协议原子写入，不依赖其他 Peer 执行采集。Mac 承载随签名应用交付的原生扩展，不启动 Python 子进程，不把本机 SQLite 当成共享知识权威。

本体是 regular Mac 应用，拥有 Dock 图标、普通主窗口和应用菜单。快捷采集 NSPanel 是辅助入口；不得再把应用整体收窄为 accessory/LSUIElement 菜单栏工具。主窗口导航与快捷采集编辑位置分开，草稿和队列只有一个所有者。

`Packages/PeerCore` 拥有通用 PostgreSQL 原生连接、事务、图／Storage、Source Job、凭据、Host 配置和原生扩展生命周期。`extensions/capture` 拥有材料、系统采集、界面、SQLite 草稿／待办、构图与收入恢复；`extensions/local-files` 拥有目录来源、文件提取、监视、持续对账及界面，原件留在磁盘。`Sources/InKCreApp` 拥有应用 Host、普通主窗口、导航、菜单及设置，不能由某一个扩展控制主窗口生命周期。跨平台业务合同归各 first-party extension，数据库 schema／迁移由 impl-py 交付。

Capture 和此次 Mac 分发尚未发布，直接修订候选 schema，不增加旧 HTTP、旧回执或旧本机格式兼容。保留原开发数据文件，不自动导入或清空。第三方引用必须保留许可证、固定来源、修改说明和署名；打包必须包含完整依赖许可。

同次提交不得换 UUID、变更材料或改投另一个信息库。只有事务明确成功或核对共享 Capture 根的材料摘要后才可清理本机材料。扩展不拥有独立共享表；草稿、待办和确认结果由本机 SQLite 保存。选区失败不能读旧剪贴板充数；截图只持久化明确选择的区域。

运行 `bash scripts/check.sh` 和 `bash scripts/build-app.sh`。前者与 CI 共用 Xcode 26.2 的 Swift 格式／lint 检查和测试入口，覆盖 Host、PeerCore 与 first-party 扩展；固定来源的 Vendor 代码按上游格式维护。编译不证明系统权限、真实选区、焦点或多屏行为；真实应用验证使用合成内容，按实际结果记录。开发包使用 `dev.inkcre.capture`；发布身份、签名、公证只能使用显式提供的输入。
