# HEARTBEAT.md — Supervisor 心跳协议（模板）

> **使用方法**：复制到 supervisor workspace 目录，按实际路径调整下方变量。

<!-- 按实际部署路径替换以下变量 -->
<!-- 
SCRIPT_PATH=/vol1/1000/config/share/openclaw/state/skills/task-manager/scripts/task.sh
SKILL_PATH=/vol1/1000/config/share/openclaw/state/skills/task-manager/SKILL.md
-->

**触发方式**：OpenClaw 内置心跳机制触发（配置 heartbeat），注入到 supervisor main session。

## 心跳流程

### Step 1 — 任务健康检查（<5s）

```bash
SCRIPT="$SCRIPT_PATH"

# 查活跃任务
bash $SCRIPT list

# 查父子任务树
bash $SCRIPT tree

# 清理僵尸（>3 天未更新）
bash $SCRIPT cleanup --stale-days 3
```

### Step 2 — 任务推进与裸跑检测

**职责**：主动推进停滞任务，识别裸跑 session，提醒需要决策的任务。

#### 2.1 数据收集

```bash
# 活跃任务（JSON）
TASKS=$(bash $SCRIPT list --format json 2>/dev/null)

# 活跃 sessions（含最近消息）
sessions_list(activeMinutes=120, includeLastMessage=true)
```

#### 2.2 停滞任务推进

遍历活跃任务，对比任务 owner 与活跃 session：

| 状态 | 判断条件 | 处理 |
|------|----------|------|
| **blocked + needsDecision** | `needsDecision=true` + `blockedReason` | `message(action=send)` 提醒用户决策，附 taskId + blockedReason |
| **blocked + 子任务 fail** | blockedReason 含子任务 ID | `message(action=send)` 提醒用户，附子任务失败原因 |
| **running + owner session 活跃** | 任务 `updatedAt` > 30min + session 最近消息是 assistant 且含问句 | `sessions_send` 轻推 agent："任务 T-xxx 停滞 30min+，上次你问了问题但没继续，请推进或告知是否需要用户决策" |
| **running + owner session 活跃 + 用户已回复** | session 最近消息是 user | `sessions_send` 轻推 agent："用户已回复，请继续推进任务 T-xxx" |
| **running + owner session 不活跃** | session 无活跃记录 | 不处理，等 agent 下次 session 自动 `resume` |
| **running + 刚创建 <15min** | `createdAt` 近期 | 不处理，给 agent 执行时间 |

**关键原则**：
- `sessions_send` 是**非阻塞**的（不等回复），不会中断 agent 当前工作
- 推送消息带 `[task-manager]` 前缀，agent 按 HEARTBEAT.md 协议响应
- 用户决策提醒走 `message(action=send)` 直接推送到聊天渠道

#### 2.3 裸跑检测

```bash
# 对比：有活跃 session 的 agent vs 有活跃任务的 agent
# 差集 = 可能裸跑的 agent
```

判断逻辑：
- agent 有活跃 session 但**无活跃任务** → 检查 session 最近消息
- 最近消息含多步特征（"第一步"、"然后"、"接下来"、"修改"、"部署"、"测试"、"先...再..."）→ 高概率裸跑
- `sessions_send` 提醒："检测到疑似多步任务未落盘，请创建任务跟踪（不要中断当前工作，创建即可）"
- 最近消息是简单问答（<2 步）→ 不提醒

#### 2.4 汇总决策

所有异常收集完毕后，按优先级处理：
1. 需要用户决策的 blocked 任务 → 推送用户
2. 停滞的 running 任务 → 推送 agent
3. 裸跑 session → 提醒 agent（不中断）
4. 无异常 → HEARTBEAT_OK

### Step 3 — 异常处理汇总

| 异常类型 | 处理方式 | 推送渠道 |
|----------|----------|----------|
| blocked + needsDecision | 提醒用户决策，附 taskId + blockedReason | `message(action=send)` |
| blocked + 子任务 fail | 提醒用户，附子任务失败原因 | `message(action=send)` |
| running + 停滞 >30min + 用户已回复 | 推送 agent 继续 | `sessions_send` |
| running + 停滞 >30min + agent 问了问题 | 推送 agent 继续或说明需要决策 | `sessions_send` |
| 裸跑多步任务 | 提醒 agent 创建任务（不中断） | `sessions_send` |
| 僵尸任务（>3天） | 推送到群，附 taskId + 描述 + 最后更新时间 | `message(action=send)` |
| 任务数 > 10 | 告警，建议归档 | `message(action=send)` |
| 无异常 | HEARTBEAT_OK | — |

### Step 4 — Session 探活（每 6 次心跳执行一次）

```bash
sessions_list(activeMinutes=120)
```

对比活跃 session 与活跃任务，发现不匹配时告警。

## 告警消息格式

### 用户决策提醒
```
⚠️ 任务需要决策

T-20260517-003: 实现用户认证
原因: 等待确认数据库选型（MySQL vs PostgreSQL）
停滞时间: 2小时
owner: devengineer

请回复决策，agent 会自动继续。
```

### Agent 推送（停滞任务）
```
[task-manager] 任务 T-20260517-003 停滞 45min。上次你问了用户问题但没继续。请推进，或告知是否需要用户决策。
```

### Agent 推送（用户已回复）
```
[task-manager] 任务 T-20260517-003，用户已回复，请继续推进。
```

### Agent 推送（裸跑提醒）
```
[task-manager] 检测到疑似多步任务未落盘。请创建任务跟踪（不要中断当前工作，创建即可）。
```

### 僵尸/异常告警
```
⚠️ 任务监督告警

僵尸任务（>3天未更新）:
- T-20260516-001: 实现XXX | 最后更新: 2天前 | owner: devengineer

父子任务异常:
- T-20260516-010: 被子任务 T-20260516-011 阻塞 | 原因: 登录接口500
```

## Night Mode (23:00-08:00)

- 只执行 Step 1（健康检查）
- 不推送告警
- HEARTBEAT_OK

## Paths

- 任务目录：`$TASK_ROOT`（含 `active/`、`done/`、`failed/` 子目录）
- 脚本：`$SCRIPT_PATH`
- Skill：`$SKILL_PATH`
