# 版本命名与发布规范

main 是唯一发布来源。版本元数据由根目录 [version.json](../version.json) 定义，App 与分享扩展使用一致的数字版本和构建号。

## 当前状态

- 初始开发版本为 `0.1.0` / build `1`，尚未发布。
- 已提供 main 推送及目标为 main 的 PR 检查，以及版本同步、tag 校验、构建和打包脚本。
- 公开仓库、私人漏洞报告渠道、远端 CI 和分支 / tag 保护须在发布前配置并验证。
- 自动发布 workflow、Developer ID 签名与 Apple 公证尚未配置。

## 分支与来源

功能、文档和版本准备在工作分支完成，经目标为 main 的 PR 检查后合并。普通 CI 只响应 main 推送和目标为 main 的 PR，不响应 tag，也不发布安装包。

发布提交必须已合入远端 main。tag 不属于分支；发布 workflow 监听 tag 时，必须取得完整 Git 提交图、tag 及 `origin/main`，切换到 tag 对应提交后执行：

```bash
bash scripts/version.sh check-tag "$RELEASE_TAG" origin/main
```

`RELEASE_TAG` 通过环境变量传入。校验命令要求 tag 是附注 tag、名称与版本文件一致、HEAD 等于 tag 提交、已跟踪源码无修改，且提交可从 `origin/main` 到达。本地演练可传 `main`；发布检查必须使用当次 fetch 的 `origin/main`。

这些检查不会联网、创建 tag 或发布。远端 main 和版本 tag 的保护规则需要单独配置。

## 版本和构建号

```json
{
  "version": "0.1.0",
  "build": 1
}
```

| 字段 | 规则 |
| --- | --- |
| `version` | `X.Y.Z` 或 `X.Y.Z-alpha.N`、`X.Y.Z-beta.N`、`X.Y.Z-rc.N`；无 `v` 前缀 |
| `build` | JSON 整数，全项目递增，范围 1…9999 |
| `CFBundleShortVersionString` | 去掉预发布后缀后的三段数字版本 |
| `CFBundleVersion` | build 的十进制字符串 |

数字不带多余前导零，预发布序号从 1 开始。不使用日期版本、四段版本或 SemVer `+metadata` 后缀。

- 修复递增 PATCH，新增功能或数据约定调整递增 MINOR；进入新的产品主版本时递增 MAJOR。递增高位时低位归零。
- 开发阶段直接更新产品约定、实现和行为测试，不建立版本适配层。
- 预发布顺序为 `alpha.N → beta.N → rc.N → 正式版本`，按实际需要使用阶段。相同阶段的内容更新须递增序号。
- 每个新的对外版本身份增加 build；切换版本时 build 不归零，不使用日期、随机数或 CI run number 代替。
- 同一 tag 的各架构包共享版本和 build；失败重试不增加 build。
- 未发布工作版本下的日常提交无需逐次改版本；对外发布前集中准备元数据。

更新版本使用统一命令，例如下一工作版本：

```bash
bash scripts/version.sh set 0.1.1-alpha.1 2
bash scripts/version.sh check
```

该命令同步 JSON 与两份 plist，拒绝改变版本身份时保持或降低 build。三份文件一起提交，不手工分开修改。

## 名称

| 对象 | 固定格式 | 初始版本示例 |
| --- | --- | --- |
| 产品 / App | `WeChat2AI` / `WeChat2AI.app` | 产品名不带版本、架构或昵称 |
| Git tag | `v<完整版本>` | `v0.1.0` |
| Release 标题 | `WeChat2AI v<完整版本>` | `WeChat2AI v0.1.0` |
| ZIP | `WeChat2AI-<完整版本>-build<build>-<架构>.zip` | `WeChat2AI-0.1.0-build1-arm64.zip` |
| 校验文件 | `SHA256SUMS.txt` | 覆盖实际分发的所有包 |
| 版本准备提交 | `chore(release): v<完整版本> (build <build>)` | `chore(release): v0.1.0 (build 1)` |

架构使用 `arm64`、`x86_64`。只有 App、扩展均含两种架构且完成验收后才能使用 `universal`；当前仅实测 arm64。预发布使用 GitHub Pre-release，不能标为最新正式版。DMG 和发布清单仅在对应流程实现后提供。

产品标识、命令、资源和数据路径遵循[产品约定](product-contract.md)。

## 发布步骤

1. 更新版本、CHANGELOG、README、用户指南及分发说明，执行版本检查与适当的行为验证。
2. 提交版本准备 PR，等待检查通过并合入 main。
3. 获取最新远端 main，在已审核的源码提交创建附注 tag，执行 `check-tag` 校验；仅推送这个 tag。
4. 在 tag 对应源码构建包，核对版本、架构、签名、许可证、包内容及 SHA-256。
5. 按[分发说明](distribution.md)完成首次运行与端到端验收后再发布。

已推送的版本 tag 不移动或复用，已公开的安装包不覆盖；更改产物时准备新的版本身份。构建与 CI 不安装应用、注册分享扩展、修改系统安全设置或发送 Agent 任务。
