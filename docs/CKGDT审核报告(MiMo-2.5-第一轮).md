# CKGDT 课程知识图谱与数字孪生平台审核报告（MiMo-2.5 第一轮）

- 审核日期：2026-07-04
- 审核对象：`D:\FlutterProjects\knowledge_graph_app`
- 当前分支：`master`
- 应用版本：`2.5.0+0`
- Flutter / Dart：`Flutter 3.35.1` / `Dart 3.9.0`
- 审核模型：MiMo-2.5-Free
- 审核范围：架构规范、安全漏洞、数据库一致性、测试覆盖、文档准确性

---

## 总体结论

**项目功能完整度高（88 页面 / 19 智能体 / 87 数据表），但存在 3 个 CRITICAL 级安全漏洞、2 个 HIGH 级架构违规、以及大量技术债务。最紧迫的问题是 API Key / Gitee Token 硬编码（可被反编译提取）和 CLAUDE.md 文档严重滞后于实际代码。**

### 严重度统计

| 级别 | 数量 | 说明 |
|------|------|------|
| **CRITICAL** | 5 | 硬编码密钥 × 3 + 本地化代理崩溃 + V34 迁移缺失 |
| **HIGH** | 7 | 架构分层违规 × 2 + 密码安全 × 2 + 导航文档过时 + 测试空白 + `catch (_) {}` 泛滥 |
| **MEDIUM** | 12 | SQL 注入风险 + Token 泄露 + 废弃 API + 大文件 + 文档版本过时 等 |
| **LOW** | 10 | 命名规范 + 构建配置 + 双重建表 等 |

---

## 一、安全漏洞（Security）

### S1. CRITICAL — 硬编码 AI API Key（3 个密钥明文编译进二进制）

**文件**：`lib/data/models/ai_config_model.dart:29-33`

```dart
const Map<String, String> builtinApiKeys = {
  'deepseek': 'sk-717ef9146311424daa2fbead8ed4682b',
  'zhipu': '5dc44da8d9dd4c28bf38cde316950f1e.nNIf7AXWrJXIcSyQ',
  'zhipu_vision': '20322a4a95bf4bd68161b1f705aa6603.yHEHABcNAcOWy8WH',
};
```

**影响**：APK 反编译或 Dart AOT 快照提取即可获得全部密钥，滥用 AI 服务产生费用。
**修复**：移除硬编码，改为运行时从安全存储读取；或至少用 `kReleaseMode` 条件守卫。

### S2. CRITICAL — 硬编码 Gitee Access Token

**文件**：`lib/services/data_loading_service.dart:56-57`

```dart
const defaultToken = '64a07762f8a3ab4415b8c943651bfb91';
```

**影响**：该 Token 拥有 `chzcldl/mad-data` 和学生组仓库的读写权限，泄露即失控。
**修复**：从 `flutter_secure_storage` 读取，首次启动引导用户配置。

### S3. CRITICAL — 硬编码讯飞语音 API 凭证

**文件**：`lib/services/settings_service.dart:199-202`

App ID / API Key / API Secret 三件套明文写入。
**修复**：同 S1，移除或条件编译。

### S4. HIGH — 密码安全薄弱

- **默认密码可预测**：`userId.substring(userId.length - 6)`，6 位数字空间（100 万种），无暴力破解防护
- **哈希算法弱**：单次 SHA-256 + 可预测 salt（userId），无迭代/拉伸
- **无登录频率限制**：可无限尝试登录
- **密码哈希实现分散**：`auth_service.dart:246`、`user_dao.dart:260`、`session_manager.dart:122` 三处重复实现

**修复**：迁移至 bcrypt/argon2 + 随机 salt；增加登录失败延迟/锁定机制。

### S5. MEDIUM — Gitee Token 通过 URL Query 参数传递

**文件**：`gitee_service.dart:535`、`release_service.dart:869-923`

Token 出现在 URL 中会泄露到服务器日志、代理日志、浏览器历史。
**修复**：改用 `Authorization: Bearer <token>` Header。

### S6. MEDIUM — 密钥存储在明文 SharedPreferences

**文件**：`gitee_service.dart:21`、`settings_service.dart:218-312`

所有 Token/API Key 存储在 SharedPreferences（明文 XML/JSON），root 设备可直接读取。
**修复**：迁移到 `flutter_secure_storage`（Keychain/Keystore）。

### S7. MEDIUM — SQL 字符串拼接（IN 子句）

**文件**：`data_loading_service.dart:321-338`

```dart
final ids = emptyGraphs.map((r) => "'${r['id']}'").join(',');
await db.rawDelete('DELETE FROM graphs WHERE id IN ($ids)');
```

虽然 `r['id']` 来自数据库查询，但若通过同步导入恶意数据则存在注入风险。
**修复**：使用参数化查询或 `where: 'id IN (${List.filled(n, '?').join(',')})'`。

---

## 二、架构违规（Architecture）

### A1. CRITICAL — 本地化代理被清空（历史事故再次复发）

**文件**：`lib/main.dart:227, 301`

两个 `MaterialApp` 均使用 `localizationsDelegates: const []`，导致 `MaterialLocalizations.of(context)` 返回 null，登录页 TextField 运行时崩溃（灰色错误占位）。

这是 CLAUDE.md 明确记录的**第四次复发**。
**修复**：恢复为 `AppL10n.localizationsDelegates`。

### A2. CRITICAL — V34 数据库迁移缺失

**文件**：`lib/data/local/database_helper.dart:944-949`

```dart
if (oldVersion < 33) {
  await _migrateToV33(db);
  await _migrateToV34(db);   // V34 嵌套在 V33 块内！
}
```

V34（`ai_trial_settings` 表）没有独立的 `if (oldVersion < 34)` 守卫，从 V33 升级到 V35 时被跳过。
**修复**：添加独立的 V34 迁移块。

### A3. HIGH — 23 个页面直接操作数据库

CLAUDE.md 规定 "pages 只调用 services/dao，不直接操作 DB"，但 23 个 presentation 文件直接导入 `DatabaseHelper` 并执行 `rawQuery`。

主要违规文件：
- `data_export_page.dart`（17 次 rawQuery）
- `learning_analytics_page.dart`（8 次）
- `login_progress_dialog.dart`（8 次）
- `teacher_workspace_page.dart`（8 次）
- `logout_report_dialog.dart`（7 次）

**修复**：将 SQL 提取到对应 DAO 方法中。

### A4. HIGH — 24 个 DAO 反向依赖 Services

CLAUDE.md 规定 "dao 只依赖 sqflite + DatabaseHelper"，但 24 个 DAO 文件导入了 `CourseContextService` 等服务层组件，形成循环依赖。

**修复**：将 `courseId` 作为参数从 Service 层传入 DAO，而非 DAO 内部获取。

### A5. HIGH — NavigationService 导入 57 个页面文件

**文件**：`services/navigation_service.dart`

Services 层直接导入所有 presentation 页面，任何页面变更都触发服务层重编译。

**修复**：使用路由注册模式（`Map<String, WidgetBuilder>`），在 App 启动时注册。

### A6. MEDIUM — 98 处 `catch (_) {}` 违反编码规范

CLAUDE.md 明确禁止 `catch (_)`，但代码中有 98 处违规：
- `project_detector.dart`：21 处
- `sync_service.dart`：20 处
- `apk_launcher_service.dart`：9 处
- `course_data_service.dart`：7 处
- 其他 41 处

**修复**：全部替换为 `catch (e, st) { swallowDebug(e, tag: '...', stack: st); }`。

### A7. MEDIUM — 2 个 Service 导入 Presentation 文件

- `achievement_chart_service.dart` 导入 `achievement_shared.dart`
- `achievement_excel_service.dart` 导入 `achievement_config.dart`

**修复**：将共享代码移至 `core/` 或 `data/` 层。

---

## 三、数据库一致性（Database）

### D1. HIGH — `_ensureAllTables` 缺失多个迁移

`_ensureAllTables` 是种子 DB 的安全网，但跳过了：

| 缺失迁移 | 影响 |
|----------|------|
| V24 | `ai_chat_history` 性能索引 |
| V25 | `archive_documents` 3 个列 |
| V32 | `course_objectives` 5 个列 |
| V33 | `assessment_groups.course_id` 等 |
| V34 | `ai_trial_settings` 整张表 |

**修复**：补齐 `_ensureAllTables` 中的迁移调用。

### D2. MEDIUM — 表数量文档严重过时

- **CLAUDE.md 声称**：59 张表
- **实际数量**：87 张表（74 在 database_helper + 13 仅在 DAO 中）

13 张表仅在 DAO 中创建（`teaching_cases`、`checkin_sessions`、`work_comments` 等），database_helper 无感知。

### D3. MEDIUM — 13 张表双重创建

以下表在 `database_helper.dart` 和对应 DAO 中均有 `CREATE TABLE IF NOT EXISTS`：
`collaboration_messages`、`peer_reviews`、`feedback`、`achievement_component_scores`、`contribution_scores`、`checkin_sessions`、`checkin_records`、`classroom_messages`、`roll_call_sessions`、`roll_call_records`、`classroom_questions`、`work_comments`、`work_likes`、`work_views`。

虽不冲突但增加维护负担。

### D4. LOW — `_ensureAllTables` 性能开销

每次启动运行 ~30 个迁移函数（大部分是空操作 ALTER TABLE），对启动速度有轻微影响。

---

## 四、测试覆盖（Testing）

### T1. HIGH — 关键路径零测试

| 缺失测试的关键路径 | 风险 |
|-------------------|------|
| 数据库迁移（V1-V35） | V34 缺陷无法被自动发现 |
| SyncService（Gitee 同步） | 核心数据同步无任何测试 |
| AuthService（登录/会话） | 认证流程无测试 |
| NavigationService（53+ 路由） | 路由解析无测试 |
| AI Service | AI Provider 集成无测试 |
| VoiceService | 语音识别无测试 |
| 20/26 DAO | 仅 6 个 DAO 有测试 |
| 17/19 Agent | 仅 2 个 Agent 测试 |
| 87/88 页面 | 仅 1 个 widget 测试 |

### T2. MEDIUM — 现有测试概况

共 52 个测试文件，覆盖：模型、核心工具、部分服务、部分 DAO、归档流程、达成度流程。基本框架存在但深度不足。

---

## 五、代码质量（Code Quality）

### Q1. MEDIUM — 400+ 处废弃 API `.withOpacity()`

Flutter 3.27+ 废弃了 `Color.withOpacity()`，应使用 `color.withValues(alpha: 0.x)`。

Top 10 违规文件：
| 文件 | 次数 |
|------|------|
| `defense_broadcast_page.dart` | 47 |
| `login_page.dart` | 43 |
| `analysis_tab.dart` | 43 |
| `knowledge_graph_page.dart` | 38 |
| `virtual_twin_page.dart` | 33 |
| `notification_manage_page.dart` | 32 |
| `teacher_manage_page.dart` | 31 |
| `contribution_tab.dart` | 30 |
| `ordinary_score_tab.dart` | 29 |
| `live_stream_panel.dart` | 27 |

### Q2. MEDIUM — 17 个超大文件（>1500 行）

| 文件 | 行数 |
|------|------|
| `period_tab.dart` | 3,932 |
| `courseware_workshop_page.dart` | 3,628 |
| `knowledge_graph_page.dart` | 3,348 |
| `report_tab.dart` | 2,958 |
| `database_helper.dart` | 2,949 |
| `courseware_service.dart` | 2,339 |
| `achievement_dao.dart` | 2,323 |
| `scores_tab.dart` | 2,295 |
| `virtual_twin_page.dart` | 2,265 |
| `learning_hub_page.dart` | 2,240 |
| `lab_report_tab.dart` | 2,172 |
| `analysis_tab.dart` | 2,143 |
| `achievement_excel_service.dart` | 2,092 |
| `defense_broadcast_page.dart` | 1,916 |
| `home_page.dart` | 1,889 |
| `graph_detail_page.dart` | 1,867 |
| `grading_agent.dart` | 1,208 |

### Q3. LOW — 命名规范

文件命名（snake_case）和类命名（PascalCase）**全部合规**，无违规。

---

## 六、CLAUDE.md 文档准确性

### C1. HIGH — 导航结构完全过时

CLAUDE.md 描述的 Tab 布局与实际代码严重不符：

| 维度 | CLAUDE.md 声称 | 实际代码 |
|------|---------------|---------|
| 教师 Tab 数 | 9 个 | 7-8 个 |
| 学生 Tab 数 | 6 个 | 7 个 |
| "案例" Tab | 未记录 | 两个角色均有（index 2） |
| "归档" Tab | 未记录 | 教师角色有（index 6） |
| "课堂" Tab | 教师有 | 已合并入"教学"聚合页 |
| "实验" Tab | 学生有 | 学生有（index 4） |

### C2. MEDIUM — 版本号过时 4 个次版本

- **CLAUDE.md 声称**：`2.1.0`
- **实际代码**：`2.5.0`

### C3. MEDIUM — 数据库版本过时

- **CLAUDE.md 声称**：version = 24
- **实际代码**：version = 35

### C4. MEDIUM — 表数量过时

- **CLAUDE.md 声称**：59 张表
- **实际数量**：87 张表

### C5. LOW — Agent 数量过时

- **CLAUDE.md 声称**：18 个 Agent
- **实际数量**：19 个（新增 `CaseDemoAgent`）

### C6. LOW — 子页面数量过时

- **CLAUDE.md 声称**：30+ 子页面
- **实际数量**：53+ 路由

---

## 七、构建与部署（Build）

### B1. INFO — 版本号一致性

所有 9 个版本引用文件**已对齐**到 2.5.0（pubspec / Android / Windows / Web / OHOS / BuildInfo）。

### B2. INFO — Android 构建配置

`isMinifyEnabled = false`，Release APK 未混淆/压缩，体积偏大。

### B3. LOW — OHOS versionCode 未递增

`ohos/AppScope/app.json5` 的 `versionCode` 仍为 1，未随版本升级递增。

### B4. LOW — pubspec.lock 追踪不一致

CLAUDE.md 声称 pubspec.lock 已 gitignore，但实际仍在仓库中。

---

## 八、修复优先级建议

### 立即修复（P0 — 阻断发布）

1. **A1** — 恢复 `AppL10n.localizationsDelegates`（登录页崩溃）
2. **S1/S2/S3** — 移除所有硬编码密钥（安全漏洞）
3. **A2** — 修复 V34 迁移缺失（数据完整性）

### 短期修复（P1 — 1-2 周内）

4. **A3/A4** — 修复架构分层违规（23 页面直连 DB + 24 DAO 反向依赖）
5. **A6** — 清理 98 处 `catch (_) {}`
6. **S4** — 加固密码安全（bcrypt + 登录限频）
7. **C1-C6** — 更新 CLAUDE.md 文档

### 中期改进（P2 — 1-2 月内）

8. **Q1** — 替换 400+ 处 `.withOpacity()`
9. **Q2** — 拆分 17 个超大文件
10. **T1** — 补充数据库迁移、同步、认证测试
11. **S5/S6** — Token 改用 Header 传递 + 安全存储
12. **D1** — 补齐 `_ensureAllTables` 迁移

### 长期优化（P3 — 持续改进）

13. **A5** — NavigationService 路由注册模式重构
14. **D2/D3** — 统一建表入口，消除双重创建
15. **Q3** — 持续清理技术债务

---

## 九、与 GPT5.5 第五轮审核对比

| 维度 | GPT5.5 第五轮 | MiMo-2.5 第一轮 |
|------|-------------|----------------|
| 审核范围 | 登录页灰块专项 | 全面系统审核 |
| 发现 P0 | 1 项（本地化代理） | 5 项（含安全漏洞） |
| 安全审计 | 未涉及 | 7 项（3 CRITICAL） |
| 架构审计 | 未涉及 | 7 项（2 HIGH） |
| 数据库审计 | 未涉及 | 4 项 |
| 测试审计 | 未涉及 | 2 项 |
| 文档审计 | 部分（CLAUDE.md 更新） | 6 项（全部过时） |

GPT5.5 聚焦于单一运行期 bug 的定位与修复，MiMo-2.5 从安全、架构、数据、测试、文档五个维度进行了系统性审查，发现了 GPT5.5 未覆盖的硬编码密钥、分层违规、文档过时等深层问题。

---

*报告生成：MiMo-2.5-Free · 2026-07-04*
