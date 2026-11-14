# WeChat2AI 项目协作规范

## 开始工作

- 先阅读 [README](README.md)、[架构](docs/architecture.md)和[开发说明](docs/development.md)，修改前检查工作区差异，保留已有未提交改动。
- 涉及界面、主题、组件、文案或交互时，必须先阅读并遵循[全局 Theme 与交互 UX 规范](docs/spec/global-theme-and-ux.md)。设计参考图中的示意功能不自动成为开发需求。
- 设计变更同步全局规范及[验证记录](docs/validation.md)。SwiftUI 为唯一主界面；AppKit 负责系统窗口、面板和文本桥接。
- 产品行为与数据范围同时遵循[分析任务](docs/analysis-tasks.md)、[产品约定](docs/product-contract.md)和[隐私说明](PRIVACY.md)；发现冲突时明确差异并同步相关文档。
- 涉及分支、版本、tag、Release、CI 或打包时，先阅读并遵循[版本命名与发布规范](docs/release-policy.md)。main 是唯一发布来源；版本以 `version.json` 为准，使用 `bash scripts/version.sh set` 同步两份 plist，不手工分开改版本。

## 实现约定

- 保持原生 macOS 13+、Swift / AppKit / SwiftUI 技术路线及现有脚本构建方式，不为普通修改引入额外依赖或新工程体系。
- `App/` 负责界面、状态与操作编排；`Sources/WeChat2AICore/` 负责解析、资料库、接收队列和交接规则；`ShareExtension/` 保持独立的系统分享边界；CLI 位于 `Sources/WeChat2AICLI/`。
- 视图通过共享模型发出操作，不直接复制文件或改写资料库；耗时文件操作在后台执行，界面状态在主线程更新。保留重复操作拦截、弹窗互斥及过期预览保护。
- UI 统一使用 Editorial Sandstone 主题及语义 Token，覆盖浅深色、键盘焦点、禁用、加载、错误和空状态；不在各页面另设色板或照抄概念图中的未知数据。
- 项目处于开发阶段，只实现产品约定中定义的标识、目录、命令与格式。标识或格式变更直接更新实现与测试，不建立版本适配层；文档只描述当前行为。
- 应用不调用云端 AI API、不自动发送 Agent 任务。交接只准备独立副本并请求打开客户端；用户在目标应用确认发送，不以打开成功代表已读取或分析完成。
- 一次修改聚焦明确问题；相关行为、规范或限制变化同步文档，不顺手改动无关文件。

## 验证与交付

- 核心行为修改运行 `bash scripts/test.sh`；App 状态或交互修改运行 `bash scripts/test-app.sh`；需要完整 App 验证时运行 `bash scripts/build.sh`。没有 SwiftPM test target，`swift build` 只构建核心库和 CLI。
- UI 修改使用隔离路径和虚构数据，检查浅深色、最小窗口、长内容及关键状态，并按[规范验收清单](docs/spec/global-theme-and-ux.md#112-视觉与交互验收)记录实际结果。构建完成后可用 `scripts/run-ui-isolated.sh` 检查 SwiftUI 主界面。
- 测试失败先处理或明确定位，不继续打包和安装；构建和 CI 不自动安装应用、注册扩展、修改安全设置或发送任务。
- 不提交真实聊天、个人附件、授权书签、密钥、证书、日常资料库、私人绝对路径和构建产物；截图标明虚构数据，新增资源在 [NOTICE](NOTICE.md) 记录来源与许可。
- 提交使用仓库本地的 GitHub noreply 邮箱；公开前检查暂存文件与提交元数据。二进制包附 LICENSE / NOTICE，不携带本机扩展属性。
- 版本与发布相关变更运行 `bash scripts/version.sh check` 和 `bash scripts/test-release.sh`；发布 tag 必须是 main 可达提交的附注 tag，执行 `check-tag` 校验，不移动已推送 tag 或覆写公开包。未实现的自动发布、签名公证与远端规则不得描述为已启用。
- 交付说明写清修改内容、实际验证和未验证项；纯文档修改检查引用与内容一致性，不虚报构建或端到端结果。
