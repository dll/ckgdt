# 脚本目录

## 当前脚本入口

| 脚本 | 用途 |
| --- | --- |
| `deploy_web.ps1` | Web 部署 |
| `pack_dist_zip.ps1` | 打包发布 ZIP |
| `preflight_windows_release.ps1` | Windows 发布前检查 |
| `version_bump.dart` | 版本号更新 |
| `gitee_create_release.py` | 创建 Gitee Release |
| `gitee_upload_assets.py` | 上传 Release 附件 |
| `find_gitee_release.py` | 查询 Release |
| `patch_sqlite3.ps1` | sqlite3 补丁 |
| `install_git_hooks.sh` | 安装 Git hooks |
| `check_no_ohos_patch.sh` | 检查 OHOS patch 残留 |

## 根目录兼容脚本

以下脚本暂时保留在根目录，因为代码或文档仍按根目录调用：

- `build_ohos.bat`
- `ohos_patch.ps1`
- `ohos_restore.ps1`
- `pubspec_overrides_ohos.yaml`
- `install_vs_components.bat`

迁移这些脚本时，必须同步修改 `lib/services/release_service.dart`、`docs/CKGDT构建HarmonyOS应用.md` 和 `CLAUDE.md` 中的入口说明。

## 推荐分类

```text
scripts/build/      # Android / Windows / Web / OHOS 构建入口
scripts/release/    # 发布、打包、上传
scripts/setup/      # 环境安装和本机初始化
scripts/hooks/      # Git hook 和提交前检查
scripts/media/      # 视频、课件、音频生成
scripts/patches/    # 构建补丁和二进制补丁
```

## 规则

- 脚本产生的日志写入 `logs/build/YYYY-MM-DD/`。
- 脚本产生的发布产物写入 `dist/`。
- 中间文件、缓存、音视频临时文件不得写入根目录。
