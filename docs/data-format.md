# 本地目录与数据格式

## 资料库

```text
<当前资料库>/
  library.json
  unfiled/<batchID>/
  sources/<创建时名称>-<固定ID>/
    source.json
    batches/<batchID>/
  .staging/
  .operations/
  .writer.lock
```

每个批次包含 `manifest.json`、`messages.jsonl`、`transcript.md` 和 `original/`。manifest 记录版本、来源、统计、警告、时间信息和原文 SHA-256；JSONL 每行一条消息，附件使用相对路径。聊天时间缺少时区时不自动补造，原始时间精度另行保留。

`original/` 保存原始输入及 ZIP 解压内容。来自自动接收的批次另有 `intake-origin.json`，用于幂等和恢复。

默认资料库位于 `~/Library/Application Support/WeChat2AI/Library/`。用户可以选择其他位置，切换不会搬迁原数据。

## 群项目与交接

```text
~/WeChat2AI/
  Projects/<libraryID>/
    bindings.json
    <首次群名>-<短ID>/
      project.json
      README.md
      wechat-imports/<handoffID>/
        manifest.json
        messages.jsonl
        transcript.md
        original/
        handoff.json
        task.json
        context/history/
        context/results/
      results/
  Handoffs/<handoffID>/
```

群项目按资料库与来源固定 ID 绑定，后续交接复用项目，每批仍创建独立副本。未归群批次使用独立 Handoffs。主批次、选定参考、文件校验和范围记录在 handoff.json 与 task.json；不自动扫描整个群历史作为模型上下文。


## 输入限制

文件夹或 ZIP 解压内容限 512 MiB、10,000 项，正文 TXT 限 20 MiB。ZIP 支持 Stored 和 Deflate，拒绝 ZIP64、加密、分卷、重复路径、越界、符号链接和特殊文件，并校验 CRC 与解压长度。一次输入只能有一份可识别聊天正文。

交接复制同样有累计体积和条目限制，接近输入上限的批次可能因包含原 ZIP 与解压文件而无法创建副本，此时保留原批次并报错。

不要手工编辑格式版本、ID、回执、锁或恢复记录。未知版本、损坏及冲突必须明确处理，不用空数据覆盖。跨批次去重、数据库索引和全库导出不属于当前格式承诺。
