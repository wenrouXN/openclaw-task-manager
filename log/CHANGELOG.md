# CHANGELOG — Task Manager

## v2.1.4 — 2026-05-17

### 修复
- **强制规则注入**：SKILL.md 顶部新增 `⚠️ 强制规则` 段，skill 被加载即生效，无需每个 agent 改 AGENTS.md
- **裸跑检测**：HEARTBEAT-TEMPLATE 新增 Step 2，supervisor 心跳可识别“agent 在裸跑多步任务”并主动提醒

### 变更
- frontmatter description 强化：明确“≥3 步必须先 create 再执行”
- SKILL.md 新增 5 条强制规则（落盘、更新进度、验证、失败记录、跨 session 恢复）
- HEARTBEAT-TEMPLATE 拆分为 4 步（原 Step 2/3 变为 Step 3/4）

## v2.1.3 — 2026-05-17

### 修复
- **list-done 退出码 1**：`set -e` 下 `[ "$format" = "table" ] && echo ""` 测试失败时导致脚本退出，改用 `if/fi`
- **duplicate 检测范围**：从仅 `running` 扩展到 `running|blocked`

### 新增
- **create 加全局锁**：`with_global_lock` 防并发 ID 冲突
- **duplicate 创建检测**：create 前检查同名 running/blocked 任务
- **smoke test 脚本**：`scripts/smoke-test.sh`（27 项端到端测试）
- **GitHub Actions CI**：push/PR 自动跑 smoke test
- **README badges**：CI status + MIT License

### 变更
- **setup.md 硬编码路径改占位符**（8 处）
- **spec-format.md 硬编码路径改占位符**（1 处）
- **SKILL.md 快速开始改占位符**（2 处）
- **SPEC-TEMPLATE**：补充 parent/children/verified 字段
- **清理生产数据残留**：`.locks/T-xxx.lock`

## v2.1.2 — 2026-05-17

### 修复
- **reopen/takeover 清理锁文件**：与 complete/fail 保持一致
- **输入验证**：create --priority、update --status、verify --result 增加枚举校验
- **SPEC-TEMPLATE**：补充 parent/children/verified 字段

### 变更
- **模板路径占位符**：AGENTS-TEMPLATE / HEARTBEAT-TEMPLATE 改用顶部变量声明，去除硬编码路径
- **.gitignore**：新增

## v2.1.1 — 2026-05-17

### 修复
- **complete/fail 自动清理锁文件**：任务完成或失败时 `rm -f "$LOCK_DIR/$task_id.lock"`，防止 `.locks/` 目录膨胀
- **list-done table header**：`list-done --format table` 现在输出表头行（TASK/OWNER/UPDATED/DESC）

### 变更
- **精简 supervisor AGENTS.md**：去除与 SKILL.md 重复的命令列表，保留 supervisor 专有的消息解析规则和告警逻辑
- **devengineer AGENTS.md**：task-manager 引用改为 skill 名（全局自动加载），删除硬编码路径
- **devengineer HEARTBEAT.md**：task-manager 引用精简为"全局，自动加载"，删除冗余路径和命令示例
- **清理测试任务**：移除 T-20260517-003~008 测试数据

## v2.1.0 — 2026-05-17

### 新增
- **父子任务**：`--parent` 参数创建子任务，自动注册到父任务的 `children` 字段
- **`tree` 命令**：树形展示父子任务层级，支持 `--agent` 过滤
- **`verify` 命令**：验证任务结果（pass/fail），fail 时自动追加修复步骤
- **`reopen` 命令**：将已完成任务从 done/ 移回 active/，状态重置为 running
- **`revise` 命令**：验证失败后追加修复步骤（标记为 `[修订]`）
- **完整守卫**：`complete` 前检查所有子任务必须 done（`--force` 跳过）
- **联动阻塞**：子任务 `fail` → 父任务自动 `blocked`
- **预检门控**：触发条件表 + 自检检查点 + 事后补录规范
- **反模式表**：4 个已验证失败模式（含真实案例）
- **自迭代协议**：触发条件、迭代流程、改动范围约束
- **references/**：setup.md（安装部署）、spec-format.md（SPEC 格式）、anti-patterns.md（反模式详解）
- **templates/**：SPEC-TEMPLATE.md、AGENTS-TEMPLATE.md、HEARTBEAT-TEMPLATE.md
- **CHANGELOG.md**：版本日志
- **README.md**：人类可读概览

### 变更
- Supervisor AGENTS.md 模板：新增 verify/reopen/revise/tree/parent/orphans
- Supervisor HEARTBEAT.md 模板：新增 tree 命令 + 父子 blocked 告警
- 安装章节：拆分为 references/setup.md，含心跳配置 + 安装验证清单 + 迁移指引
- SPEC.md 格式：拆分为 references/spec-format.md，含状态流转图 + 父子差异 + 恢复机制

## v2.0.0 — 2026-05-17

### 新增
- **flock 并发锁**：所有写操作加文件锁，防止并发损坏
- **claim 冲突检测**：`claim` 命令检查当前 owner，返回 conflict
- **takeover 强制接管**：`takeover` 命令强制接管任务，记录审计日志
- **orphans 僵尸扫描**：`orphans` 命令扫描超时未更新的任务
- **plan 步骤规划**：`plan` 命令设置详细执行计划
- **resume 恢复信息**：`resume` 命令获取断点续做信息
- **list-done 已完成查询**：`list-done` 命令查询已完成任务
- **JSON 输出**：`--format json` 支持程序解析
- **表格式输出**：`--format table` 支持人类阅读
- **重建索引**：`rebuild-index` 命令重建任务索引

### 变更
- 任务目录：从 `task-management/` 迁移到 `task-manager/`
- 脚本：统一到 `scripts/task.sh`

## v1.0.0 — 2026-05-16

### 初始版本
- 基础 CRUD：create / update / complete / fail / block / unblock / list / status / cleanup
- Supervisor 协议：`[task-lifecycle]` 前缀解析
- 心跳巡检：每小时 cron 触发
- SPEC.md 格式：元信息 + 目标 + 执行计划 + 上下文 + 恢复信息
