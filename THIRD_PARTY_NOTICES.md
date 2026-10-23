# 开源许可与来源

InKCre Swift 原创实现使用 MIT。参考或改写的 Cida 文件使用 Apache-2.0，保留其独立许可。完整许可随源码与应用交付。

Cida（辞达）由 Xuanwo 及贡献者开发。选区读取与采集协调骨架的来源、核对版本与 InKCre 修改范围记录于 extensions/capture/Legal/Cida/ATTRIBUTION.txt。本应用不借用 Cida 的图标或产品身份，不声称上游为本应用背书。

BetterShot 由 Kartik Labhshetwar 及贡献者开发。CaptureMac/Vendor/BetterShot 中的选区、几何和冻结图裁剪来自固定修订，使用 BSD-3-Clause；来源及修改范围见 extensions/capture/Legal/BetterShot/ATTRIBUTION.txt，完整许可随源码与应用交付。未引入其 Cap 3D 或 MacShot 滚动截图组件，不使用其品牌或声称上游背书。

PostgresNIO 及传递依赖使用各自许可。Package.resolved 固定来源与修订；scripts/collect-licenses.py 从实际解析的源码收集完整 LICENSE／NOTICE，包括 BoringSSL 的内嵌许可。缺失许可会使打包失败。生成结果随应用保存在 Contents/Resources/THIRD_PARTY_NOTICES.txt，可从应用菜单打开。

用户提供的 InKCre logo pack 用于本项目品牌；代码 MIT 许可不授予 InKCre 商标或品牌资源的使用权。品牌目录保留出处记录。

[SwiftSoup 2.14.3](https://github.com/scinfu/SwiftSoup/tree/2.14.3)（e7f85f4d3dd91ca9a1e94d3328aa1ed5120a8c0f）用于本地 HTML 文字解析，使用 MIT。构建收集上游完整 LICENSE，保留原 jsoup 作者与 Swift port 作者署名。

[Hister](https://github.com/asciimoo/hister) 的目录监视与客户端提取行为为本地文件功能提供启发。参考版本 f1fff29683c8c8006a35d3387384d9b1e123cebe，项目使用 AGPL-3.0-or-later。本实现未复制或改写其源码，不运行其服务；本致谢不表示上游参与或背书。
