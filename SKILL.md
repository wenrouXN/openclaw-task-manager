---
name: task-manager
description: >
  全局任务生命周期管理系统。强制规则：收到多步任务（≥3 步）时，必须先用 task-manager
  创建任务再执行，不允许裸跑。用于：(1) 多步骤任务的创建、规划、执行、验证、完成；
  (2) 父子任务编排与生命周期联动；(3) 跨 session 断点恢复；(4) 并发安全的任务交接；
  (5) 僵尸任务清理与巡检。当任务 ≥3 步、预计 >5 分钟、需要 spawn/ACP、涉及 repo/config/cron
  变更、或用户要求跟踪时触发。触发词：任务、跟踪、记录、落盘、task、plan。
---

# Task Manager — 全局任务生命周期管理

> 任务目录：`$TASK_ROOT`（配置环境变量，或在脚本中硬编码）
> 脚本：本 skill 的 `scripts/task.sh`
> 详细文档：`references/` 目录

---

## ⚠️ 强制规则（读到此 skill 即生效）

以下规则无需用户提醒，skill 被加载后自动约束 agent 行为：

1. **多步任务必须落盘**：≥3 步的任务 → 先 `create` + `plan`，再执行。裸跑是 bug。
2. **执行中更新进度**：每完成一个步骤 → `update --step`。不是做完再补。
3. **验证前不许 complete**：`verify pass` 是 complete 的前置条件（`--force` 除外）。
4. **失败要记录**：`fail` 时必须写 reason，不能静默放弃。
5. **跨 session 要恢复**：新 session 接手 → 先 `resume`，不要凭记忆做事。

违反以上规则 = bug，可在自迭代协议中修补。

---

## 预检门控

**读到此 skill 后、执行任何操作前，必须完成预检。**

### 触发条件（命中任一即需落盘）

| 条件 | 判断标准 |
|------|----------|
| 多步骤 | ≥ 3 步 |
| 耗时 | > 5 分钟，或可能跨 session |
| handoff | 需要 spawn / ACP / 子 agent |
| 外部变更 | 涉及 repo、config、deploy、cron、文件删除 |
| 用户要求 | 用户说"跟踪"、"记录"、"任务" |
| 诊断+修复 | 先排查问题再修复 |
| 需要验证 | 改完需要验证才知是否成功 |

### 自检（第一个实质性操作前）

```
□ ≥3 步？ □ 改 repo/config/cron？ □ 需 spawn/ACP？
□ 用户要求跟踪？ □ >5 分钟？ □ 诊断+修复？ □ 需验证？
```

**任一勾选 → 立即 create + plan，不要继续。**

> 反模式详解与事后补录规范：见 `references/anti-patterns.md`

---

## 快速开始

```bash
SCRIPT=/path/to/skills/task-manager/scripts/task.sh  # 按实际路径替换

# 创建任务
sessions_spawn(
    task="[task-manager] create: <描述> | agent:<agentId> | priority:<normal|high|low> | session:<sessionKey>",
    runtime="subagent", agentId="supervisor")

# 直接用脚本查询（不经过 supervisor）
bash $SCRIPT list --format table          # 活跃任务
bash $SCRIPT list-done --limit 5          # 已完成
bash $SCRIPT resume T-xxx --format table  # 断点恢复
bash $SCRIPT orphans 24                   # 僵尸扫描
```

---

## 交互协议

消息格式：`[task-manager] <command>: <value> | <key>: <value> | ...`

### 父子任务

```bash
bash $SCRIPT create "子任务" --agent <id> --parent <parentId>
bash $SCRIPT tree [--agent <id>]
```

**生命周期联动：**
- 父任务 `complete` 前，所有子任务必须 `done`（`--force` 跳过）
- 子任务 `fail` → 父任务自动 `blocked`（reason 包含子任务 ID）
- 父任务 `unblock` 后可继续推进

### 命令速查

| 命令 | 说明 | 关键参数 |
|------|------|----------|
| `create` | 创建任务 | `--agent`, `--priority`, `--session`, `--parent` |
| `update` | 更新进展 | `--step`, `--last-step`, `--next-action`, `--status` |
| `plan` | 设置执行计划 | `--steps "step1,step2,..."` |
| `verify` | 验证结果 | `--result pass/fail`, `--issues` |
| `complete` | 完成（需先 verify） | `--force` 跳过验证 |
| `reopen` | 重新打开（done→running） | — |
| `revise` | 验证失败后追加修复 | `--findings "fix1,fix2"` |
| `fail` | 标记失败 | 第二参数为 reason |
| `block` | 阻塞 | 第二参数为 reason |
| `unblock` | 解除阻塞 | — |
| `list` | 查询活跃任务 | `--status`, `--agent`, `--format table/json` |
| `list-done` | 查询已完成 | `--limit`, `--agent` |
| `status` | 单任务详情 | `--format table/json` |
| `resume` | 恢复信息（断点续做） | `--format table/json` |
| `tree` | 树形展示父子任务 | `--agent` |
| `claim` | 认领任务 | `--agent`, `--session` |
| `takeover` | 强制接管 | `--agent`, `--session` |
| `orphans` | 僵尸扫描 | 参数为小时数（默认 24） |
| `cleanup` | 清理僵尸 | `--stale-days 3` |
| `rebuild-index` | 重建索引 | — |

---

## 恢复机制

`resume` 命令解析 SPEC.md，输出上次进度 + 待办步骤。Agent 读取即可从断点继续，不需要记忆之前的对话。

```bash
bash $SCRIPT resume T-20260516-001 --format table
```

---

## 常见场景

### 场景 1：完整编排（create → plan → execute → verify → done）

```bash
bash $SCRIPT create "实现用户认证" --agent devengineer --priority high
bash $SCRIPT plan T-xxx --steps "设计数据模型,实现登录,编写测试,部署"
bash $SCRIPT update T-xxx --step "Step 1 完成" --last-step "设计数据模型"
bash $SCRIPT verify T-xxx --result pass
bash $SCRIPT complete T-xxx
```

### 场景 2：验证失败 → 修订 → 重新验证

```bash
bash $SCRIPT verify T-xxx --result fail --issues "登录接口500,注册缺邮箱验证"
bash $SCRIPT revise T-xxx --findings "修复登录500,添加邮箱验证"
# 执行修复 ...
bash $SCRIPT verify T-xxx --result pass
bash $SCRIPT complete T-xxx
```

### 场景 3：新 session 恢复旧任务

```bash
bash $SCRIPT resume T-xxx --format table
# → 读取输出，从 lastStep 继续执行
```

### 场景 4：父子任务编排

```bash
bash $SCRIPT create "认证模块" --agent devengineer --priority high
bash $SCRIPT create "登录接口" --agent codex --parent T-xxx
bash $SCRIPT create "认证测试" --agent devengineer --parent T-xxx
bash $SCRIPT tree
# 子任务 fail → 父自动 blocked
bash $SCRIPT fail T-child "接口500"
bash $SCRIPT status T-parent  # → Blocked: child T-child failed
```

### 场景 5：跳过验证直接完成

```bash
bash $SCRIPT complete T-xxx --force
```

---

## FAQ

**Q: 小任务需要创建任务吗？** → 不需要。单步操作、快速查询不落盘。
**Q: 能直接编辑 SPEC.md 吗？** → 推荐通过 supervisor 或脚本操作，保证格式一致。
**Q: 跨 session 怎么恢复？** → 用 `resume` 命令获取上次进度。
**Q: 多 agent 同时操作一个任务？** → flock 文件锁 + claim 冲突检测保护。
**Q: 如何转交任务？** → `claim --agent newAgent --session newSession`；冲突时用 `takeover`。
**Q: owner 挂了？** → `orphans 24` 扫描 + `takeover` 接管。

---

## 自迭代协议

**skill 是活文档。** 执行中发现缺陷（规则不明确、护栏缺失、流程有漏洞），应就地修补 SKILL.md。

### 触发条件

| 场景 | 示例 |
|------|------|
| 规则未被执行 | skill 写了"必须落盘"但 agent 跳过了 |
| 执行中发现遗漏 | 某个前置检查没写进 skill |
| 失败模式未被覆盖 | FAQ 没有回答的问题 |
| 用户纠正 | 用户指出 agent 应该做但没做的事 |

### 迭代流程

1. 发现缺陷 → 用 edit 直接修补 SKILL.md
2. 如涉及反模式 → 更新 `references/anti-patterns.md`（带真实案例）
3. 如涉及安装 → 更新 `references/setup.md`
4. 改动说明 → 在 CHANGELOG.md 记录

### 改动原则

- **最小变更**：只改需要改的部分
- **可操作**：新增规则必须有明确判断标准和执行动作
- **有案例**：反模式必须包含真实失败案例
- **不重复**：全局 AGENTS.md 已有的规则，skill 只引用不复制

---

## 安装部署

> 详见 `references/setup.md`，包含：
> - Supervisor AGENTS.md / HEARTBEAT.md 完整模板
> - Cron 配置命令与验证
> - 安装验证清单（7 步端到端验证）
> - 从旧版 task-management 迁移指引

## SPEC.md 格式

> 详见 `references/spec-format.md`，包含：
> - 完整字段说明
> - 状态流转图
> - 父子任务 SPEC 差异
> - 恢复机制详解
