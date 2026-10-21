# InKCre Mac 标识资源

来自用户提供的 `InKCre-logo-pack-20261021`。来源与固定仓库版本见同目录 `PROVENANCE.json`；面板与菜单 PNG 保持资产包原字节，应用图标另做 macOS 平台画布适配。

`MarkLight.png` 和 `MarkDark.png` 分别取自原色透明、反白透明的 24 px @2x 版本，用于采集面板并按界面深浅切换。`MenuTemplate.png` 取自纯黑透明的 20 px @2x 版本，由 macOS 作为 template 图像适配菜单栏。

`AppIcon.svg` 与 `AppIconSmall.svg` 保留资产包的标准 256 和小尺寸 32 几何与配色，在白色圆角底板外围加入透明留白。沿用 `nearby-audio` 已修复的 legacy ICNS 光学尺度：常规底板占 824/1024，小尺寸占 28/32；圆角半径为底板宽度的 18.75%。不能把通用满版白底 PNG 直接打包成 Mac 图标，ICNS 不会自动补这层留白。

16、32 逻辑尺寸（包括对应 @2x）使用小尺寸母版，其余使用标准母版。更改 SVG 后运行 `bash scripts/build-macos-icon.sh`，通过本机已有的 `rsvg-convert` 生成整套 PNG；不要放大小尺寸位图。普通应用构建只用系统 `iconutil` 打包已生成的 iconset，无需额外安装渲染器。SwiftPM 资源 bundle 与 ICNS 在签名前装入应用。
