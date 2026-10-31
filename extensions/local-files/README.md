# 本地文件 Swift 分发

`LocalFiles` 拥有位置 URI、提取、Source 配置、对账和图更新；`LocalFilesMac` 拥有书签、FSEvents、监视生命周期及原生界面。Host 静态组合此扩展与 Capture。共享合同位于 InKCre/docs 的 `20-product-tdd/local-files-contract.md`，无需 Python 服务或新数据库迁移。

Source 配置在 info-base，书签及原连接绑定在 Host 的 `extensions/inkcre-local-files/directories.json`，权限 0600。密码仅存系统 Keychain。先监视再扫描；通知合并为待核对状态，不保存事件日志。每 30 秒核对共享配置、待执行 Job 和失败扫描，正常监视不会每 30 秒重新读取所有文件。每轮从原连接的 Keychain 取凭据。停止等待当前文件事务和提取结束，再释放监视与目录访问。

`LocalFilesModel` 拥有当前连接、目录绑定和前台读取；每个 `DirectoryMonitor` 独立拥有 FSEvents、扫描任务、变更合并、Job 收束和目录访问的释放。切换前台连接不停止其他已绑定目录，扫描结果只刷新所属连接的窗口数据。停止监视时，所有调用者都等待当前扫描结束，之后才释放目录访问。

列表与扫描只读取文件元数据和正文 ID；选中文件才读取该文件正文，修订变化后更新当前正文。未变化文件不进入逐文件写事务，完整扫描仍复核来源状态并处理失效文件。

读取端解释 `extensions.local_files.file.v1`／`file.v2` 与 `body`，不要注册不能执行的 Source 占位类。重连扫描当前目录，不引入原文件复制或正文 outbox。

验证使用合成目录和一次性 PostgreSQL。`swift test` 包含 URI／六种格式提取；设置 `INKCRE_FILES_TEST_DATABASE`、`INKCRE_FILES_TEST_PORT`、`INKCRE_FILES_TEST_PASSWORD` 后执行真实事务、FSEvents、暂停／恢复、重启、删除保留与隐藏窗口主流程。测试运行角色是 `inkcre_core`，仅允许指定一次性数据库。`INKCRE_LAYOUT_EVIDENCE_DIR` 保存实际 AppKit 窗口的渲染图，不激活窗口。


本分发写入 file.v2：HTML 保存提取后的结构，Markdown 保存原文，PDF／DOCX／Org／纯文沿原有文字范围。读取按正文的精确 resolver 选择纯文、HTML 或 GFM；WebKit 禁止来源脚本，净化及 CSP 阻止资源自动加载，已知资源保留说明和链接。没有可信网页地址时不把机器路径当 base。

成功重新提取才在原事务内升级旧根和正文的格式，保持 ID 与其他关系；失败／原件缺失保留旧成功内容和修订。`mac-native-content.v2` 触发原件未变时的必要重提取，分发版本选择沿用 Host 的既有保护。
