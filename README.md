# Task Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

全局任务生命周期管理系统 — OpenClaw 多 agent 协作场景下的任务跟踪、状态管理和断点恢复。

## 特性

- **全生命周期**：create → plan → execute → verify → complete（含 reopen / revise）
- **父子任务**：`--parent` 创建子任务，`tree` 查看层级，生命周期联动
- **验证守卫**：`verify` 必须 pass 才能 `complete`
- **断点恢复**：`resume` 命令获取上次进度，跨 session 无缝续做
- **并发安全**：flock 文件锁 + claim 冲突检测 + takeover 强制接管
- **僵尸清理**：`orphans` 扫描 + `cleanup` 自动归档
- **自迭代**：SKILL.md 内置迭代协议，发现缺陷就地修补

## 快速开始

```bash
# 创建任务
bash scripts/task.sh create "实现用户认证" --agent devengineer --priority high

# 规划步骤
bash scripts/task.sh plan T-20260517-001 --steps "分析需求,编写代码,测试验证,部署"

# 执行 + 更新
bash scripts/task.sh update T-20260517-001 --step "Step 1 完成" --last-step "分析需求"

# 验证 + 完成
bash scripts/task.sh verify T-20260517-001 --result pass
bash scripts/task.sh complete T-20260517-001

# 父子任务
bash scripts/task.sh create "认证模块" --agent devengineer
bash scripts/task.sh create "登录接口" --agent codex --parent T-xxx
bash scripts/task.sh tree

# 断点恢复
bash scripts/task.sh resume T-20260517-001 --format table
```

## 文件结构

```
task-manager/
├── SKILL.md                 # 核心技能（预检 + 协议 + 场景 + FAQ + 自迭代）
├── README.md                # 本文件
├── scripts/
│   └── task.sh              # 统一脚本（所有操作入口）
├── templates/
│   ├── SPEC-TEMPLATE.md     # SPEC.md 模板
│   ├── AGENTS-TEMPLATE.md   # Supervisor AGENTS.md 模板
│   └── HEARTBEAT-TEMPLATE.md # Supervisor HEARTBEAT.md 模板
├── references/
│   ├── setup.md             # 安装部署（Supervisor 配置、Cron、验证清单）
│   ├── spec-format.md       # SPEC.md 格式参考（字段说明、状态流转）
│   └── anti-patterns.md     # 反模式详解（4 个已验证失败模式）
└── log/
    └── CHANGELOG.md         # 版本日志
```

## 安装

```bash
# 1. 初始化目录
mkdir -p /path/to/task/{active,done,failed}

# 2. 验证脚本
bash scripts/task.sh help

# 3. 部署 Supervisor（复制模板）
cp templates/AGENTS-TEMPLATE.md /path/to/supervisor-workspace/AGENTS.md
cp templates/HEARTBEAT-TEMPLATE.md /path/to/supervisor-workspace/HEARTBEAT.md

# 4. 配置心跳（在 OpenClaw 配置中为 supervisor 启用 heartbeat）
#   agents.supervisor.heartbeat.enabled = true, intervalMs = 3600000
```

详见 [references/setup.md](references/setup.md)。

## 文档

| 文档 | 用途 |
|------|------|
| [SKILL.md](SKILL.md) | 核心协议（每次使用必读） |
| [references/setup.md](references/setup.md) | 安装部署 + Supervisor 配置 |
| [references/spec-format.md](references/spec-format.md) | SPEC.md 字段 + 状态流转 |
| [references/anti-patterns.md](references/anti-patterns.md) | 反模式 + 自检清单 |
| [log/CHANGELOG.md](log/CHANGELOG.md) | 版本变更记录 |

## 许可

MIT
