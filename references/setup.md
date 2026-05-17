# Setup — Task Manager 安装与部署

## 目录结构

```
skills/task-manager/
├── SKILL.md              # 核心技能文件
├── README.md             # 人类可读概览
├── scripts/
│   └── task.sh           # 统一脚本
├── templates/
│   └── SPEC-TEMPLATE.md  # SPEC.md 模板
├── references/
│   ├── setup.md          # 本文件：安装部署
│   ├── spec-format.md    # SPEC.md 格式参考
│   └── anti-patterns.md  # 反模式详解
└── log/
    └── CHANGELOG.md      # 版本日志
```

## 初始化（首次使用）

```bash
# 创建任务目录结构
mkdir -p /vol1/1000/config/share/openclaw/state/task/{active,done,failed}

# 验证脚本可用
bash /vol1/1000/config/share/openclaw/state/skills/task-manager/scripts/task.sh help
```

## Supervisor 配置

Supervisor 需要两份文件：`AGENTS.md`（协议解析）和 `HEARTBEAT.md`（心跳巡检）。

### Supervisor AGENTS.md 模板

**模板文件**：`templates/AGENTS-TEMPLATE.md`
**实际配置参考**：`/vol1/1000/config/share/openclaw/state/workspace-supervisor/AGENTS.md`

使用方法：复制模板文件到 supervisor workspace 目录，改名为 `AGENTS.md`，按实际路径调整。

### Supervisor HEARTBEAT.md 模板

**模板文件**：`templates/HEARTBEAT-TEMPLATE.md`
**实际配置参考**：`/vol1/1000/config/share/openclaw/state/workspace-supervisor/HEARTBEAT.md`

使用方法：复制模板文件到 supervisor workspace 目录，改名为 `HEARTBEAT.md`，按实际路径调整。

## Cron 配置

Supervisor 需要每小时 cron 触发心跳：

```bash
# 创建 supervisor 心跳 cron
openclaw cron create --name "supervisor-heartbeat" \
  --schedule '{"kind":"every","everyMs":3600000}' \
  --payload '{"kind":"systemEvent","agentId":"supervisor","text":"[heartbeat] 巡检"}' \
  --sessionTarget 'last'
```

**关键参数：**
- `agentId: supervisor` — 确保注入 supervisor agent
- `sessionTarget: last` — 复用 supervisor 最近的 session
- `everyMs: 3600000` — 每小时
- payload 必须含 `[heartbeat]` 关键词，触发 HEARTBEAT.md 流程

### Cron 验证

```bash
# 确认 cron 存在且 enabled
openclaw cron list

# 手动触发一次验证
openclaw cron run <cronId>

# 查看运行日志
openclaw cron list-runs --cron-id <cronId> --limit 5
```

## 安装验证清单

部署完成后，执行以下检查确认体系正常：

```bash
SCRIPT=/vol1/1000/config/share/openclaw/state/skills/task-manager/scripts/task.sh

# 1. 脚本可用
bash $SCRIPT help

# 2. 目录结构正确
ls /vol1/1000/config/share/openclaw/state/task/{active,done,failed}

# 3. 创建+完成全流程
bash $SCRIPT create "安装验证测试" --agent test
T=$(bash $SCRIPT list --format json | grep -o '"taskId":"[^"]*"' | tail -1 | cut -d'"' -f4)
bash $SCRIPT verify "$T" --result pass
bash $SCRIPT complete "$T"

# 4. 父子任务
P=$(bash $SCRIPT create "父任务验证" --agent test | grep -o '"taskId":"[^"]*"' | cut -d'"' -f4)
bash $SCRIPT create "子任务验证" --agent test --parent "$P"
bash $SCRIPT tree
bash $SCRIPT fail "$P" "cleanup"

# 5. Supervisor 心跳 cron
openclaw cron list | grep supervisor

# 6. Supervisor AGENTS.md 协议前缀
grep "task-manager" /vol1/1000/config/share/openclaw/state/workspace-supervisor/AGENTS.md

# 7. Supervisor HEARTBEAT.md tree 命令
grep "tree" /vol1/1000/config/share/openclaw/state/workspace-supervisor/HEARTBEAT.md

echo "✅ 安装验证通过"
```

## 迁移指引（从旧版 task-management）

1. **删除旧 skill 目录**：`rm -rf skills/task-management/`
2. **更新引用**：所有 `task-management` → `task-manager`（grep 检查 AGENTS.md、HEARTBEAT.md）
3. **旧 cron 处理**：删除旧 cron，按上方 Cron 配置新建
4. **验证**：执行上方安装验证清单
