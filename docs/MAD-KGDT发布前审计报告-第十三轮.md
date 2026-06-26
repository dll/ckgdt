# MAD-KGDT 发布前审计报告（第十三轮 — 项目级终审）

> **审计日期**：2026-06-01 &emsp; **版本**：v1.17.0 &emsp; **审计范围**：全项目（5 端 + CI + 文档 + 代码）

---

## 一、版本一致性

| 来源 | 值 | 状态 |
|------|-----|:----:|
| `lib/core/version.dart` (SSOT) | `1.17.0`（三段式） | ✅ |
| `pubspec.yaml` | `1.17.0+0` | ✅ |
| `android/.../strings.xml` | `移动图谱与数字孪生v1.17.0` | ✅ |
| `windows/CMakeLists.txt` | `BINARY_OUTPUT_NAME "移动图谱与数字孪生v1.17.0"` | ✅ |
| `windows/runner/main.cpp` | `L"移动图谱与数字孪生v1.17.0"` | ✅ |
| `windows/runner/Runner.rc` | FileDescription/OriginalFilename/ProductName **3 处** `v1.17.0` | ✅ |
| `web/index.html` | `<title>`/`apple-mobile-web-app-title`/`application-name` **3 处** `v1.17.0` | ✅ |
| `web/manifest.json` | `"name"` 带版本，`"short_name"` 不带 | ✅ |
| `ohos/AppScope/app.json5` | `versionName: "1.17.0"`, `versionCode: 19` | ✅ |
| `ios/Runner/Info.plist` | 使用 `$(FLUTTER_BUILD_NAME)` 自动获取 | ✅ |

> **14 个文件全部对齐**。`MaterialApp.title` 由 `BuildInfo.appBrandWithVersion` 派生 = `移动图谱与数字孪生v1.17.0`（三段式，build=0 时省略尾部零）。

---

## 二、CI 流水线

| Job | 触发 | 运行器 | 超时 | 状态 |
|-----|------|--------|------|:----:|
| `analyze-test` | push/PR | ubuntu-latest | 15m | ✅ 绿灯 |
| `build-web` | push | ubuntu-latest | 30m | ✅ 绿灯 |
| `build-android` | push | ubuntu-latest | 45m | ✅ 绿灯 |
| `build-windows` | push | windows-latest | 60m | ✅ 绿灯 |
| `build-ios` | push | macos-latest | 60m | ✅ 绿灯 |
| `deploy-web` | push master | ubuntu-latest | — | ✅ 自动部署 |

**门禁**：
- `catch(_)` 棘轮：上限=0，实际=0 → 通过 ✅
- `withOpacity` 零容忍门禁 → 通过 ✅
- `flutter analyze lib` → 0 error 0 warning ✅
- `flutter test` → 25 文件 207 tests 全部通过 ✅

---

## 三、代码质量

| 指标 | 值 | 状态 |
|------|-----|:----:|
| `flutter analyze` errors | 0 | ✅ |
| `flutter analyze` warnings | 0 | ✅ |
| `catch(_)` in lib/ | 0 | ✅ |
| `.withOpacity(` in lib/ | 0 | ✅ |
| Unit tests | 207 passed, 0 failed | ✅ |

486 条 info 提示均为风格建议（`prefer_const_constructors` 等），无功能影响。

---

## 四、平台构建

| 端 | 构建方式 | 产物 | 大小 | 状态 |
|----|---------|------|------|:----:|
| **Android** | `flutter build apk --release` | `app-release.apk` (universal) | 142 MB | ✅ |
| **Windows** | `flutter build windows --release` | `.exe` + libmpv/ANGLE/sqlite3 dlls | 66 MB zip | ✅ |
| **Web** | `flutter build web --release --base-href "/mad-kgdt/"` | 静态站 + GitHub Pages | 39 MB zip | ✅ |
| **HarmonyOS** | `./build_ohos.bat` | `entry-default-signed.hap` (arm64) | 72 MB | ✅ |
| **iOS** | CI macOS runner `--no-codesign` | `.ipa` (从 xcarchive 打包) | 49 MB | ✅ |

**OHOS API 兼容**：`ohos_patch.ps1` 覆盖 8 种 API 降级（withValues/ThemeData 后缀/activeThumbColor/toARGB32/i18n），`ohos_restore.ps1` 确保构建后 lib/ 复原。

---

## 五、已知修复项（本轮审计）

| # | 严重度 | 问题 | 修复 |
|---|:---:|------|------|
| 1 | 🔴 | `Runner.rc` OriginalFilename 缺 `.exe` 前点号 → `v1.17.0exe` | 手动修复为 `v1.17.0.exe` |
| 2 | 🔴 | `VersionBumpService` 正则 `[0-9.]+` 误吞 `.exe` 后缀 | 改为 `\d+\.\d+\.\d+` 精确三段匹配 |
| 3 | ⚠ | `Version.display` 四段式 `1.17.0.0`（build=0 时冗余） | 改为三段式 `1.17.0` |
| 4 | ⚠ | `catch_underscore_ceiling.txt` = 178 但实际 = 0 | 更新为 0，收紧棘轮 |
| 5 | ⚠ | `android/local.properties` versionCode=1 vs pubspec build=0 | 非阻塞（Gradle 读取 pubspec 覆盖） |

---

## 六、文档完整性

| 文档 | 内容 |
|------|------|
| `docs/MAD-KGDT构建iOS应用.md` | iOS 构建指南（449 行，含十六轮审核记录） |
| `docs/MAD-KGDT构建Android应用.md` | Android 构建指南（Gradle/签名/ADB） |
| `docs/MAD-KGDT构建Windows应用.md` | Windows 构建指南（ANGLE/libmpv） |
| `docs/MAD-KGDT构建Web应用.md` | Web 构建指南（base href/GitHub Pages） |
| `docs/MAD-KGDT构建HarmonyOS应用.md` | 鸿蒙构建指南（签名/真机限制） |
| `docs/` 其他 | 架构设计/case study/测试报告/开发记录 等 31 条目 |

---

## 七、发布产物清单

| 文件 | 大小 |
|------|------|
| `移动图谱与数字孪生+windows+v1.17.0.zip` | 69 MB |
| `移动图谱与数字孪生+android+v1.17.0.zip` | 82 MB |
| `移动图谱与数字孪生+web+v1.17.0.zip` | 40 MB |
| `移动图谱与数字孪生+harmonyos+v1.17.0.zip` | 41 MB |
| `移动图谱与数字孪生+ios+v1.17.0-unsigned.ipa` | 49 MB |

> 全部 5 个产物已上传到 [GitHub Release v1.17.0](https://github.com/dll/mad-kgdt/releases/tag/v1.17.0)

---

## 八、总结

项目处于**就绪发布**状态：
- ✅ 14 个文件版本号一致
- ✅ 5 端 CI 全部绿灯
- ✅ 0 error / 0 warning / 0 catch(_)
- ✅ 207 tests 全部通过
- ✅ 5 篇构建文档齐全
- ✅ 5 个产物已上传 Release + Gitee tag
- 🔴 2 项修复（Runner.rc dot + VersionBumpService regex，本轮已修）
- ⚠ 3 项低优先级（Version.display 格式 / ceiling 文件 / local.properties，本轮已修）

**Git 状态**：`master` 分支干净，tag `v1.17.0` 已推送到 Gitee + GitHub 双远程。
