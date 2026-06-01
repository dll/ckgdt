# MAD-KGDT 构建 iOS 应用指南

> **移动图谱与数字孪生教学系统 — iOS 端（iPhone + iPad）云端构建与分发**

---

## 一、概述

MAD-KG 是 Flutter 全平台项目，iOS 端构建依赖 **macOS + Xcode** 工具链。本方案使用 **GitHub Actions + macOS Runner** 实现云端自动化构建，无需本地 Mac 设备。

| 项目 | 说明 |
|------|------|
| 构建方式 | GitHub Actions `macos-latest` 云 runner |
| 成本 | 公开仓库免费（2000 分钟/月） |
| 触发方式 | push `master` 分支自动构建 |
| 产物格式 | `.ipa`（iOS 应用包） |
| 支持设备 | iPhone + iPad（Universal） |
| Bundle ID | `cn.edu.chzu.madkg`（以 `ios/Runner.xcodeproj` 为准） |
| 最低 iOS 版本 | iOS 13.0（`ios/Podfile`） |
| Flutter 版本 | 3.35.1（CI `FLUTTER_VERSION`） |

> **当前 CI 状态（2026-06-01，第十三轮审核核实）**：`.github/workflows/ci.yml` 的
> `build-ios` job 在 commit `f30070a73` 新增，跑 `flutter build ipa --release --no-codesign`，
> 即**只验证编译通过、不签名**——产物无法直接装真机。要真机安装/分发必须按第三章配证书。
> 该 job 尚无确认的绿灯运行记录，首次推送后请到 GitHub → Actions 核实 `build-ios` 是否通过。

---

## 二、前置准备

### 2.1 Apple Developer 账号

必须拥有 **Apple Developer Program** 会员资格（$99/年），用于：
- 创建证书（Certificate）
- 注册设备（Device UDID）
- 创建 App ID
- 生成 Provisioning Profile

注册地址：https://developer.apple.com/programs/

### 2.2 获取设备 UDID（真机安装必需）

每台需要安装的 iPhone/iPad 都必须注册 UDID。

**方法一 — Xcode 获取**（需 Mac）：
```
设备连接 → Xcode → Window → Devices and Simulators → 复制 Identifier
```

**方法二 — 在线工具**（无需 Mac）：
1. iPhone/iPad Safari 打开 https://udid.tech
2. 点击"获取 UDID"→ 允许下载配置描述文件
3. 设置 → 通用 → VPN 与设备管理 → 安装描述文件
4. 自动跳转显示 UDID

**方法三 — Windows 工具**：
- 爱思助手 / 3uTools 连接设备后可查看 UDID

### 2.3 Apple Developer 后台配置

登录 https://developer.apple.com/account/resources/certificates/list 完成以下步骤：

#### Step 1：创建证书（Certificate）

1. 点击 **Certificates** → "+" 添加
2. 选择 **iOS App Development**（开发/测试用）或 **iOS Distribution**（发布用）
3. 需要 CSR 文件：macOS 上 Keychain Access → 证书助理 → 从证书颁发机构请求证书
4. 上传 `.certSigningRequest` → 下载 `.cer` 文件
5. 双击 `.cer` 导入钥匙串 → 导出为 `.p12`（设置密码）

#### Step 2：注册设备

1. 点击 **Devices** → "+" 添加
2. 填入设备名称和 UDID（2.2 获取的值）
3. 最多可注册 100 台 iPhone / 100 台 iPad / 100 台 Apple TV

#### Step 3：创建 App ID

1. 点击 **Identifiers** → "+" 添加 → **App IDs**
2. Bundle ID 选择 **Explicit**，填入 `cn.edu.chzu.madkg`（必须与 `ios/Runner.xcodeproj` 的 `PRODUCT_BUNDLE_IDENTIFIER` 完全一致，否则 Provisioning Profile 不匹配，构建/安装失败）
3. 勾选所需 Capabilities（本项目无需额外开启）

#### Step 4：生成 Provisioning Profile

1. 点击 **Profiles** → "+" 添加
2. 选择 **iOS App Development**（开发）或 **Ad Hoc**（内部测试分发）
3. 选择对应 App ID → 选择证书 → 勾选目标设备
4. 命名后下载 `.mobileprovision` 文件

---

## 三、GitHub Secrets 配置

在项目仓库中设置 Action Secrets：**GitHub → Settings → Secrets and variables → Actions → New repository secret**

### 3.1 准备 Secret 值

在 macOS 终端（或 Git Bash / WSL）执行：

```bash
# 1. p12 证书 Base64 编码
base64 -i YourCertificate.p12 | tr -d '\n'

# 2. Provisioning Profile Base64 编码
base64 -i YourProfile.mobileprovision | tr -d '\n'
```

Windows PowerShell 等效命令：

```powershell
# p12 证书
[Convert]::ToBase64String([IO.File]::ReadAllBytes("YourCertificate.p12"))

# Provisioning Profile
[Convert]::ToBase64String([IO.File]::ReadAllBytes("YourProfile.mobileprovision"))
```

### 3.2 添加三个 Secrets

| Secret 名称 | 值 | 说明 |
|-------------|-----|------|
| `IOS_P12_CERT` | p12 文件的 Base64 编码 | 开发/发布证书 |
| `IOS_P12_PASSWORD` | p12 导出时设置的密码 | 证书密码（明文） |
| `IOS_PROVISION_PROFILE` | mobileprovision 文件的 Base64 编码 | 描述文件 |

### 3.3 切换到签名构建

在 `.github/workflows/ci.yml` 的 `build-ios` job 中，将：

```yaml
- name: Build unsigned IPA
  run: flutter build ipa --release --no-codesign
```

替换为：

```yaml
- name: Install Provisioning Profile
  run: |
    mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
    echo "${{ secrets.IOS_PROVISION_PROFILE }}" | base64 -d > ~/Library/MobileDevice/Provisioning\ Profiles/profile.mobileprovision

- name: Import Code Signing Certificate
  uses: apple-actions/import-codesign-certs@v3
  with:
    p12-file-base64: ${{ secrets.IOS_P12_CERT }}
    p12-password: ${{ secrets.IOS_P12_PASSWORD }}

- name: Build signed IPA
  run: flutter build ipa --release --export-method=development
```

`--export-method` 可选值：
- `development` — 开发包（仅注册设备可安装）
- `ad-hoc` — 内部测试分发（TestFlight 外）
- `app-store` — 上传 App Store

---

## 四、构建与下载

### 4.1 触发构建

推送代码到 `master` 分支即可自动触发：

```bash
git push origin master
```

或手动触发：GitHub → Actions → CI workflow → **Run workflow**。

### 4.2 查看构建状态

GitHub → Actions → 选择最新运行 → 等待 `build-ios` job 完成。

### 4.3 下载 IPA

构建完成后：
1. 进入对应 Action Run 页面
2. 底部 Artifacts → 点击 `ios-ipa`
3. 解压得到 `MAD-KG-v{版本号}-unsigned.ipa`

---

## 五、安装到 iPhone/iPad

### 5.1 macOS（推荐）

```bash
# 安装 Apple Configurator 2（App Store 免费）
# 设备连接 Mac → 拖拽 .ipa 到 Apple Configurator → 安装

# 或使用命令行工具
brew install ios-deploy
ios-deploy --bundle path/to/Runner.ipa
```

### 5.2 Windows — 通过工具安装

**爱思助手**：
1. 设备连接 PC → 打开爱思助手
2. 应用游戏 → 导入安装 → 选择 `.ipa` 文件
3. 等待安装完成 → 设备 → 设置 → 通用 → VPN 与设备管理 → 信任企业级 App

**3uTools**：操作流程类似，支持一键安装 IPA。

**iTunes（旧版，支持 App 管理）**：
1. 安装 iTunes 12.6.3 或更早版本（新版已移除 App 管理）
2. 设备连接 → 应用 → 拖入 IPA

### 5.3 无线分发（OTA）

搭建简单 OTA 分发服务，iPhone/iPad 扫码安装：

1. 上传 IPA 到 HTTPS 服务器
2. 创建 `manifest.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>items</key>
    <array>
        <dict>
            <key>assets</key>
            <array>
                <dict>
                    <key>kind</key>
                    <string>software-package</string>
                    <key>url</key>
                    <string>https://your-server.com/MAD-KG.ipa</string>
                </dict>
            </array>
            <key>metadata</key>
            <dict>
                <key>bundle-identifier</key>
                <string>cn.edu.chzu.madkg</string>
                <key>bundle-version</key>
                <string>1.16.2</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>移动图谱与数字孪生</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
```

3. 生成安装链接：
```
itms-services://?action=download-manifest&url=https://your-server.com/manifest.plist
```

设备 Safari 打开此链接即可安装。

---

## 六、CI 工作流程详解

### 6.1 当前配置（无签名验证构建）

`.github/workflows/ci.yml` 中的 `build-ios` job：

```yaml
build-ios:
  name: Build iOS IPA
  if: github.event_name == 'push'
  needs: analyze-test          # 依赖静态分析通过
  runs-on: macos-latest        # macOS 14 (M1) runner
  timeout-minutes: 60
  steps:
    - uses: actions/checkout@v4
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.35.1'
        channel: stable
        cache: true
    - run: flutter pub get
    - name: Build unsigned IPA
      run: flutter build ipa --release --no-codesign
    - name: Rename IPA
      run: |
        VERSION=$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
        cp build/ios/ipa/Runner.ipa "build/ios/ipa/MAD-KG-v${VERSION}-unsigned.ipa"
    - uses: actions/upload-artifact@v4
      with:
        name: ios-ipa
        path: |
          build/ios/ipa/MAD-KG-*.ipa
          build/ios/ipa/Runner.ipa
        retention-days: 14
```

### 6.2 构建流程图

```
push master
    │
    ▼
┌─────────────────┐
│  analyze-test   │  ← 所有 PR 必跑（静态分析 + 单元测试）
│  ubuntu-latest  │
└────────┬────────┘
         │ 通过
    ┌────┼────┬────────┐
    ▼    ▼    ▼        ▼
┌────┐┌────┐┌──────┐┌────┐
│Web ││APK ││Win   ││iOS │  ← 并行构建
│    ││    ││exe   ││IPA │
└────┘└────┘└──────┘└────┘
```

### 6.3 构建产物

| Job | 产物 | 保留时间 |
|-----|------|---------|
| `build-ios` | `MAD-KG-v{版本}-unsigned.ipa` | 14 天 |
| `build-android` | `app-release.apk` | 14 天 |
| `build-web` | `build/web/` (自动部署 gh-pages) | 14 天 |
| `build-windows` | `build/windows/.../Release/` | 14 天 |

---

## 七、常见问题

### Q1：构建失败 "CocoaPods not installed"

GitHub Actions `macos-latest` 已预装 CocoaPods。若遇到版本问题：

```yaml
- name: Update CocoaPods
  run: sudo gem install cocoapods
```

### Q2：`sqflite_common_ffi` 导致 iOS 编译错误

项目使用平台条件导入，iOS 走 `sqflite` 平台 channel，`sqflite_common_ffi` 仅桌面端生效。若 CI 报 FFI 相关错误，确认 `pubspec.yaml` 中 `sqlite3_flutter_libs` 版本兼容。

### Q3：无签名 IPA 能直接安装吗？

不能。`--no-codesign` 产物仅验证编译通过，无法在真机安装。需完成第三章的证书配置才能安装到设备。

### Q4：如何支持更多设备？

新设备需将其 UDID 添加到 Apple Developer 后台的 Devices 列表，然后**重新生成 Provisioning Profile**，更新 `IOS_PROVISION_PROFILE` secret 后重新构建。

### Q5：Apple Developer 证书有效期

- Development 证书：1 年
- Distribution 证书：1 年
- Provisioning Profile（Development）：1 年
- Provisioning Profile（Ad Hoc）：1 年

到期前需重新生成并更新 GitHub Secrets。

### Q6：可否上传到 App Store？

可以。需要：
1. Distribution 证书（非 Development）
2. App Store Provisioning Profile
3. 构建命令改为 `--export-method=app-store`
4. 使用 Xcode Archive + `altool` 上传，或通过 App Store Connect API

```yaml
- name: Upload to App Store
  run: |
    xcrun altool --upload-app \
      -f build/ios/ipa/Runner.ipa \
      -t ios \
      -u "${{ secrets.APPLE_ID }}" \
      -p "${{ secrets.APP_SPECIFIC_PASSWORD }}"
```

### Q7：构建超时怎么办？

- `macos-latest` 默认 360 分钟上限，CI 中设置 `timeout-minutes: 60` 足够
- 若 `flutter pub get` 慢，可追加 pub cache 缓存步骤

---

## 八、可靠性与可用性审核（2026-06-01，第十三轮）

对照 `ios/` 工程真实配置、`.github/workflows/ci.yml`、`build-ios` 技能逐条核实，结论分两面。

### 8.1 现状评估

| 维度 | 状态 | 说明 |
|------|:----:|------|
| Flutter 工程骨架 | ✅ | `ios/Runner.xcodeproj` / `Info.plist` / `Podfile` / `AppIcon.appiconset` 齐全 |
| CI 编译验证 | ⚠️ 未验证 | `build-ios` job 已在 `f30070a73` 加入，但 `--no-codesign`、且尚无确认的绿灯运行 |
| 真机可装产物 | ❌ | CI 只产**无签名** IPA，无法直接装真机；需自备证书走第三章签名流程 |
| 签名凭证 | ❌ 未配置 | 仓库无任何 iOS 证书/Profile（与鸿蒙不同，鸿蒙已内置调试签名）；本机也无 Mac |
| Bundle ID 一致性 | ✅ 已统一 | 工程实为 `cn.edu.chzu.madkg`；本文档原写 `com.madkg.app`、技能文档原写 `cn.edu.chzu.madkgdt`（均已修正为 `cn.edu.chzu.madkg`）。注意鸿蒙端 `bundleName` 是 `cn.edu.chzu.madkgdt`（带 dt），与 iOS 是**两个独立的平台标识**，不冲突 |

### 8.2 本轮修正的文档错误

| 项 | 原（错误） | 现（正确，以工程为准） |
|----|-----------|----------------------|
| Bundle ID | `com.madkg.app` | `cn.edu.chzu.madkg`（`PRODUCT_BUNDLE_IDENTIFIER`） |
| 最低 iOS 版本 | 12.0（技能文档） | **13.0**（`ios/Podfile` + pbxproj `IPHONEOS_DEPLOYMENT_TARGET`） |

> Bundle ID 错值是高危项——填错会导致 `No profiles for '...' were found`，Provisioning Profile
> 永远匹配不上，构建/安装必失败。三处来源（本文档 / 技能 / 鸿蒙）历史上各写各的，已以
> `ios/Runner.xcodeproj` 的 `cn.edu.chzu.madkg` 为唯一真相。

### 8.3 可用性结论

- **现在能做到**：云端（GitHub Actions macOS runner）**验证 iOS 能编译通过**——这对"工程不退化"有价值，无需本地 Mac。
- **现在做不到**：产出能装真机的签名 IPA。卡在两个硬前提：① Apple Developer 账号；② 证书/Profile 配置（且签名步骤需在 `ci.yml` 启用，目前是 `--no-codesign`）。
- **要真机演示的最短路径**：申请 Apple 账号（教育账号免费，但只能装本机 7 天）→ 配 3 个 GitHub Secrets → 把 `ci.yml` 的 `--no-codesign` 换成第三章的签名构建 → 下载 IPA 装机。预计首次 2-4 小时。

### 8.4 仍待办（超本轮文档修正范围）

- [ ] 首次推送后到 GitHub → Actions 确认 `build-ios` 真能编译过（macOS runner 上 CocoaPods/sqflite 原生依赖是常见翻车点）
- [ ] 如需签名：补 `ios/ExportOptions.plist`（技能引用了它但文件不存在）或统一用 `--export-method` 方式
- [ ] 配 Apple Developer 账号 + 证书/Profile + 3 个 GitHub Secrets，把 `ci.yml` 的 `--no-codesign` 换成签名构建

---

## 九、快速检查清单

- [ ] Apple Developer 账号已开通（$99/年）
- [ ] 已创建 iOS Development 证书并导出 `.p12`
- [ ] 目标设备 UDID 已注册到 Apple Developer
- [ ] App ID 已创建（Bundle ID **精确等于** `cn.edu.chzu.madkg`）
- [ ] Provisioning Profile 已生成并下载
- [ ] 三个 GitHub Secrets 已配置
- [ ] CI 签名构建步骤已启用
- [ ] GitHub → Actions 确认 `build-ios` job 绿灯通过
- [ ] 构建成功 → 从 Artifacts 下载 IPA
- [ ] IPA 通过爱思助手 / Apple Configurator 安装到设备
- [ ] 设备设置中信任开发者证书
