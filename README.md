# InKCre for Mac

正常运行于 Dock 和应用切换器中的原生 Mac Peer，首版提供收集能力。macOS 15 或更新版本，可采集当前选区、明确粘贴的文字/链接/图片、单屏框选截图与主动输入的想法。原材料、来源与补充想法分别保存；收入不依赖 OCR 或模型处理。

启动或点击 Dock 图标打开普通主窗口，侧栏提供采集、记录、本地文件、Peer 与连接。主窗口可缩放、最小化，记住尺寸位置；关闭主窗口后进程、菜单栏入口和队列继续运行，`⌘Q` 才退出。Peer 页展示当前信息库、连接对应的 Peer 身份与连接问题；配置连接本身不表示在线。

主窗口使用系统 `NavigationSplitView` 和原生工具栏，标题随当前页面更新。采集页工具栏提供新想法、粘贴材料、框选截图，采集与记录页保留快捷面板入口；记录和 Peer 页不显示采集动作。侧栏开关固定在窗口控制按钮旁，系统分隔线跟随侧栏宽度，内容区不另放重复顶栏。窗口通过 `NSHostingController` 与 `fullSizeContentView` 承载 SwiftUI，不用弹性占位或自制侧栏控制器修补位置。显示菜单以 `⌘⌥S` 切换侧栏，与系统工具栏按钮共用 `NavigationSplitView` 的可见状态；命令沿窗口响应链执行，设置窗口和快捷面板不会误切主窗口侧栏。全屏仍使用系统命令。

全局入口打开独立快捷采集面板。主窗口与面板共用同一草稿、记录和队列，同时只有一份可编辑采集视图。“在主窗口继续”转回主窗口采集页；关闭或收起快捷面板保留草稿并归还前一个应用的焦点。主窗口菜单提供新想法、设置、关闭、最小化和窗口重新打开等普通 Mac 操作。

## 构建与打开

需要 Xcode 26.2 / Swift 6.2。PostgresNIO 及依赖通过 SwiftPM 解析，精确修订固定在 Package.resolved。

```sh
bash scripts/check.sh
bash scripts/build-app.sh
open dist/InKCre.app
```

构建产物是 universal `.app` 和 `dist/InKCre-0.1.0-universal.dmg`。未指定开发签名身份时使用 ad-hoc 签名；两种开发包都不能当作已公证的发行版。将 `.app` 放在固定位置，并保持稳定的开发签名身份后再授权。

首版尚未发布，应用版本当前为 `0.1.0`，版本与 build 的构建输入统一在 `Application.json`。`CFBundleShortVersionString` 保存应用版本，`CFBundleVersion` 单独记录构建序号；交付说明按实际构建写作 `0.1.0（build 19）`，不能将构建序号称作 `v15`。首版发布前最多递增 patch 或 build，不提升 minor／major；一般开发构建只递增 build，正式版本准备遵循组织的 Release 流程。

需要反复开发和实测系统采集时，使用本人明确指定的 Apple Development 身份：`DEVELOPMENT_SIGNING_IDENTITY='Apple Development: …' bash scripts/build-app.sh`。也可将该身份的名称或证书 SHA-1 单独保存在 ignored `.local-development-signing-identity`（一行文本，不执行其中内容）。脚本不会自动选择证书或回退到另一个身份；正式发布仍使用独立的 `SIGNING_IDENTITY` 输入。ad-hoc 身份随代码版本变化，系统可能不再认可先前的隐私授权；固定路径和 bundle ID 本身不足以解决此问题。[Apple 对代码身份与授权的说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

默认 `⌃⌥I` 读取当前选区并唤起快捷面板，`⌃⌥S` 框选截图；采集编辑器内 `⇧⌘V` 粘贴材料、`⌘↩` 收入，Esc 仅收起快捷面板并保留草稿。设置中的五项快捷键均可分别录入、清除或恢复默认，修改立即生效并在重启后保留。点击对应按键按钮后按下组合键，Esc 取消录入。组合键须包含 ⌘、⌃ 或 ⌥，收起面板的默认 Esc 除外。`⌘W`、`⌘Q`、`⌘,`、`⌘⌥S` 等窗口、导航和编辑命令保留给平台操作。重复组合、标准命令冲突或系统注册冲突会提示并保留原设置，其他快捷键不受影响。录入期间暂停全局触发，离开设置或切换应用时取消录入。

收集和截图在全局生效；粘贴和收入作用于主窗口采集页或快捷面板；收起仅作用于快捷面板。输入法组词时采集快捷键交给输入法处理。“采集”菜单显示当前配置的快捷键；菜单和按键使用相同的可用条件，无法执行的局部快捷键不会吞掉输入。选区需要辅助功能权限，截图需要屏幕录制权限；输入和明确粘贴不需要这些权限。

直接 AX 读取不可用时，仅在系统明确报告非空选区且不是安全输入时尝试复制回退。没有可靠选区时显示降级提示，不采集旧剪贴板或编辑器默认复制的整行。真实来源缺失就留空；明确粘贴不会伪造来源应用。网页抓取、OCR 和知识查询不属于此版本。目录文件由独立的本地文件扩展处理。

截图在应用内使用 BetterShot 选区组件的固定版本改编，先冻结各屏画面，再拖动框选。松手后可拖动区域移动、拖动八个手柄缩放，或在区域外重新框选；附近的原生“截取”／“取消”按钮始终留在屏幕内。回车或双击选区确认，Esc、右键和“取消”退出并保留原草稿。确认只从看到的冻结画面裁剪原图 PNG，不重新拍摄，不调用 Apple 截图工具栏。全屏冻结帧仅在本次会话内存中存在，只持久化明确确认的单屏区域。

截图入口只静默检查授权；未授权时在面板内显示说明，不反复调用系统授权请求或弹出应用警告。只有明确点击“请求屏幕录制权限”才发起授权。授权后按系统要求完全退出并重新打开应用，不能仅凭系统开关亮起就断言当前进程已获得权限。[Apple 的 ScreenCaptureKit 示例说明](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)。

移除材料、删除草稿和删除记录均先显示系统确认框；取消确认不会改变内容，确认后直接删除，无法撤销。快捷面板的“取消本次”在有内容时先确认，确认后删除本次草稿并关闭面板；空面板直接关闭。“收起”只隐藏面板并保留草稿。删除已收入记录只影响本机列表，共享内容仍属于 info-base。不提供回收站或“撤销移除”。

手写想法使用单一主要输入区；采集原文与可选附注分别呈现，附注按需展开，已有附注默认可见，编辑区不嵌套在原文滚动区内。图片可用原生 Quick Look 查看原始尺寸，预览临时文件只对当前用户可读写，关闭预览或离开内容时移除。未收入记录可以展开查看完整原文、全部图片、来源和附注，无须导出 JSON 才能核对材料。上次收入状态与当前草稿保存状态分别显示，“查看记录”定位到对应条目，继续写下一条想法不会丢失入口。

## 数据库与原生主流程验收

默认 `bash scripts/check.sh` 检查格式和不依赖数据库的行为；数据库用例未配置时会明确跳过。两种入口都显式串行执行测试，因为原生界面用例共享 NSApplication、菜单和焦点状态。`SWIFT_JOBS` 只调节编译并发，默认 2。

完整验收消费 impl-py 的权威初始化，不在本仓维护 schema。CI 使用 `scripts/database-source-revision` 固定该实现版本；本地可传入已完成 PDM 安装的 impl-py checkout，入口会显示实际 revision。准备 PostgreSQL 17 与 pgvector 后，从空库开始执行：

```sh
brew install postgresql@17 pgvector
# impl-py 中先按其说明安装 Python 3.12 和锁定 PDM 依赖。
python3 scripts/check-database.py --impl-py /path/to/impl-py \
  --postgres-bin "$(brew --prefix postgresql@17)/bin"
```

此入口仅在临时目录创建独立 PostgreSQL cluster、随机回环端口和随机凭据，调用权威 `scripts/database.py init --profile development`／`ready`，开启 Capture 和 Local Files 的全部数据库及隐藏原生窗口旅程，结束后停止并删除该临时 cluster。不会使用现有 development／preview 库，也不启动系统 PostgreSQL 服务。缺工具、迁移失败或验收失败均返回非零。测试输出即时刷新；Swift 测试进程最多运行 10 分钟，超时会终止其子进程及后代进程组、清理自有 cluster 并返回失败，不能视为验收通过。

已有独占且完成权威迁移的一次性数据库时，可以消费权限为 0600 的 JSON descriptor：

```sh
python3 scripts/check-database.py --descriptor /private/path/swift-test.json
```

descriptor 必须声明 `disposable: true`，包含 `host`（回环）、`port`、`database`、`username: "inkcre_core"` 和 `password`；调用者负责该库的独占性与销毁。凭据通过子进程环境传入，不 source dotenv，也不放入命令参数。脚本不修改 schema；`INKCRE_LAYOUT_EVIDENCE_DIR` 可指定已有目录保存合成界面的实际渲染图。这些检查不代表系统授权提示、真实跨应用选区、多屏实体环境或公证已通过。

PeerCore 的 `withConnection` 借出限于作用域内使用的连接；`query` 明确收集 `[PostgresRow]` 后返回，调用方逐行解码并检查取消，不承诺流式背压。检查连接状态与发出查询必须留在同一次 NIO event loop 执行中，避免关闭后的驱动 promise 无人完成；不要绕回原始异步驱动查询。当前目录记录读取仍会同时持有查询行和最终记录数组，大结果的峰值内存不是原来的流式水平。

原生会话以运行角色设置 `client_connection_check_interval=1000`，在项目使用的 PostgreSQL 17/macOS 或 Linux 上，每秒检查执行中的查询是否已失去客户端；代价是长查询增加周期性检查。它检测内核已报告的断连，不是同步回滚确认；`statement_timeout=30000` 继续限制无法及时检测的服务器工作。具体平台与网络边界见 [PostgreSQL 17 连接配置](https://www.postgresql.org/docs/17/runtime-config-connection.html#GUC-CLIENT-CONNECTION-CHECK-INTERVAL)。

## 连接信息库

连接设置使用 PostgreSQL 主机、端口、库名、独立运行角色及密码，可选 Web 地址。远端使用 TLS 并校验证书；只有回环开发地址允许关闭 TLS。密码存于 Keychain，角色拥有已准入数据库协议权限，不使用迁移管理员或 JWT 签名密钥。

在“连接”页可以添加命名连接、编辑当前连接，并用“当前连接”切换；保存会同时使用该连接，重新打开应用会恢复上次选择。切回连接或编辑运行角色、密码、名称时保留连接与 Peer 身份；更换数据库地址才创建新连接，原条目仍可选择。连接名称只用于本机辨认，不修改共享 Peer 名称，也不重建数据库连接池。只读取当前多连接配置格式；不支持的开发配置会报错并保留原文件，不自动迁移或清空。

切换只改变当前操作的信息库。冻结 Capture 待办继续向原目标恢复，已经授权的目录继续监视并收入其原信息库；目录绑定只保存连接引用、Peer 身份和访问书签，后台与待办从完整连接集合读取最新认证配置；不会搬迁、清空材料或将旧目录改投新库。前台目录列表在切换时清空并重新加载，切换完成前禁用其操作。

凭据使用 macOS file-based Keychain。后台读取禁止系统授权弹窗；密钥串锁定或应用访问被拒绝时，显示需要处理的连接错误，只有主动保存连接时允许交互。访问策略属于进程，因此共享凭据入口串行执行读写并恢复原策略。开发验收应由签名应用保存测试密码，不能用 `security add-generic-password -T` 预置后假定签名分区已正确授权。

`⌘,` 打开唯一的原生设置窗口，工具栏提供“连接”“扩展”“采集”三页；采集页集中管理快捷键和系统权限。主窗口 Peer 页提供同一连接选择入口，当前连接编辑打开设置窗口中的原生 sheet；无效输入在表单内提示并保留，可用 Esc 取消、Return 保存。编辑期间不能通过新建或全局采集切走表单。保存后通知正在运行的 Capture 更新连接，并在后台检查，不重启扩展或丢弃当前草稿。Host 维护连接的在线状态，扩展在执行时另行检查共享参与；配置已保存或在线不等于扩展可以写入。权限页分别显示辅助功能与屏幕录制的实际许可状态。未配置连接时点击“收入”会打开连接表单；保存或取消都返回原草稿，保存后由用户再次确认收入。

共享数据库的分发标识需允许原生宿主使用自己的格式。Capture Swift 分发在本 Peer 内构图，用同一 PostgreSQL 事务写入标准 Block／Relation／Storage，无 Capture 专用表；Python Peer 与 PostgREST 均无需在线。图、材料指纹和收入语义属于 first-party `inkcre/capture`，共享合同见 [Capture Extension 合同](https://github.com/InKCre/docs/blob/main/20-product-tdd/capture-contract.md)。

“草稿已保留在本机”表示 SQLite 已成功落盘；“本机已保留，待收入”表示冻结材料和目标已经保存；“结果待确认”表示请求可能已经成功；事务明确成功或恢复核对 Capture 根的材料摘要后才显示“已收入”。网络中断、退出或切换连接不会给旧提交换身份或改目标。首次发送直接进入提交事务；已发送待办先查原 Capture 根，必要时复用原材料、图与原 UUID 向同一信息库重试。SQLite 已确认的记录不再发送；未确认的提交若在恢复前被其他 Peer 删除，重试可能重新收入。

材料累计最多 32 MiB，支持 PNG/JPEG/GIF/WebP，原生数据库通过 bytea 参数保存原图。失败材料可在“待收入”中导出 JSON，导出不含连接凭据。暂不提供修改已经发送的材料或自动舍弃失败项。

失败记录的“更新密码…”仅更新原连接的 Keychain 项，并按原 UUID、材料与数据库目标重试，不切换当前连接。已收入记录缺少打开地址时，“配置 Web 地址…”仅修改该条记录的展示地址，保存后打开共享内容；记录自身地址优先，同一 Peer 当前连接的 Web 地址仅作补充。

待收入记录可“取消收入”，停止后续自动发送并保留原材料、UUID 和目标；“继续收入”先核对原 Capture 根。已发出的请求可能已完成，取消不能撤回共享内容。确认删除待办会停止后续发送并删除本机记录和材料；已经发出的请求仍可能完成，迟到响应不会重新创建本机记录。

## 本地文件

在主窗口的“本地文件”添加目录，系统目录选择器返回的权限通过安全作用域书签保存。首次扫描以及之后的目录变化会收入 PDF、DOCX、Markdown、Org、HTML 和纯文本。文件表展示提取结果，选中后可读正文、打开原件或在 Finder 显示。错误留在对应文件中；空列表、扫描中、部分失败与连接错误分别呈现。

本地文件扩展通过原生 PostgreSQL 直接更新资料，修改或可证明的重命名保持资料 ID。原件删除后正文保留，位置标为失效；目录离线、权限错误或解析失败不会清空旧正文。暂停停止监视，恢复和应用重启重新核对；移除先确认，只移除 Source，保留共享图。目录始终绑定原信息库，切换当前连接不改投。

原件链接是 `inkcre-peer-file://<peer-id>/<机器绝对路径>`。原件留在磁盘，本地不另存正文队列或文件备份，数据库只存正文和元数据；其他 Peer 读取正文无需此 Mac 在线。应用内只打开属于本 Peer 的位置，不注册系统 URL handler，也不提供跨 Peer 文件传输。文件消失前尚未成功收入的内容无法恢复。

PDF 读取文字层；DOCX 读取主文档与表格文字，遗漏脚注、批注等附属内容，详情会标出范围。Markdown／Org 保留原语法；HTML 用 SwiftSoup 解析，不执行脚本或下载外链。输入上限 64 MiB，正文上限 8 MiB；UTF-8 与带 BOM 的 UTF-16 可直接读取。详细维护边界见 [本地文件分发](extensions/local-files/README.md)。

## 本地数据与发布

开发包的 Host 配置位于 `~/Library/Application Support/dev.inkcre.capture/connection.json`；Capture 数据位于同目录 `extensions/inkcre-capture/capture.sqlite`，使用 WAL/FULL。确认后清理本机材料，保留共享引用。WAL 和空闲页不提供安全擦除保证。此前未发布开发版的数据文件原样保留，本版没有旧格式导入或 HTTP 回退层。

`Sources/InKCreApp` 拥有主窗口、导航、菜单与设置。`Packages/PeerCore` 提供数据库、标准图／存储、Source Job、凭据和原生模块生命周期；`extensions/capture` 与 `extensions/local-files` 是独立 Swift 包，各自拥有业务与 Mac 界面。宿主菜单提供独立的“Peer 连接…”，Capture 停用后仍能编辑连接，宿主继续维护 Peer 在线状态。Capture 在实际提交时办理首次准入并校验共享选择，不另设连接状态页或连接轮询。设置中的“扩展”页展示实际携带的分发版本和本机运行状态，可独立启停。“在此 Mac 启用”只控制本机入口和任务，不读写远端启用意图，离线也可操作；停用等待当前工作收束并保留材料，退出只停止运行。共享停用、移除或版本不匹配仍阻止写入。扩展设置中的“在「信息库」启用本机版本”明确对指定信息库选择当前 bundled 版本并启用参与，可用于升级后恢复或重新加入；普通重连不会覆盖共享选择。

Capture 的精确 manifest 随签名应用交付，格式为 `swift_bundled`。当前不实现动态插件下载／热加载，其他版本需更新应用。扩展版本与应用版本分开，不声称已有 Registry 原生 Swift 下载通道。目录扩展每次启动或首次使用连接时初始化类型定义，30 秒刷新只检查参与与来源；Host 对已使用的连接统一续租。手动目录扫描逐文件检查本地取消与截止时间，远端取消以 5 秒为间隔在文件处理边界检查，并在结束前再次确认。

菜单栏 template 图标和明暗面板标识通过 InKCre UI 的 SwiftPM product `InKCreLogoAssets` 取得，当前依赖正式版本 `2.6.0`，使用 exact 约束并由 `Package.resolved` 锁定提交。SwiftPM 解析资源，打包脚本将资源 bundle 嵌入最终 `.app`，普通构建无需解压 ZIP、安装 Web 依赖或运行渲染器。应用 ICNS 继续由本仓库维护，在原标志外使用 Mac 专用圆角底板和透明边距，避免通用白底画布满版导致 Dock 尺寸过大。依赖与资源路径、原始出处、小尺寸/高 DPI 几何与图标再生步骤见 [Mac 标识资源](extensions/capture/Sources/CaptureMac/Resources/Brand/README.md)。

发布构建显式设置稳定 `BUNDLE_ID` 与 `SIGNING_IDENTITY`；可用 `NOTARY_PROFILE` 指定已配置的 notarytool Keychain profile。脚本不会寻找或创建发布凭据。发布后保持 bundle ID 与签名团队不变，以保留系统权限、Keychain 和待办身份。

```sh
BUNDLE_ID=你的稳定BundleID SIGNING_IDENTITY='Developer ID Application: …' \
  NOTARY_PROFILE=你的Profile bash scripts/build-app.sh
```

Swift 测试覆盖冻结包重开、目标绑定、原子确认、原生构图、原生数据库事务、共享材料指纹与扩展生命周期。原生权限、多应用选区、多屏、Intel 实机与公证安装还需对应环境验证，不能由 universal 编译结果推断通过。


原创 Swift 代码使用 MIT，Cida 选区读取与采集协调改编保留 Apache-2.0，BetterShot 选区与冻结图组件保留 BSD-3-Clause。见 [开源许可与致谢](THIRD_PARTY_NOTICES.md)。构建脚本从本次解析的依赖收集完整许可，随开发包交付；菜单“开源许可与致谢…”可打开通知。

数据库操作将租用、结果读取和事务限制在同一个可取消作用域，单次最多等待 30 秒；取消或超时关闭当前连接。在途 Capture 仍通过原提交恢复确认。各信息库独立续租、刷新目录和处理采集待办，同一信息库内，符合重试条件的采集待办按首次提交顺序处理，后续重试不改变次序。停用本地扫描后不再另起网络任务写回 Job 终态，未确认终态由共享 Job 的既有截止时间收束。
