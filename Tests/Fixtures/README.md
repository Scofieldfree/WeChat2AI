# 虚构测试资料

本目录内容全部虚构，允许随项目按 MIT 许可证使用，不含真实聊天或用户附件。

- `text/聊天记录.txt`：中文文件名、多行消息、三条虚构对话。
- `attachments/Chat History.txt`：两条虚构消息，一条关联同目录的自制文本附件。
- `attachments/演示附件.txt`：仅用于验证附件完整性，不含业务资料。

从仓库根目录运行 CLI 时显式指定临时输出位置，例如：

```bash
swift build
TASK_OUTPUT=$(mktemp -d)
.build/debug/wechat2ai Tests/Fixtures/text/聊天记录.txt "$TASK_OUTPUT/text"
.build/debug/wechat2ai Tests/Fixtures/attachments "$TASK_OUTPUT/attachments"
```

ZIP、非法路径 ZIP 和输出校验在隔离验证时临时生成，不提交压缩包或生成资料库。核心测试运行器也会在自己的临时目录中生成输入。
