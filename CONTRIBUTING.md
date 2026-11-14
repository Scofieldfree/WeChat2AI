# 参与 WeChat2AI

请先阅读 [README](README.md)、[架构](docs/architecture.md)和[开发说明](docs/development.md)。项目使用 Swift、SwiftUI 和 AppKit，核心逻辑不依赖 GUI。

## 本地开发

从仓库根目录运行：

```bash
bash scripts/test.sh
swift build
bash scripts/build.sh
```

测试使用 `Tests/Run.swift` 中的独立运行器，当前没有 SwiftPM test target。测试失败时停止后续打包和安装。安装是单独的本机操作，不是运行测试的前提。

App 在 `App/`，分享扩展在 `ShareExtension/`，解析、资料库、队列和交接逻辑在 `Sources/WeChat2AICore/`，CLI 在 `Sources/WeChat2AICLI/`。Shell 脚本必须从脚本位置解析仓库目录，并正确处理空格和中文路径。

## 修改约定

涉及版本、tag、CI 和发布，请先阅读[版本命名与发布规范](docs/release-policy.md)。版本准备与其他修改一样通过目标为 main 的 PR；不从功能分支独有提交发布。

- 一个提交或 PR 聚焦一个问题，说明触发场景、修改后行为和实际验证结果。
- 产品标识、数据路径、格式与配置键按[产品约定](docs/product-contract.md)实现。开发阶段直接更新实现和行为测试，文档描述当前行为。
- 使用虚构聊天和自制附件复现问题。不要提交真实导出、个人资料、授权书签、密钥、证书或构建产物。
- 提交使用 GitHub noreply 邮箱；不要在日志中保留本机私人绝对路径。
- 提交截图前检查发言人、正文、路径、账号及通知区域。公开样例必须明确标记为虚构。
- 不在构建或 CI 中安装应用、注册扩展、修改安全设置或自动发送 Agent 任务。
- UI 修改附虚构数据截图，说明窗口尺寸和浅色或深色外观；不能以截图代替数据完整性验证。

问题反馈请提供版本、系统、架构、最小复现、预期与实际行为。安全问题遵循 [SECURITY](SECURITY.md) 的报告要求。

提交自己有权贡献的内容，保留第三方版权、许可和署名。项目代码采用 [MIT](LICENSE)。
