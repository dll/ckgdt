---
name: build-ohos
description: 构建 HarmonyOS HAP 包 + 签名 + 安装。处理 OpenHarmony 调试签名、模拟器 ABI 死坑、Flutter ohos 工具链特殊命令。触发：用户说"构建鸿蒙"/"打 HAP"/"鸿蒙签名"/"安装到鸿蒙"。
---

# 构建 HarmonyOS HAP

## ⚠ 不可再犯的天坑（按踩过的次数排）

### 坑 1：模拟器装不了 — ABI 死局（已踩 3 次，浪费 2 小时）

**现象**：模拟器装 HAP 报 `code:9568347 install parse native so failed`

**根因**：
- 华为官方手机模拟器（Pura 90 等）只发 **x86_64 镜像**（`abi: x86`）
- flutter_ohos 工具链**只编 arm64-v8a 引擎**（`flutter/bin/cache/artifacts/engine/` 仅有 `ohos-arm64-release`，**无 ohos-x86 / ohos-x64**）
- 两者 ABI 永远不匹配 → 模拟器永远装不了 Flutter 编译的 HAP

**结论**：**不要再尝试鸿蒙模拟器装 Flutter HAP**。直接用真机演示。

**真机要求**：任何 HarmonyOS NEXT 设备（Mate 60 / Pura 70 / 平板 / Vision），ABI 都是 arm64-v8a，永远兼容。

### 坑 2：模拟器 OS 卡 Logo（已踩 2 次）

**现象**：DevEco Device Manager 启动模拟器，鸿蒙 Logo 转圈不停，hdc list targets 永远 `[Empty]`

**诊断顺序**：
```bash
tasklist.exe | grep -iE "vmware|qemu|emulator"
```

**真因**：VMware 服务（`vmware-authd.exe` / `vmware-usbarbitrator64.exe`）独占 VT-x，鸿蒙模拟器（基于 QEMU）拿不到虚拟化加速。

**解决**：任务管理器 → 服务 → 停 VMware Authorization Service / VMware USB Arbitration Service。或启用 Windows Hypervisor Platform 并重启系统。

但鉴于坑 1 ——**模拟器即使启动也装不了 HAP**——根本不该花时间修这个。

### 坑 3：签名不生效（已踩 1 次）

**现象**：hvigor 报 `WARN: No signingConfig found for product default` + `Finished :entry:default@SignHap... after 4 ms`（正常应该 8-10 秒）

**根因**：DevEco Studio 自动生成签名时只写 `app.signingConfigs[0].name = "default"`，但**没把 `"signingConfig": "default"` 关联到 `app.products[0]`**。

**修复**：`ohos/build-profile.json5` 的 products[0] 加一行 `"signingConfig": "default"`。

### 坑 4：material 目录漏拷

**现象**：build 报 `ENOENT: no such file or directory, stat '...ohos\signature\material'`

**根因**：DevEco 自动签名生成的 `~/.ohos/config/openharmony/material/` 是 hvigor 内部状态目录（`ac/ce/fd` 三个哈希分桶），必须**整个**复制进工程。

**修复**：`cp -r ~/.ohos/config/openharmony/material ohos/signature/`

### 坑 5：versionCode 倒退

**现象**：DevEco Studio 重置 `app.json5` 的 `versionCode` 为 1（项目本来是 13）。

**根因**：DevEco 某些操作会重置 versionCode；versionCode 必须**只增不减**否则鸿蒙系统拒绝升级。

**修复**：手动改回 `versionCode = 13`（与 versionName `0.13.0` 对齐）。

---

## 当前工程状态（v0.13.0）

| 项 | 值 |
|----|----|
| bundleName | `cn.edu.chzu.madkgdt` |
| versionCode | 13 / versionName 0.13.0 |
| compatibleSdkVersion | 13（兼容 NEXT 5+）|
| targetSdkVersion | 20 |
| 签名状态 | OpenHarmony 调试签名（仅可装开启开发者模式的设备）|
| 签名凭证位置 | `ohos/signature/{debug.cer, debug.p7b, debug.p12, material/}` |
| build-profile.json5 | 用 `./signature/*` 相对路径，团队成员 clone 后无需重签 |

---

## 标准构建命令

```bash
# 完整构建（patch lib/ → flutter pub get → assembleHap → 还原 lib/）
./build_ohos.bat

# 或者直接 hvigor（需要 lib/ 已 patch 过）
cd ohos
hvigorw clean assembleHap -p product=default -p buildMode=release --no-daemon
```

**产物路径**：
- 已签名：`ohos/entry/build/default/outputs/default/entry-default-signed.hap` ← 用这个
- 未签名：`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`

**约 70-72 MB**，不含 x86 引擎（不会跑模拟器，故无需）。

---

## 真机安装

```bash
HDC="/d/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"

# 1. 真机开发者模式 → 设置 → 关于本机 → 软件版本号点 7 次
# 2. 设置 → 系统 → 开发者选项 → USB 调试

# 3. 验证连接
"$HDC" list targets
# 应输出类似：xxxxxxx-xxxx 之类的设备 ID

# 4. 安装
"$HDC" install -r ohos/entry/build/default/outputs/default/entry-default-signed.hap

# 5. 启动应用（手动点桌面图标 或 hdc shell aa start）
"$HDC" shell aa start -a EntryAbility -b cn.edu.chzu.madkgdt
```

**故障排查**：

| 错误 code | 原因 | 修复 |
|---|---|---|
| 9568293 | check syscap failed（HAP API 高于设备）| 设备升级 / 降低 compatibleSdkVersion |
| 9568347 | install parse native so failed（ABI 不匹配）| **真机替换模拟器** |
| 永远 hang | hdc 端口被占 | `hdc kill && hdc start` 重启 server |

---

## 升版同步（与其它端联动）

升 0.13 → 0.14 时，鸿蒙端必改的字段（与 CLAUDE.md "升版同步表" 配合）：

| 文件 | 字段 |
|------|------|
| `ohos/AppScope/app.json5` | `versionName` "0.14.0"、`versionCode` 14（**只增不减**）|
| `ohos/AppScope/resources/base/element/string.json` | `app_name`（如带版本号）|

**不要改**：
- `bundleName`（一旦发布商用版会变成升级 vs 新装的关键）
- `vendor`（公司名稳定）

---

## DevEco Studio 设置签名（首次配置）

新机器 / 团队成员：本仓库已经把签名凭证 commit 进 `ohos/signature/` 了，不需要做这步。

但如果证书过期 / 想重置：

1. 打开 DevEco → File → Open → `ohos/`
2. File → Project Structure → Signing Configs → 勾 **Automatically generate signature** → 华为账号登录
3. 4 个文件出现在 `~/.ohos/config/openharmony/`
4. 复制到 `ohos/signature/` 并改名 debug.cer/p7b/p12 + 整个 material 目录
5. `ohos/build-profile.json5` material 内 keyPassword/storePassword 复制过来
6. 检查 `products[0]` 有 `"signingConfig": "default"`

---

## 打包发布（zip 入 dist/）

构建完后用统一打包格式（参见 release-all 技能）：

```
dist/移动图谱与数字孪生+harmonyos+v0.13.0.zip
└── 移动图谱与数字孪生-v0.13.0.hap   （已签名 HAP，72M）
└── 安装说明.txt                      （含真机限制说明、错误码、默认账号）
```

**安装说明.txt 必须包含的内容**：
- ⚠ 模拟器不兼容（ABI 不匹配的明确警告）
- 真机开发者模式步骤
- hdc install 命令
- 默认账号
- 5 类错误码故障排查

---

## 不要做的事

❌ **不要**尝试鸿蒙模拟器装 HAP（坑 1，物理上不可能）
❌ **不要**直接 commit `~/.ohos/config/openharmony/` 绝对路径到 build-profile.json5（坑：别的机器 clone 后构建必失败）
❌ **不要**降低 versionCode（坑：鸿蒙系统拒绝升级）
❌ **不要**漏拷 `material/` 目录（坑：SignHap 失败）
❌ **不要**忘了 `products[0].signingConfig: "default"`（坑：签名跳过）
❌ **不要**花时间修虚拟化让模拟器跑起来（即使跑起来也装不了 HAP）
