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

## 路径变量（按实际部署替换）

```bash
# 任务目录（存放 active/done/failed 子目录）
TASK_ROOT=/path/to/task

# task.sh 脚本路径
SCRIPT_PATH=/path/to/skills/task-manager/scripts/task.sh

# Supervisor workspace 目录
SUPERVISOR_WORKSPACE=/path/to/workspace-supervisor
```

## 初始化（首次使用）

```bash
# 创建任务目录结构
mkdir -p "$TASK_ROOT"/{active,done,failed}

# 验证脚本可用
bash "$SCRIPT_PATH" help
```

## Supervisor 配置

Supervisor 需要两份文件：`AGENTS.md`（协议解析）和 `HEARTBEAT.md`（心跳巡检）。

### Supervisor AGENTS.md 模板

**模板文件**：`templates/AGENTS-TEMPLATE.md`

使用方法：
```bash
cp templates/AGENTS-TEMPLATE.md "$SUPERVISOR_WORKSPACE/AGENTS.md"
# 编辑文件顶部的变量声明，替换为实际路径
```

### Supervisor HEARTBEAT.md 模板

**模板文件**：`templates/HEARTBEAT-TEMPLATE.md`

使用方法：
```bash
cp templates/HEARTBEAT-TEMPLATE.md "$SUPERVISOR_WORKSPACE/HEARTBEAT.md"
# 编辑文件顶部的变量声明，替换为实际路径
```

## 心跳配置

Supervisor 的心跳由 OpenClaw 内置心跳机制触发（配置级别），**不需要手动创建 cron**。

需要确保两件事：

### 1. Supervisor 的 HEARTBEAT.md 存在

按上方 Supervisor HEARTBEAT.md 模板步骤操作即可。

### 2. OpenClaw 配置文件启用心跳

在 supervisor agent 的配置中确保存在 `heartbeat` 配置项，例如：

```json
{
  "agents": {
    "supervisor": {
      "heartbeat": {
        "enabled": true,
        "intervalMs": 3600000
      }
    }
  }
}
```

验证：
```bash
# 检查 supervisor 配置中有 heartbeat 设置
openclaw config get agents.supervisor.heartbeat
```

## 安装验证清单

部署完成后，执行以下检查确认体系正常：

```bash
# 1. 脚本可用
bash "$SCRIPT_PATH" help

# 2. 目录结构正确
ls "$TASK_ROOT"/{active,done,failed}

# 3. 创建+完成全流程
bash "$SCRIPT_PATH" create "安装验证测试" --agent test
T=$(bash "$SCRIPT_PATH" list --format json | grep -o '"taskId":"[^"]*"' | tail -1 | cut -d'"' -f4)
bash "$SCRIPT_PATH" verify "$T" --result pass
bash "$SCRIPT_PATH" complete "$T"

# 4. 父子任务
P=$(bash "$SCRIPT_PATH" create "父任务验证" --agent test | grep -o '"taskId":"[^"]*"' | cut -d'"' -f4)
bash "$SCRIPT_PATH" create "子任务验证" --agent test --parent "$P"
bash "$SCRIPT_PATH" tree
bash "$SCRIPT_PATH" fail "$P" "cleanup"

# 5. Supervisor 心跳配置（HEARTBEAT.md + config heartbeat）
[ -f "$SUPERVISOR_WORKSPACE/HEARTBEAT.md" ] && echo "HEARTBEAT.md ✅" || echo "HEARTBEAT.md ❌"

# 6. Supervisor AGENTS.md 协议前缀
grep "task-manager" "$SUPERVISOR_WORKSPACE/AGENTS.md"

# 7. Supervisor HEARTBEAT.md tree 命令
grep "tree" "$SUPERVISOR_WORKSPACE/HEARTBEAT.md"

echo "✅ 安装验证通过"
```

## GitHub Actions CI（可选）

将 CI 配置复制到仓库根目录即可启用自动测试：

```bash
mkdir -p .github/workflows
cp references/ci/smoke-test.yml .github/workflows/
git add .github/workflows/smoke-test.yml
git commit -m "ci: add smoke test workflow"
git push
```

**注意**：推送 `.github/workflows/` 需要 GitHub token 具备 `workflow` scope。

## 迁移指引（从旧版 task-management）

1. **删除旧 skill 目录**：`rm -rf skills/task-management/`
2. **更新引用**：所有 `task-management` → `task-manager`（grep 检查 AGENTS.md、HEARTBEAT.md）
3. **验证**：执行上方安装验证清单
