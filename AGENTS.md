# InKCre Mac Peer

使用中文与人沟通。未明确要求时不提交或推送。

本仓库拥有原生 macOS 采集 Peer。共享状态属于 info-base；Capture 扩展分发由其他 Peer 执行。Mac 不承载扩展宿主，不启动 Python 子进程，不把本机 SQLite 当成共享知识权威。

本体是 regular Mac 应用，拥有 Dock 图标、普通主窗口和应用菜单。快捷采集 NSPanel 是辅助入口；不得再把应用整体收窄为 accessory/LSUIElement 菜单栏工具。主窗口导航与快捷采集编辑位置分开，草稿和队列只有一个所有者。

`Sources/CaptureCore` 拥有冻结提交、SQLite、Keychain 和 Peer 协议。`Sources/InKCreApp` 拥有系统采集及原生交互。共享请求与图合同见 `InKCre/impl-py` 的 `docs/30-unit-tdd/capture-extension.md`；数据库迁移由 `impl-py` 拥有。

同次提交不得换 UUID、变更材料或改投另一个信息库。只有经过指纹核对的共享回执可以清理本机材料。选区失败不能读旧剪贴板充数；截图只持久化明确选择的区域。

运行 `swift test` 和 `bash scripts/build-app.sh`。编译不证明系统权限、真实选区、焦点或多屏行为；真实应用验证使用合成内容，按实际结果记录。开发包使用 `dev.inkcre.capture`；发布身份、签名、公证只能使用显式提供的输入。
