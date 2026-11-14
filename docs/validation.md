# 验证范围

适用源码：WeChat2AI 0.1.0 / build 1。以下结果均为本机检查，不代表公开分发或远端 CI 已完成。

## 自动检查

2026-11-14，在 Apple Silicon / macOS 26 下从空构建目录执行；模块为 `WeChat2AICore` 与 `WeChat2AICLI`。

| 检查 | 结果 |
| --- | --- |
| `bash scripts/test.sh` | 60 项，0 失败 |
| `bash scripts/test-app.sh` | 33 项，0 失败 |
| `bash scripts/test-release.sh` | 29 项，0 失败 |
| `swift build` | 核心库与唯一 CLI 构建通过 |
| `bash scripts/package.sh` | App、分享扩展、签名及 ZIP 生成通过 |
| 解压后的 `codesign --verify --deep --strict` | 通过 |
| 包内容 | 25 个条目，App 与扩展均附一致的 LICENSE / NOTICE，无 AppleDouble 或私人源码路径 |
| Shell 语法与 Markdown 文件引用 | 通过 |

测试包：`WeChat2AI-0.1.0-build1-arm64.zip`。SHA-256：`f69fd398c0b3e45c7c8d23fd76419fec40e6ca2654ba9d94fe990e5da29c7f9e`。包位于被忽略的 `build/releases/`，尚未公开分发。

源码和资源的模式检查未发现个人邮箱、私人绝对路径或常见凭据。截图的 EXIF 仅含像素尺寸，未发现身份、设备或位置字段。模式检查不代替完整安全审计。

## 界面素材

[主窗口](images/main-light-synthetic.jpg)、[深色最小窗口](images/main-dark-minimum-synthetic.jpg)、[图片预览](images/image-preview-synthetic.jpg)及四页设置截图均来自独立 SwiftUI 测试宿主。聊天、图片、模板、接收任务和路径均为虚构。

资料库与数据、接收两页已使用当前构建重新截图并核对四项数据路径和虚构接收状态；测试宿主与专用资料根已清理。其余截图展示相同界面实现，未重新逐项操作。

界面内容区分别为浅色 1180 × 760pt、深色最小 960 × 620pt、设置 560 × 570pt。截图展示来源与批次、阅读和任务区、长正文、图片及设置；不作为微信或外部 Agent 端到端结果。

## 发布前待验证

- 新建公开仓库后的 CI、main / tag 保护和私人漏洞报告渠道。
- macOS 13、Intel 实机和完整 VoiceOver / 键盘 Tab 顺序。
- 真实微信分享，以及三个 Agent 的文件授权、资料读取与用户确认发送。
- Developer ID、Apple 公证及干净机器下载 / 首次运行。
- 全部图片格式、超大批次、网络磁盘和同步冲突。

本机测试使用隔离路径和虚构资料；构建不安装 App、注册扩展或发送任务。当前产品边界见[产品约定](product-contract.md)，分发要求见[分发说明](distribution.md)。
