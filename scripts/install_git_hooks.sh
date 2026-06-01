#!/usr/bin/env bash
# 安装项目 git hooks（团队成员 clone 后跑一次）。
#
#   bash scripts/install_git_hooks.sh
#
# 装的钩子：
#   pre-commit → scripts/check_no_ohos_patch.sh（拦截鸿蒙补丁态误提交）

set -eu

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

hooks_dir=$(git rev-parse --git-path hooks)
mkdir -p "$hooks_dir"

cat > "$hooks_dir/pre-commit" <<'EOF'
#!/usr/bin/env bash
# Auto-installed by scripts/install_git_hooks.sh — do not edit here.
repo_root=$(git rev-parse --show-toplevel)
guard="$repo_root/scripts/check_no_ohos_patch.sh"
if [ -f "$guard" ]; then
  bash "$guard" || exit 1
fi
exit 0
EOF

chmod +x "$hooks_dir/pre-commit"
chmod +x "$repo_root/scripts/check_no_ohos_patch.sh" 2>/dev/null || true

echo "✓ pre-commit 钩子已安装 → $hooks_dir/pre-commit"
echo "  作用：提交前运行 scripts/check_no_ohos_patch.sh，拦截鸿蒙补丁态残留。"
echo "  跳过单次：git commit --no-verify"
