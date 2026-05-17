# SPEC.md 格式参考

## 字段说明

```markdown
# T-20260516-001: 实现 XXX 功能

## 元信息
- **taskId**: T-20260516-001
- **status**: running | blocked | done | failed
- **priority**: low | normal | high
- **owner**: devengineer
- **created**: 2026-05-16T18:30:00+08:00
- **updated**: 2026-05-16T19:00:00+08:00
- **blockedReason**: （仅 blocked 时填写）
- **verified**: pass | fail | （未验证留空）
- **parent**: T-20260516-000 （父任务 ID，根任务无此字段）
- **children**: T-20260516-002,T-20260516-003 （子任务 ID 列表）

## 目标
一句话描述要完成什么。

## 验收标准
- [ ] 条件 1
- [ ] 条件 2

## 执行计划
- [x] Step 1: 已完成
- [ ] Step 2: 进行中
- [ ] Step 3: 待做

## 上下文
- **sourceRepo**: /vol1/1000/config/share/projects/xxx
- **branch**: feat/xxx
- **worktree**: /tmp/acp-cache/xxx
- **relatedSessions**: agent:devengineer:telegram:group:xxx

## 恢复信息
- **lastStep**: Step 2 编码完成
- **nextAction**: Step 3 测试验证
- **blockers**: 无
- **dependencies**: 无

## 决策记录
| 时间 | 决策 | 理由 |
|------|------|------|

## 日志摘要
- 2026-05-16T18:30 — 任务创建
- 2026-05-16T19:00 — Step 1 完成
```

## 状态流转

```
running ──→ blocked ──→ running ──→ done
   │                        │
   ├──→ failed              └──→ done (verify pass 后)
   │
   └──→ done (--force，跳过 verify)
```

- `running → done`：需先 `verify --result pass`，再 `complete`
- `running → blocked`：`block <reason>` 或子任务 fail 自动触发
- `blocked → running`：`unblock`
- `done → running`：`reopen`
- `failed → running`：`reopen`
- 任何状态 → `failed`：`fail <reason>`

## 父子任务 SPEC 差异

父任务的 SPEC.md 包含 `children` 字段（逗号分隔的子任务 ID 列表）。
子任务的 SPEC.md 包含 `parent` 字段（父任务 ID）。

```bash
# 创建子任务时自动注册到父任务的 children 字段
bash $SCRIPT create "子任务" --agent codex --parent T-20260517-010
```

## 恢复机制

`resume` 命令解析 SPEC.md 中的恢复信息，输出：

```
Task: T-20260516-001
Status: running | Priority: high | Owner: devengineer
Last Step: Step 2 完成
Next Action: 继续 Step 3 测试
Pending Steps:
- [ ] Step 3: 测试验证
- [ ] Step 4: 部署上线
Recent Log:
- 2026-05-16T19:00 — Step 2 完成
- 2026-05-16T18:30 — Step 1 完成
```

Agent 读取 `resume` 输出即可从断点继续执行，不需要记忆之前的对话。
