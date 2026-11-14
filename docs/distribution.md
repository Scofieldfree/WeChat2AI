# 打包与分发

当前仅提供源码构建流程及本机测试包准备方式，未创建独立仓库的公开 Release。

main 来源限制、版本号、构建号、tag、Release 标题及文件名统一遵循[版本命名与发布规范](release-policy.md)。当前只有 CI，尚未启用 tag 自动发布。

```bash
bash scripts/package.sh
```

该命令按本机架构生成 `build/WeChat2AI.app`，在 `build/releases/` 的独立子目录内生成带完整版本、build 和架构的 ZIP 及 SHA256SUMS。它不会安装 App、注册扩展或启动应用。构建会先替换 `build/WeChat2AI.app`，避免残留文件混入；仅影响该生成目录。App 与扩展均附 LICENSE / NOTICE，ZIP 不保留资源分叉、扩展属性或隔离标记。版本以根目录 `version.json` 为准，构建前核对两份 plist；当前为 0.1.0 / build 1。预发布包名包含 `-beta.N` 等后缀，包内 Apple 数字版本只保留三段数字。

## 当前签名边界

默认 ad-hoc 签名用于本地构建结构校验，没有 Developer ID 身份或 Apple 公证。`SIGN_IDENTITY` 可指定本机证书，但单独设置这个变量不等于完成 hardened runtime、公证和其他机器验收。

分享扩展随主 App 分发，不能作为独立应用安装。最低目标是 macOS 13，现阶段仅 Apple Silicon 实测；不能根据交叉编译成功就宣称 Intel 可用。

## 公开前

1. 核对 [LICENSE](../LICENSE)、[NOTICE](../NOTICE.md) 和源码公开范围；保持私人漏洞报告入口可用，并同步 [SECURITY](../SECURITY.md)。
2. 在远端运行 CI；核对可复现的源码提交与实际二进制版本，再创建版本 Tag。
3. 明确发布包的架构、最低系统、签名、公证状态和 SHA-256。
4. 在干净测试环境验证下载、首次打开、分享扩展、手动导入和 Agent 读取。
5. 验证 ZIP 的 SHA-256、完整性、LICENSE / NOTICE 及包内签名，不应包含 `__MACOSX/`、私人资料或构建目录。
6. 普通用户分发路线另行配置 Developer ID 和 Apple 公证，源码构建路线继续保留。

对于系统阻止的未公证测试包，采用 Apple 的单应用批准流程；不要要求用户关闭 Gatekeeper 或清除全局安全限制。具体行为见 [Apple 安全打开 Mac App](https://support.apple.com/102445)，正式站外分发要求见 [Apple macOS distribution](https://developer.apple.com/macos/distribution/)。
