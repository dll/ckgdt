---
name: build-wxmp
description: 构建微信小程序 + AppID 配置 + 体验版上传 + 提交审核。Flutter 用 weui_flutter 或编译为小程序。触发：用户说"构建小程序"/"打小程序"/"上传体验版"/"提交审核"。
---

# 构建微信小程序

## ⚠ 当前项目状态

**本项目目前不支持微信小程序原生构建** —— Flutter 官方未提供 wxmp 编译目标。

如果要做微信小程序版本，有 3 条路径（按可行性排）：

| 方案 | 工作量 | 评价 |
|---|---|---|
| **A. Flutter Web 嵌入小程序 web-view** | 1 小时 | 评比演示够用，但功能受限（不能用小程序 API）|
| **B. 用 Taro / uni-app 重写关键页** | 2-4 周 | 真正的小程序体验，工程量大 |
| **C. 等 Flutter Wechat 社区项目** | — | 还在早期，不可靠 |

## 方案 A：Flutter Web 嵌入小程序（推荐评比演示）

新建独立小程序工程，主页一个 web-view 指向 GitHub Pages：

### 1. 微信开发者工具创建工程

下载：https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html

新建项目 → AppID 注册：
- 学习用：可申请测试号（`https://mp.weixin.qq.com/wxopen/waregister?action=step1`）
- 正式：到 mp.weixin.qq.com 注册公众号 → 关联小程序

### 2. 业务域名白名单

mp.weixin.qq.com → 开发管理 → 开发设置 → 业务域名 / 服务器域名：
- 加 `https://dll.github.io`

⚠ web-view 不能跨域加载 GitHub Pages 直接的页面，必须**通过备案的自有域名**或微信认证后申请豁免。

**本项目 GitHub Pages 没法直接用 web-view** —— 需要：
- 自己买个域名（约 50 元/年）
- 备案（个人备案 7-15 天）
- 备案后域名加到小程序业务域名白名单
- GitHub Pages 自定义域名（仓库 Settings → Pages → Custom domain）

### 3. 简易 web-view 页面（如果你有备案域名）

```js
// pages/index/index.js
Page({
  data: {
    src: 'https://你的备案域名.com/mad-kgdt/'
  }
})
```

```html
<!-- pages/index/index.wxml -->
<web-view src="{{src}}" />
```

### 4. 体验版上传

1. 微信开发者工具 → 上传 → 填版本号 0.13.0
2. mp.weixin.qq.com → 版本管理 → 设置体验版
3. 把指定微信号加到体验成员列表

### 5. 提交审核（正式发布）

1. 版本管理 → 提交审核
2. 审核 1-7 天
3. 审核通过 → 发布

## ⚠ 已知坑

### 坑 1：未备案域名 web-view 加载失败
**现象**：web-view 白屏，开发工具控制台报 `not in domain list`
**修复**：必须备案 + 业务域名白名单。GitHub Pages 默认的 `dll.github.io` 不行。

### 坑 2：getSystemInfo / 系统能力受限
**根因**：web-view 内的 Web 是沙盒环境，不能调小程序 API（getUserInfo / payment / scan 等）

**变通**：通过 `<web-view>` 的 `bindmessage` + `JSBridge` 与小程序壳通信。

### 坑 3：体验版有效期
**现象**：体验版 X 天后失效
**修复**：定期"取消体验版 → 重新设置"。开发版（IDE 里的预览）每次都新，无失效。

## 方案 B：Taro 重写（真做就走这条）

```bash
npm install -g @tarojs/cli
taro init mad-kgdt-wxmp
# 选 React + TypeScript 模板
```

把核心交互（图谱浏览、测验、班级问答）用 React 重写：
- Flutter 90% UI / 业务逻辑用不上
- 但 Taro 可以一码三端（小程序 / H5 / RN）
- 后端用现有 Gitee 同步协议（HTTP API）

工程量：**2-4 周** 1 个全职。

## 方案 C：Flutter Wechat 社区项目

GitHub 上有 [flutter_wechat_miniprogram](https://github.com/...) 等尝试，但都还在概念阶段，**生产环境不可用**。

## 当前推荐

**评比演示**：直接告诉评委"本平台支持微信生态，但当前演示用桌面 / 鸿蒙 / Web 三端"。**不要花时间硬上小程序**。

如果真要做：
1. 备案一个域名（最低门槛）
2. 简易 web-view 壳工程（30 行 JS）
3. 评比时打开小程序 → 跳到 Web 版

## 升版同步（如有小程序工程）

| 文件 | 字段 |
|------|------|
| `wxmp/project.config.json` | `version` |
| `wxmp/app.json` | `pages` / `tabBar` 等 |

## 不要做的事

❌ **不要**幻想 `flutter build wxmp` —— 不存在
❌ **不要**用未备案域名的 web-view（必白屏）
❌ **不要**把 AppID + 小程序密钥 commit 到 git（敏感）
❌ **不要**为评比演示走 Taro 重写（工作量太大，不值得）
