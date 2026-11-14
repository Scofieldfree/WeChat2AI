# 开发与本机构建

需要 macOS 13+ 和 Apple Command Line Tools。Swift 编译器需支持 Swift 5.9 语法；包声明 `swift-tools-version: 5.9`，脚本按 Swift 5 语言模式编译。当前本机验证环境为 Apple Silicon、macOS 26 和 Apple Swift 6.3.3，其他组合以实际测试为准。

## 命令职责

在仓库根目录运行，每一步失败时停止后续步骤：

```bash
for script in scripts/*.sh; do
  bash -n "$script"
done
bash scripts/version.sh check
bash scripts/test-release.sh
bash scripts/test.sh
bash scripts/test-app.sh
swift build
bash scripts/build.sh
codesign --verify --deep --strict build/WeChat2AI.app
bash scripts/package.sh
```

| 命令 | 行为 |
|---|---|
| `scripts/version.sh` | 检查 / 同步版本及两份 plist，推导 tag / Release 名称，校验 tag 的 main 来源；不推送或发布 |
| `scripts/test-release.sh` | 在专用临时仓库验证版本、构建号、tag 类型及 main 来源边界 |
| `scripts/test.sh` | 编译 WeChat2AICore 和独立测试运行器，执行行为测试；不使用 XCTest |
| `scripts/test-app.sh` | 排除产品 @main 编译独立 App 状态测试，所有路径/偏好/外部操作显式隔离 |
| `scripts/run-ui-isolated.sh` | 创建虚构资料和独立 Bundle ID 的测试宿主，以 SwiftUI 启动，不安装或注册分享扩展 |
| `swift build` | 构建 WeChat2AICore 与唯一 CLI wechat2ai；不生成完整 GUI App |
| `scripts/build.sh` | 构建图标、主 App 与分享扩展，并使用本机 ad-hoc 签名或显式 SIGN_IDENTITY |
| `scripts/package.sh` | 重新构建并生成版本化 ZIP 和 SHA256SUMS；不安装或启动 |
| `scripts/install-local.sh` | 安装到当前用户 Applications，注册扩展并启动应用 |

当前测试没有 SwiftPM test target，不能用 `swift test` 替代 `scripts/test.sh`。SDK、zlib、AppKit、Foundation 和 CryptoKit 均来自系统开发工具，不需要下载第三方 Swift 包。完整 App 构建会重新生成 `build/WeChat2AI.app`，请勿在该输出目录保存个人文件。

## 安装与恢复

准备使用时自行执行 `bash scripts/install-local.sh`。已有安装先退出 App，再加 `--replace`。脚本只接受当前 WeChat2AI 标识，校验名称和签名，并把被替换的 App 备份到 `~/Library/Application Support/WeChat2AI/AppBackups/`。

不要同时安装两份相同 Bundle ID 的应用。源码目录与用户资料分开保存。通过 `WECHAT2AI_APP_SOURCE` 可指定本机构建的 App 来源；脚本在替换前校验名称、标识及签名。

## 测试数据与 CI

[Fixtures](../Tests/Fixtures/README.md) 中只包含虚构数据。测试运行器自行创建临时目录；手工 CLI 验证也需要显式传入独立输出目录，不能指向日常资料库。

GitHub Actions 的 `CI` 使用 `macos-26`，仅响应 main 推送和目标为 main 的 PR；运行语法、版本与发布规则、核心 / App 测试、CLI / App 构建及签名验证，不响应 tag、不安装、不请求生产签名凭据、不发布。Action 固定到已核对的提交。远端仓库与 CI 运行状态在发布前单独验证，本机结果见[验证记录](validation.md)。命名和后续发布流程见[发布规范](release-policy.md)。

## 验证 SwiftUI 主界面

先运行 `bash scripts/test-app.sh` 与 `bash scripts/build.sh`，再运行：

```bash
bash scripts/run-ui-isolated.sh
# 深色与最小窗口：
bash scripts/run-ui-isolated.sh --ui-dark --ui-minimum
```

每次创建 `build/ui-host.*` 虚构资料根目录及对应独立 UserDefaults suite。宿主保留真实文件面板以便手工导入，客户端打开、Finder 和剪贴板替代器不触发日常系统操作。不要用该宿主宣称真实 Agent 或微信分享已验收。

所有启动方式均使用 SwiftUI。生产构建使用用户设置，日常验证优先使用上述隔离脚本。实际检查与尚未验证的范围见[验证记录](validation.md)。

隔离主题场景（均创建新临时资料，不指向日常资料库）：

```bash
bash scripts/run-ui-isolated.sh --ui-wide
bash scripts/run-ui-isolated.sh --ui-minimum --ui-long
bash scripts/run-ui-isolated.sh --ui-dark --ui-empty
bash scripts/run-ui-isolated.sh --ui-library-missing
```

`--ui-long` 提供两个同名长来源、12 个归档批次、200 条虚构消息及长 URL。`--ui-library-missing` 在临时测试根内模拟已保存资料库路径失效。正文读取失败检查需先加载批次，再仅在该临时根中将对应 `transcript.md` 改名备份，切换到其他批次后返回；恢复备份后重新读取。不要在日常资料库执行故障注入。宿主输出实际内容尺寸供核对；窗口截图还会包含系统标题栏高度。实际验收结果见[验证记录](validation.md)。

`--ui-settings` 在后台载入完成后打开四页设置窗口；与其他隔离参数组合使用。隔离宿主缺少 `--ui-test-root` 时直接退出，不读取日常配置。宿主输出实际正文视口尺寸（不含系统标题栏、详情头及交接台），供核对高度预算。实际结果与未验证项见[验证记录](validation.md)。

`--ui-density` 提供 30 条虚构单行消息，可与 `--ui-long` 组合量测阅读密度；`--ui-settings` 另建虚构模板、一个来源默认及未完成接收登记，用于设置列表验证。它们只在显式隔离根内生成。

`--ui-images` 在隔离根内生成自制横图、竖图、透明 PNG、方向标记 JPEG、损坏文件和缺失附件消息，供阅读视图缩略图验收；不使用真实图片。图片预览验证见[验证记录](validation.md)。
