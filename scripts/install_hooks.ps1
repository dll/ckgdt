#!/usr/bin/env pwsh
<#
.SYNOPSIS
    安装项目 Git hooks — .githooks/ 目录 → Git hooksPath 配置。

.DESCRIPTION
    将 git hooksPath 指向 .githooks/ 目录（已受版本控制），
    所有 dev 成员克隆仓库后只需跑一次本脚本。

    安装的钩子：
      pre-commit     — OHOS 补丁残留检查 + 大文件拦截 + Dart 语法检查
      post-merge     — 合并后自动 flutter pub get（仅 pubspec.yaml 变化时）
      post-checkout  — 切换分支后自动 flutter pub get
      pre-push       — 推送前 flutter analyze + test + 版本号一致性检查

    跳过钩子：
      git commit --no-verify       # 跳过 pre-commit
      git push --no-verify         # 跳过 pre-push

.EXAMPLE
    .\scripts\install_hooks.ps1                    # 安装到当前仓库
    .\scripts\install_hooks.ps1 -Remove            # 恢复 Git 默认钩子
#>

param(
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$hooksDir = Join-Path $repoRoot '.githooks'

if (-not (Test-Path -LiteralPath $hooksDir)) {
    Write-Host "❌ 未找到 .githooks/ 目录: $hooksDir" -ForegroundColor Red
    exit 1
}

if ($Remove) {
    git config --local --unset core.hooksPath 2>$null
    Write-Host "✓ Git 钩子已恢复为默认（.git/hooks/）" -ForegroundColor Green
    exit 0
}

# 配置 Git 使用 .githooks/ 作为钩子目录
git config --local core.hooksPath '.githooks'

Write-Host "✓ Git hooksPath 已配置: .githooks/" -ForegroundColor Green
Write-Host "  仓库级配置（不影响其他项目）" -ForegroundColor Gray
Write-Host ""
Write-Host "已安装的钩子:" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $hooksDir -File | ForEach-Object {
    $desc = switch ($_.Name) {
        'pre-commit'    { '提交前: OHOS 检查 / 大文件拦截 / Dart 语法检查' }
        'post-merge'    { '合并后: 自动 flutter pub get' }
        'post-checkout' { '切换分支: 自动 flutter pub get' }
        'pre-push'      { '推送前: flutter analyze / test / 版本一致性' }
        default         { '自定义钩子' }
    }
    Write-Host "  • $($_.Name) — $desc" -ForegroundColor White
}
Write-Host ""
Write-Host "用法:" -ForegroundColor Yellow
Write-Host "  跳过单次提交: git commit --no-verify" -ForegroundColor Gray
Write-Host "  跳过单次推送: git push --no-verify" -ForegroundColor Gray
Write-Host "  卸载钩子:    .\scripts\install_hooks.ps1 -Remove" -ForegroundColor Gray
