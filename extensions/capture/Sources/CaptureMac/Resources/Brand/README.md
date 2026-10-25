# InKCre Mac 标识资源

来自 InKCre UI 交付的 `InKCre-logo-pack-20261021`。当前固定到尚未发布的 [UI PR #67](https://github.com/InKCre/ui/pull/67) 候选提交 `b7fea4612999003e6976ce3649ef97fff4ad55d2`；[完整 ZIP](https://github.com/InKCre/ui/blob/b7fea4612999003e6976ce3649ef97fff4ad55d2/assets/InKCre-logo-pack-20261021.zip) 无需 Vue、npm 或渲染器即可取得原生资源。资产本身的原始来源与固定版本见同目录 `PROVENANCE.json`；面板与菜单 PNG 保持资产包原字节，应用图标另做 macOS 平台画布适配。

从仓库根目录取得并更新这三张资源：

```sh
curl -fL https://raw.githubusercontent.com/InKCre/ui/b7fea4612999003e6976ce3649ef97fff4ad55d2/assets/InKCre-logo-pack-20261021.zip -o /tmp/InKCre-logo-pack-20261021.zip
unzip -q -o /tmp/InKCre-logo-pack-20261021.zip -d /tmp
cp /tmp/InKCre-logo-pack-20261021/png/2x/original-transparent/inkcre-original-transparent-24px@2x.png extensions/capture/Sources/CaptureMac/Resources/Brand/MarkLight.png
cp /tmp/InKCre-logo-pack-20261021/png/2x/reverse-transparent/inkcre-reverse-transparent-24px@2x.png extensions/capture/Sources/CaptureMac/Resources/Brand/MarkDark.png
cp /tmp/InKCre-logo-pack-20261021/png/2x/black-transparent/inkcre-black-transparent-20px@2x.png extensions/capture/Sources/CaptureMac/Resources/Brand/MenuTemplate.png
```

本次 ZIP 的 SHA-256 为 `ec4c2390f785d64db23c73f46c3c7a976cb6269d6724e5fa0a807467be79e25f`，三个 PNG 与此前用户提供的本地包逐字节一致。更新交付版本时先阅读该版本的 Logo 说明，按逻辑尺寸选择几何与像素倍率；不跟随移动分支。

`MarkLight.png` 和 `MarkDark.png` 分别取自原色透明、反白透明的 24 px @2x 版本，用于采集面板并按界面深浅切换。`MenuTemplate.png` 取自纯黑透明的 20 px @2x 版本，由 macOS 作为 template 图像适配菜单栏。

`AppIcon.svg` 与 `AppIconSmall.svg` 保留资产包的标准 256 和小尺寸 32 几何与配色，在白色圆角底板外围加入透明留白。沿用 `nearby-audio` 已修复的 legacy ICNS 光学尺度：常规底板占 824/1024，小尺寸占 28/32；圆角半径为底板宽度的 18.75%。不能把通用满版白底 PNG 直接打包成 Mac 图标，ICNS 不会自动补这层留白。

16、32 逻辑尺寸（包括对应 @2x）使用小尺寸母版，其余使用标准母版。更改 SVG 后运行 `bash scripts/build-macos-icon.sh`，通过本机已有的 `rsvg-convert` 生成整套 PNG；不要放大小尺寸位图。普通应用构建只用系统 `iconutil` 打包已生成的 iconset，无需额外安装渲染器。SwiftPM 资源 bundle 与 ICNS 在签名前装入应用。
