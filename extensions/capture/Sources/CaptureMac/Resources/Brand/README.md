# InKCre Mac 标识资源

采集面板和菜单栏标识来自 InKCre UI 的 SwiftPM product `InKCreLogoAssets`，由 `extensions/capture/Package.swift` 声明 [UI `2.6.0`](https://github.com/InKCre/ui/tree/2.6.0) 的 exact 依赖，并随应用的 `Package.resolved` 锁定解析提交。升级时同步修改版本约束与锁文件，不跟随移动分支。

`BrandAssets` 直接使用该 product 提供的 PNG，主题选择、逻辑尺寸与 `NSImage.isTemplate` 由原生界面负责，不在本仓库另存面板或菜单 PNG：

| 用途 | Bundle 内路径 | 原生显示 |
| --- | --- | --- |
| 浅色面板 | `png/2x/original-transparent/inkcre-original-transparent-24px@2x.png` | 24 × 24 pt |
| 深色面板 | `png/2x/reverse-transparent/inkcre-reverse-transparent-24px@2x.png` | 24 × 24 pt |
| 菜单栏 | `png/2x/black-transparent/inkcre-black-transparent-20px@2x.png` | 20 × 20 pt，template |

普通 SwiftPM 运行使用公开的 `InKCreLogoAssets.bundle`。自组装应用由 `scripts/build-app.sh` 将 `InKCreUI_InKCreLogoAssets.bundle` 放入 `.app/Contents/Resources`，`BrandAssets` 在应用内只从该嵌入位置加载，缺失时直接报错，不回退到本机 `.build`。普通构建不需要解压 ZIP、执行资源生成器或安装 Web 依赖。

更新 UI 依赖时阅读该版本的 Logo 说明，按逻辑尺寸选择几何与像素倍率，并更新解析锁定；24 pt @2x 的文件是 48 × 48 物理像素，不能改选常规 48 px 的标准几何。资源嵌入验收应将 `.app` 移出构建目录，确认实际界面仍能显示标识。

应用图标继续由本仓库维护。当前几何来自原 `InKCre-logo-pack-20261021`，原始来源与固定版本见同目录 `PROVENANCE.json`；该历史来源记录不承担运行时 SwiftPM 依赖的版本锁定。

`AppIcon.svg` 与 `AppIconSmall.svg` 保留资产包的标准 256 和小尺寸 32 几何与配色，在白色圆角底板外围加入透明留白。沿用 `nearby-audio` 已修复的 legacy ICNS 光学尺度：常规底板占 824/1024，小尺寸占 28/32；圆角半径为底板宽度的 18.75%。不能把通用满版白底 PNG 直接打包成 Mac 图标，ICNS 不会自动补这层留白。

16、32 逻辑尺寸（包括对应 @2x）使用小尺寸母版，其余使用标准母版。更改 SVG 后运行 `bash scripts/build-macos-icon.sh`，通过本机已有的 `rsvg-convert` 生成整套 PNG；不要放大小尺寸位图。普通应用构建只用系统 `iconutil` 打包已生成的 iconset，无需额外安装渲染器。SwiftPM 资源 bundle 与 ICNS 在签名前装入应用。
