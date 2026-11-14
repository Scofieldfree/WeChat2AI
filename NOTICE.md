# 资源与依赖说明

项目源码、随附文档、自制测试资料及下述品牌资源采用根目录的 MIT License，版权署名为 Scofieldfree。二进制 App 与分享扩展的 Resources 目录均附 LICENSE 和本说明。

## 品牌资源

| 文件 | 来源与用途 |
| --- | --- |
| `Resources/Icon/app-icon.png` | 维护者提供的 Editorial Sandstone 2048 × 2048 图标源图；通过系统 sips / iconutil 生成 App 及扩展图标 |
| `Resources/Brand/wordmark-light.svg`、`wordmark-dark.svg` | 从维护者提供的 SVG 画板提取的浅深色字标路径，移除了展示背景，保留字形、颜色和安全边距 |

上述图标与字标由维护者授权随项目按 MIT 许可证公开再分发。项目不宣称获得微信、腾讯、OpenAI 或 Anthropic 的官方授权、认可或合作关系。MIT 许可不授予第三方商标权。

## 测试与截图

`Tests/Fixtures/` 全部为虚构聊天及自制文本附件。图片测试素材由 `Tests/AppStateTests/Run.swift` 使用系统绘图接口生成，不使用真实聊天图片。

`docs/images/` 的 JPEG 来自当前源码的隔离 SwiftUI 测试宿主，全部使用虚构资料：主窗口、深色最小窗口、图片预览及四个设置页。设置页使用专用临时目录、独立偏好、自制图片和虚构模板 / 接收任务；目录、计数与客户端检测状态均是演示内容，不含真实聊天或个人路径。

截图不改写界面内容，源图保留系统窗口装饰；生成尺寸及实际验证范围见 `docs/validation.md`。图片不代表真实微信或外部 Agent 已完成端到端回归。

## 系统组件与开发工具

无外部 Swift 包依赖，也未捆绑第三方库实现。Swift、Foundation、AppKit、SwiftUI、Combine、CoreGraphics、ImageIO、UniformTypeIdentifiers、CryptoKit 和 Darwin 由 Apple 工具链及 SDK 提供。`Sources/CZlib/shim.h` 仅引用系统 `zlib.h`，modulemap 链接系统 libz；仓库未复制 zlib 实现。

SF Symbols 通过系统 API 获取，不随仓库分发独立符号图集。系统组件、工具和第三方产品的权利不由本项目 MIT 许可证重新授予。

GitHub Actions 使用官方 actions/checkout，固定提交见 `.github/workflows/ci.yml`；它不属于 App 运行时依赖。新增外部代码或素材时，应记录来源、版本、适用许可及必要署名。
