# HEARTBEAT.md — Supervisor 心跳协议（模板）

> **使用方法**：复制到 supervisor workspace 目录，按实际路径调整。
> 参考实现：`/vol1/1000/config/share/openclaw/state/workspace-supervisor/HEARTBEAT.md`

**触发方式**：每小时 cron 触发（systemEvent），注入到 supervisor main session。

## 心跳流程

### Step 1 — 任务健康检查（<5s）

```bash
SCRIPT=/vol1/1000/config/share/openclaw/state/skills/task-manager/scripts/task.sh

# 查活跃任务
bash $SCRIPT list

# 查父子任务树
bash $SCRIPT tree

# 清理僵尸（>3 天未更新）
bash $SCRIPT cleanup --stale-days 3
```

### Step 2 — 异常处理

| 异常类型 | 处理方式 |
|----------|----------|
| 僵尸任务 | `message(action=send)` 推送到群，附 taskId + 描述 + 最后更新时间 |
| blocked 任务 | 通知用户决策，附 blockedReason |
| 父任务 blocked（子任务 fail） | 推送到群，附子任务 ID + 失败原因 |
| 任务数 > 10 | 告警，建议归档 |
| 无异常 | HEARTBEAT_OK（不发消息） |

### Step 3 — Session 探活（每 6 次心跳执行一次）

```bash
sessions_list(activeMinutes=120)
```

对比活跃 session 与活跃任务，发现不匹配时告警。

## 告警消息格式

```
⚠️ 任务监督告警

僵尸任务（>3天未更新）:
- T-20260516-001: 实现XXX | 最后更新: 2天前 | owner: devengineer

需要用户决策:
- T-20260516-002: 等待确认数据库选型

父子任务异常:
- T-20260516-010: 被子任务 T-20260516-011 阻塞 | 原因: 登录接口500
```

## Night Mode (23:00-08:00)

- 只执行 Step 1（健康检查）
- 不推送告警
- HEARTBEAT_OK

## Paths

- 任务目录：`/vol1/1000/config/share/openclaw/state/task/`
- 脚本：`/vol1/1000/config/share/openclaw/state/skills/task-manager/scripts/task.sh`
- Skill：`/vol1/1000/config/share/openclaw/state/skills/task-manager/SKILL.md`
