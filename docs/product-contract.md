# 产品标识与数据边界

适用版本：WeChat2AI 0.1.0 / build 1。本文定义产品身份、保存位置和数据操作边界。

## 当前标识

| 项目 | 当前值 |
| --- | --- |
| 产品与 App | `WeChat2AI`、`WeChat2AI.app` |
| 主 App Bundle ID | `local.scofield.wechat2ai` |
| 分享扩展 ID | `local.scofield.wechat2ai.share` |
| 接收包 UTI | `local.scofield.wechat2ai.drop` |
| 接收包后缀 | `.w2adrop` |
| 可执行文件 | `WeChat2AI`、`WeChat2AIShare` |
| CLI | 仅 `wechat2ai` |
| 应用数据 | `~/Library/Application Support/WeChat2AI/` |
| 默认资料库 | `~/Library/Application Support/WeChat2AI/Library/` |
| 核心导入器默认输出根 | `~/Library/Application Support/WeChat2AI/Imports/` |
| Agent 项目与交接副本 | `~/WeChat2AI/Projects/`、`~/WeChat2AI/Handoffs/` |
| 接收文件夹 | 用户选择位置下的 `WeChat2AI Receipts` |

数据位置由 `StoragePaths` 与 `AgentWorkspace` 定义。主界面显示当前资料库中的待分类、群聊和私聊来源。App 设置与分享扩展授权分别保存在各自 Bundle ID 的偏好域中。

默认资料库在首次启动时自动创建；项目和交接目录按需创建。导入由用户明确选择文件或连接接收目录触发。

## 数据操作

当前资料库使用明确的格式版本、固定 ID、原文散列及相对附件路径。未知版本、损坏、越界、符号链接、锁冲突或缺失目录必须报告错误，不创建空资料替代，也不回退到其他目录。

导入暂存、文件锁、归档操作日志、接收回执和中断恢复用于保证数据操作的完整性。

改归与资料库切换不移动已经生成的 Agent 副本；删除一份资料不会自动清理其他副本。模板、原文、图片和交接的实际保存范围见[数据格式](data-format.md)和[隐私说明](../PRIVACY.md)。

## 平台与外部客户端

主界面使用 SwiftUI，AppKit 负责系统窗口、原生面板与正文桥接。最低系统为 macOS 13；实际实机与辅助功能覆盖以[验证记录](validation.md)为准。

Codex 与 Claude 的深链需要随对应客户端版本验证。应用不调用云端 AI API，不自动发送任务；打开请求成功不代表已经获得文件权限、读取资料或完成分析。Code 与 Cowork 可以使用同一群项目目录，但不保证共用会话。
