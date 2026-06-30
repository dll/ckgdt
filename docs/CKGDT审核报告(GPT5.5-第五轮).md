# CKGDT 课程知识图谱与数字孪生平台审核报告（GPT5.5 第五轮）

- 审核日期：2026-06-30
- 审核对象：`D:\FlutterProjects\knowledge_graph_app`
- 当前分支：`master`
- 当前基线提交：`e6ff45d 完善课程平台化智能体与数字孪生`
- 应用版本：`2.3.4+0`
- Flutter / Dart：`Flutter 3.35.1` / `Dart 3.9.0`
- 本轮重点：登录页灰色错误占位、`CLAUDE.md` 历史事故复核、Windows Release 重新构建、第五轮回归审查。

## 总体结论

本轮结论：**登录页重大运行期错误已修复，Windows Release 已重新构建通过；该问题属于 `CLAUDE.md` 已明确记录的历史事故再次复发，后续必须把本地化代理契约作为提交前硬门禁。**

截图中的登录页大灰块不是登录页视觉样式丢失，也不是语音按钮撑高表单。根因是 `lib/main.dart` 的 `MaterialApp` 被改成：

```dart
supportedLocales: const [Locale("zh"), Locale("en")],
localizationsDelegates: const [],
```

这会导致 `TextField/TextFormField` 在运行期调用 `MaterialLocalizations.of(context)` 时拿到 `null`，Flutter 将异常区域渲染为灰色错误占位。该情况与 `CLAUDE.md` 中“历史事故（已多次出现）”完全一致。

## 第五轮后续修复记录

本报告形成后已针对“仍需关注”中的高风险项完成修复：

- 提交前检查：`scripts/check_no_ohos_patch.sh` 已加入本地化代理契约检查。暂存区涉及 `lib/main.dart` 或 `test/app_localization_contract_test.dart` 时，会自动运行 `flutter test test/app_localization_contract_test.dart`，防止 `localizationsDelegates: const []` 再次进入提交。
- 文档平台化：`CLAUDE.md` 的默认课程章节已从《移动应用开发》更新为 CKGDT 六章，并明确《移动应用开发》仅作为历史种子材料兼容存在，新功能和智能体默认以当前课程上下文为准。
- 教学案例持久化：`CaseDao` 已补齐旧表 `course_id` 迁移与回填，新添加案例保存到 `teaching_cases` 并绑定当前课程；查询、编辑、删除均按当前课程作用域执行，避免跨课程串数据或旧库新增后不可见。

## 本轮已修复问题

### P0：登录页账号表单显示为灰色错误占位（已修复）

证据：

- `CLAUDE.md` 已明确要求登录页灰块先排查 `localizationsDelegates`，不要先重写登录页视觉。
- Release 日志 `build/windows/x64/runner/Release/logs/mad_init.log` 中出现：
  - `MaterialLocalizations.of`
  - `Null check operator used on a null value`
  - `_TextFieldState._getEffectiveDecoration`
- `lib/main.dart` 原状态为 `localizationsDelegates: const []`，正中历史事故根因。

修复：

- `lib/main.dart` 引入 `l10n/gen/app_localizations.dart`。
- 正常启动分支恢复：
  - `supportedLocales: AppL10n.supportedLocales`
  - `localizationsDelegates: AppL10n.localizationsDelegates`
- 数据库锁定错误页分支也补齐同一套代理，避免锁定页或后续 Material 组件再次缺失本地化上下文。

影响：

- 登录页账号输入框、密码输入框、语音输入按钮所在的 `TextFormField` 可正常获得 `MaterialLocalizations`。
- 截图中的灰色错误块应消失。
- 扫码页、语音登录和全局悬浮按钮逻辑未被重写。

## 防复发要求

该问题已多次出现，不能再按普通 UI 问题处理。后续任何涉及 `lib/main.dart`、`MaterialApp`、i18n、登录页的修改，都必须先执行：

```powershell
rg -n "localizationsDelegates|supportedLocales|AppL10n" lib\main.dart lib\l10n\gen\app_localizations.dart
flutter test test\app_localization_contract_test.dart
flutter analyze --no-fatal-infos lib\main.dart lib\presentation\pages\login
```

硬性规则：

- 禁止 `localizationsDelegates: const []`。
- 禁止手写不含 `GlobalMaterialLocalizations.delegate` 的代理列表。
- 必须使用 `AppL10n.localizationsDelegates` 和 `AppL10n.supportedLocales` 作为唯一入口。
- 登录页灰块、输入框消失、NavigationBar/TabBar 异常时，先看本地化代理和 Release 日志，不先改登录页布局。

## 验证结果

| 命令 | 结果 |
|---|---|
| `rg -n "localizationsDelegates\|supportedLocales\|AppL10n" lib\main.dart test\app_localization_contract_test.dart` | `lib/main.dart` 两个 `MaterialApp` 均使用 `AppL10n`；契约测试仍检查禁止空代理 |
| `flutter test test\app_localization_contract_test.dart` | 通过，`All tests passed` |
| `flutter analyze --no-fatal-infos lib\main.dart lib\presentation\pages\login` | 无 error/warning；仅历史 info 级提示 |
| `git diff --check` | 通过 |
| `flutter build windows --release` | 通过，产物位于 `build\windows\x64\runner\Release` |
| `flutter test test\data\local\case_dao_test.dart test\app_localization_contract_test.dart` | 通过，覆盖旧案例表补 `course_id`、新案例课程绑定和本地化代理契约 |

## 仍需关注

### P1：本地化代理契约需要进入提交前检查（已修复）

项目已有 `test/app_localization_contract_test.dart`，但本轮仍能把 `localizationsDelegates` 改成空列表并提交，说明提交前验证没有覆盖该测试。现已把以下检查接入 pre-commit 相关守卫脚本：

```powershell
flutter test test\app_localization_contract_test.dart
```

### P2：Analyzer 仍有大量 info 级技术债

本轮目标分析只出现 info 级提示，包括 `withOpacity` 弃用和少量 async context 提示。当前不阻断构建，但会稀释 analyzer 输出。建议继续采用“过滤 error/warning 作为硬门禁，info 分批清理”的策略。

### P2：教学案例新增需要持久化并关联课程（已修复）

第五轮后续复核发现，页面虽然调用 `CaseDao.addCase()`，但旧库中的 `teaching_cases` 表可能没有 `course_id` 列，导致按当前课程查询时新增/旧数据不可见或无法稳定隔离。现已修复：

- 旧表自动补 `course_id` 列，并把空课程回填为当前激活课程。
- `addCase()` 新增案例写入当前课程 ID。
- `getCases()` 只加载当前课程案例。
- `updateCase()` / `deleteCase()` 同时限定 `id` 与 `course_id`。
- 新增 `test/data/local/case_dao_test.dart` 覆盖旧表迁移和新案例课程绑定。

### P2：`CLAUDE.md` 当前课程章节描述仍包含旧默认课程（已修复）

运行端已逐步平台化为 CKGDT，但 `CLAUDE.md` 的“课程内容（6 章）”仍记录移动应用开发章节。现已改为 CKGDT 默认平台课程六章，并补充历史移动应用种子材料的兼容说明，避免后续代理误读。

## 本轮修复文件

- `lib/main.dart`
  - 恢复 `AppL10n` 导入。
  - 两个 `MaterialApp` 均恢复 `AppL10n.supportedLocales` 与 `AppL10n.localizationsDelegates`。

## 最终结论

本轮登录页错误已经定位到 `CLAUDE.md` 明确记录的历史事故：空本地化代理导致 Material 文本输入组件运行期崩溃。修复后契约测试、目标分析、空白检查和 Windows Release 构建均通过。

下一轮优先事项不是继续重写登录页，而是把“本地化代理不可为空”的契约测试纳入提交前和发布前流程，避免同类问题再次进入 Release。
