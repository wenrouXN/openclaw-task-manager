# T-{YYYYMMDD}-{NNN}: {标题}

## 元信息
- **taskId**: T-{YYYYMMDD}-{NNN}
- **status**: running | blocked | done | failed
- **priority**: low | normal | high
- **owner**: {agentId}
- **created**: {ISO-8601}
- **updated**: {ISO-8601}
- **blockedReason**: （仅 blocked 时填写）
- **verified**: pass | fail | （未验证留空）
- **parent**: （父任务 ID，根任务无此字段）
- **children**: （子任务 ID 列表，逗号分隔，无子任务留空）

## 目标
一句话描述要完成什么。

## 验收标准
- [ ] 条件 1
- [ ] 条件 2

## 执行计划
- [ ] Step 1: 待做
- [ ] Step 2: 待做
- [ ] Step 3: 待做

## 上下文
- **sourceRepo**: （如有）
- **branch**: （如有）
- **worktree**: （如有）
- **relatedSessions**: （如有）

## 决策记录
| 时间 | 决策 | 理由 |
|------|------|------|

## 日志摘要
（关键节点记录，详细日志见 log.md）
