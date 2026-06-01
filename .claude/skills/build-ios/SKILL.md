---
name: build-ios
description: 构建 iOS IPA + 证书 + 描述文件 + TestFlight。需要 macOS。触发：用户说"构建 iOS"/"打 IPA"/"上传 TestFlight"/"提交 App Store"。
---

# 构建 iOS IPA

## ⚠ 前提：必须 macOS

iOS 构建**不能在 Windows / Linux 上做**。原因：
- 需要 Xcode（仅 macOS）
- 需要 codesign（仅 macOS / 限制版有 wineprefix 但极不稳）
- 需要 Apple Developer 账号 + 钥匙串

**当前项目状态**：`ios/Runner.xcodeproj` 等基础文件存在；`.github/workflows/ci.yml` 有 `build-ios` job 跑**无签名**编译验证（`--no-codesign`，commit `f30070a73` 加入，绿灯运行待 GitHub Actions 核实）。**尚未配置过签名**——无证书/Profile，无法产出可装真机的 IPA。

## 前置准备（一次性 setup）

### 1. Apple Developer 账号

- 个人账号：99 USD/年（可发 App Store + TestFlight）
- 教育账号：免费（仅可装本机 7 天，无法分发 — 评比演示够用）
- 企业账号：299 USD/年（内部分发，不进 App Store）

### 2. 证书 + 描述文件（macOS Keychain）

**自动方式（推荐）**：
1. Xcode → Preferences → Accounts → 添加 Apple ID
2. 打开 `ios/Runner.xcworkspace` → 选 Runner target → Signing & Capabilities
3. 勾 **Automatically manage signing**
4. 选 Team

**手动方式**（需要 admin team 角色）：
1. https://developer.apple.com/account → Certificates → 新建 iOS Distribution
2. Identifiers → 创建 App ID `cn.edu.chzu.madkg`
3. Profiles → 创建 Provisioning Profile（Distribution / App Store / Ad Hoc）
4. 下载 .mobileprovision 双击导入 Xcode

### 3. CocoaPods

```bash
sudo gem install cocoapods
cd ios && pod install --repo-update
```

国内推荐：
```bash
# Gemfile.sources 改清华镜像
gem sources --add https://gems.ruby-china.com/ --remove https://rubygems.org/
```

## 标准构建命令

### 调试构建（连真机）
```bash
flutter run -d <device-id>
```

### 无签名验证编译（当前 CI 方式）
```bash
flutter build ipa --release --no-codesign
```
产物仅验证编译通过，不可装真机。

### 签名构建（需 Apple 证书）

方式一（`--export-method`，**推荐**，无需额外文件）：
```bash
flutter build ipa --release --export-method=development   # 开发包
flutter build ipa --release --export-method=ad-hoc         # 内测分发
flutter build ipa --release --export-method=app-store      # 上架 App Store
```

方式二（`ExportOptions.plist`，需自建文件）：
```bash
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

**产物**：`build/ios/ipa/Runner.ipa`

> **注意**：`ios/ExportOptions.plist` **不存在**于仓库中（已 gitignore，含 teamID 不该 commit）。
> 签名前需手动创建该文件，内容如下：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>  <!-- 或 ad-hoc / development / enterprise -->
    <key>teamID</key>
    <string>XXXXXXXXXX</string>  <!-- 10 位 Team ID -->
</dict>
</plist>
```

## 升版同步

| 文件 | 字段 |
|------|------|
| `ios/Runner/Info.plist` | `CFBundleShortVersionString` 与 `pubspec.yaml` 的 `version` 主版本号（如 `1.16.2`）对齐 |
| `ios/Runner/Info.plist` | `CFBundleVersion` = build number，每次上传递增 |
| `ios/Runner/Info.plist` | `CFBundleDisplayName` "移动图谱与数字孪生"（窗口标题由 `BuildInfo.appBrand` 控制） |

**不要改**：
- `CFBundleIdentifier`（一旦提交 App Store 不可变；本项目 = `cn.edu.chzu.madkg`，以 `ios/Runner.xcodeproj` 的 `PRODUCT_BUNDLE_IDENTIFIER` 为准）

## 上传 TestFlight

### Xcode GUI
1. Product → Archive
2. Window → Organizer → 选刚才的 Archive → Distribute App
3. App Store Connect → Upload

### 命令行
```bash
xcrun altool --upload-app --type ios \
  -f build/ios/ipa/移动图谱与数字孪生.ipa \
  -u <apple-id> \
  -p <app-specific-password>
```

**等 5-15 分钟** App Store Connect 处理后，TestFlight 内部测试组就能装。

## ⚠ 已知坑（基于行业经验）

### 坑 1：Provisioning Profile 不匹配
**现象**：`No profiles for 'cn.edu.chzu.madkg' were found`
**修复**：
- 删 `~/Library/MobileDevice/Provisioning Profiles/*` 让 Xcode 重下
- 或在 developer.apple.com 重新生成 profile，确保 App ID 完全匹配

### 坑 2：Pod install 卡住
**现象**：`pod install` 在 `Updating CocoaPods specs repo` 卡 30+ 分钟
**修复**：
```bash
pod install --verbose --no-repo-update  # 跳过 repo 更新
```

### 坑 3：Bitcode 已弃用
**现象**：Xcode 14+ 报 `Building with bitcode is deprecated`
**修复**：Build Settings → Enable Bitcode → No

### 坑 4：minimum iOS version
**当前**：`Podfile` 第一行 `platform :ios, '13.0'` —— iOS 13+（pbxproj `IPHONEOS_DEPLOYMENT_TARGET` 也是 13.0）
**注意**：升 iOS 13/14 会让一部分老设备装不上

### 坑 5：图标缺失
**现象**：上传后 App Store Connect 报 `Missing 1024x1024 icon`
**修复**：`ios/Runner/Assets.xcassets/AppIcon.appiconset/` 必须有所有尺寸

## 真机调试（macOS）

```bash
# 列设备
flutter devices

# 装到指定设备
flutter run -d <udid>
```

## 不要做的事

❌ **不要**在 Windows 跑 iOS 构建（绝对不可能）
❌ **不要** commit `*.mobileprovision` / `*.p12` / `ExportOptions.plist`（含 teamID 也不该 commit）
❌ **不要**改 `CFBundleIdentifier`（一旦发布锁死）
❌ **不要**忘 build number 递增（CFBundleVersion；TestFlight 会拒重复）
❌ **不要** Bitcode（已废弃）

## 当前优先级

⚠ **本项目 iOS 端目前未配置过**。如果评比要 iOS demo：
1. 借/租一台 Mac（或用云 Mac 服务如 MacInCloud）
2. 申请 Apple Developer 账号（教育账号免费）
3. 配证书 + ExportOptions.plist
4. 跑 `flutter build ipa`
5. 上传 TestFlight 让评委装

预计工作量：**2-4 小时**（首次配置）+ **30 分钟/次**（后续构建）。
