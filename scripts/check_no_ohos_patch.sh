#!/usr/bin/env bash
# OHOS 补丁态提交守卫 —— 防止把鸿蒙构建中途降级过的 lib/ 提交进 master。
#
# 背景（真实事故 commit 944b452d7）：build_ohos.bat 会先用 ohos_patch.ps1 把
# lib/ 源码降级（withValues→withOpacity、CardThemeData→CardTheme 等），构建后再
# 用 ohos_restore.ps1 还原。如果构建中断、或在补丁态执行了 git add lib/，降级后
# 的代码就会被提交进主干 —— 这正是第十二轮那次「withValues 全局回退 + 3 个 theme
# 编译错误」的来源。
#
# 本守卫检测「补丁态」的几个签名，命中则拒绝提交。
# 退出码 0 = 放行，1 = 拒绝。
#
# 安装：scripts/install_git_hooks.sh（把本脚本接到 .git/hooks/pre-commit）
# 跳过（确有需要时）：git commit --no-verify

set -u

fail() {
  echo "✗ [ohos-patch-guard] 拒绝提交：检测到鸿蒙构建补丁态残留" >&2
  echo "  $1" >&2
  echo "" >&2
  echo "  这通常意味着 build_ohos 构建中断、或在补丁态误 add 了 lib/。" >&2
  echo "  先还原再提交：  powershell ./ohos_restore.ps1" >&2
  echo "  （确属误报需强过：git commit --no-verify）" >&2
  exit 1
}

# 1) lib.backup/ 存在 = ohos_patch 跑过但 restore 没跑（最强信号）
if [ -d lib.backup ]; then
  fail "lib.backup/ 存在 —— ohos_patch.ps1 已备份但 ohos_restore.ps1 未还原。"
fi

# 2) pubspec_overrides.yaml 存在 = OHOS 依赖降版仍生效
if [ -f pubspec_overrides.yaml ]; then
  fail "pubspec_overrides.yaml 存在 —— OHOS 依赖降版仍生效，构建未清理。"
fi

# 3) 内容签名：暂存区里 theme_manager 用了旧版 ThemeData 名（被降级的铁证）
#    只查暂存内容（--cached），不碰工作区。
staged_theme=$(git diff --cached --name-only -- lib/services/theme_manager.dart)
if [ -n "$staged_theme" ]; then
  if git show ":lib/services/theme_manager.dart" 2>/dev/null \
       | grep -Eq '(cardTheme: CardTheme\(|dialogTheme: DialogTheme\(|tabBarTheme: TabBarTheme\()'; then
    fail "lib/services/theme_manager.dart 暂存内容用了旧版 CardTheme/DialogTheme/TabBarTheme（被 ohos_patch 降级）。"
  fi
fi

# 4) 内容签名：暂存的 lib/ dart 文件新增了 .withOpacity( 调用
#    （项目规范用 .withValues(alpha:)；patch 会把它降级成 withOpacity）
#    用 awk 取「新增行」(以 + 开头但非 +++ 头)，避开某些 grep 对 \+ 的怪异处理。
added_withopacity=$(git diff --cached -- 'lib/*.dart' 'lib/**/*.dart' \
  | awk '/^\+\+\+/{next} /^\+/{print}' \
  | grep -c '\.withOpacity(' || true)
if [ "${added_withopacity:-0}" -gt 0 ]; then
  fail "暂存改动新增了 ${added_withopacity} 处 .withOpacity( —— 应为 .withValues(alpha:)（疑似 ohos_patch 降级）。"
fi

# 5) MaterialApp 本地化代理契约：登录页 TextField 依赖
#    GlobalMaterialLocalizations。历史上多次把 localizationsDelegates 改成
#    const []，analyze 不报错，但运行期登录页出现灰色错误占位。
#    只在相关文件进入暂存区时运行，避免所有提交都被 Flutter 测试拖慢。
staged_l10n_contract=$(git diff --cached --name-only -- \
  lib/main.dart test/app_localization_contract_test.dart)
if [ -n "$staged_l10n_contract" ]; then
  echo "• [localization-contract] checking MaterialApp localization delegates..."
  flutter test test/app_localization_contract_test.dart || exit 1
fi

exit 0
