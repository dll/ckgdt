# CKGDT 构建 Web 应用指南

> **课程知识图谱与数字孪生平台 — Web 端构建与 GitHub Pages 部署**

---

## 一、概述

CKGDT 是 Flutter 全平台项目，Web 端编译为 **JavaScript（dart2js）**，部署在 **GitHub Pages** 公网访问。

| 项目 | 说明 |
|------|------|
| 构建方式 | 本地 `flutter build web --release` 或 GitHub Actions `ubuntu-latest` |
| 成本 | 公开仓库免费（GitHub Pages 免费托管） |
| 触发方式 | push `master` 分支自动构建 + 自动部署 gh-pages |
| 产物格式 | 静态 HTML/CSS/JS 文件 |
| 产物命名 | `课程知识图谱与数字孪生+web+v{版本}.zip`（含启动说明） |
| 公网地址 | https://dll.github.io/mad-fd/ |
| Base Href | `/mad-fd/`（**首尾必须各有一个斜杠**） |
| Flutter 版本 | 3.35.1 |
| 包大小 | ~39 MB（zip） |

> **当前 CI 状态（2026-06-01，v1.17.0）**：`build-web` + `deploy-web` job **已持续通过**。
> 每次 push master 自动构建 → 自动部署 gh-pages，5-10 分钟后生效。

---

## 二、前置准备

### 2.1 本地构建环境

```bash
flutter doctor -v
# 确认 Web 端（Chrome）显示 ✓
```

### 2.2 GitHub Pages 配置

仓库 `git@github.com:dll/mad-fd.git`，部署分支 `gh-pages`，本机需配置 SSH key：
```bash
ssh -T git@github.com   # 应回复 "Hi dll!"
```

---

## 三、构建与部署

### 3.1 本地构建

```bash
# Windows PowerShell：用 $env: 绕过 Git Bash 路径转换
$env:MSYS_NO_PATHCONV = '1'
flutter build web --release --base-href "/mad-fd/"
```

**关键参数**：
- `--base-href "/mad-fd/"` — 必须带首尾斜杠，否则资源 404
- `MSYS_NO_PATHCONV=1` — 防止 Git Bash 把 `/mad-fd/` 转成 Windows 路径

产物：`build/web/` 整个目录。

### 3.2 本地测试

```bash
cd build/web
python -m http.server 8080
# 浏览器访问：http://localhost:8080/mad-fd/  ← 注意 /mad-fd/ 子路径
```

或用 Node.js：
```bash
npx serve -s build/web -l 8080
```

### 3.3 部署 GitHub Pages

```bash
mkdir -p build/_gh-pages-deploy
cp -r build/web/* build/_gh-pages-deploy/

git -C build/_gh-pages-deploy init -q -b gh-pages
git -C build/_gh-pages-deploy config core.longpaths true
git -C build/_gh-pages-deploy add -A
git -C build/_gh-pages-deploy \
    -c user.email="ldl@github" -c user.name="ldl" \
    commit -q -m "deploy: web v1.17.0 base=/mad-fd/"

git -C build/_gh-pages-deploy remote add origin git@github.com:dll/mad-fd.git
git -C build/_gh-pages-deploy push -u --force origin gh-pages

rm -rf build/_gh-pages-deploy
```

> **force-push 是合理的**：gh-pages 不存历史，每次部署就是覆盖。

### 3.4 CI 自动部署

`.github/workflows/ci.yml` 已配置 `deploy-web` job：push master 自动：
1. 构建 `build/web`
2. force-push 到 `gh-pages` 分支
3. 5-10 分钟后 https://dll.github.io/mad-fd/ 生效

---

## 四、用户访问方式

### 4.1 在线访问（推荐）

**https://dll.github.io/mad-fd/** — 手机/电脑浏览器直接打开，无需安装。

### 4.2 离线本地启动

下载 `课程知识图谱与数字孪生+web+v{版本}.zip`，解压后：

**方法 1 — Python**：
```bash
cd 解压目录
python -m http.server 8080
# 访问 http://localhost:8080/mad-fd/
```

**方法 2 — Node.js**：
```bash
npx serve -s . -l 8080
```

---

## 五、CI 工作流程详解

### 5.1 构建 Job

```yaml
build-web:
  name: Build Web
  if: github.event_name == 'push'
  needs: analyze-test
  runs-on: ubuntu-latest
  timeout-minutes: 30
  steps:
    - uses: actions/checkout@v4
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.35.1'
        channel: stable
        cache: true
    - run: flutter pub get
    - name: Build web with /mad-fd/ base
      run: flutter build web --release --base-href "/mad-fd/"
    - uses: actions/upload-artifact@v4
      with:
        name: web-build
        path: build/web/
        retention-days: 14
```

### 5.2 部署 Job

```yaml
deploy-web:
  name: Deploy Web to GitHub Pages
  if: github.event_name == 'push' && github.ref == 'refs/heads/master'
  needs: build-web
  runs-on: ubuntu-latest
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@v4
    - uses: actions/download-artifact@v4
      with:
        name: web-build
        path: build/web
    - name: Deploy to gh-pages branch
      uses: peaceiris/actions-gh-pages@v4
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        publish_dir: ./build/web
        publish_branch: gh-pages
        force_orphan: true
```

### 5.3 版本号同步（3 处）

| 文件 | 字段 |
|------|------|
| `web/index.html` | `<title>` / `apple-mobile-web-app-title` / `application-name` |
| `web/manifest.json` | `"name"`（带版本号） |
| `web/manifest.json` | `"short_name"`（**不带版本号**） |

> 升版时由 `VersionBumpService.applyVersion()` 自动同步。

---

## 六、常见问题

### Q1：访问白屏 / Console 报 `Failed to load main.dart.js`

**根因**：`--base-href` 写错。
- ❌ `/mad-fd`（缺尾斜杠） → 404
- ✅ `/mad-fd/`（带尾斜杠）

### Q2：`MSYS_NO_PATHCONV=1` 报错

在 Git Bash 中 `/mad-fd/` 被转换为 Windows 路径。用 PowerShell 或 CMD 构建，或在命令前加 `MSYS_NO_PATHCONV=1`。

### Q3：Web 构建报 `dart:ffi` 警告

`media_kit` 使用 FFI，Web 不支持。这是 **警告非错误**，不影响 Web 构建和运行。Web 端视频功能有限。

### Q4：GitHub Pages 部署后未更新

GitHub Pages CDN 有 5-10 分钟缓存。强制刷新：`Ctrl+Shift+R` 或等待。

### Q5：本地测试看不到资源

必须从 `/mad-fd/` 子路径访问。`http://localhost:8080/` 会导致资源路径错误。

---

## 七、可靠性与可用性审核（2026-06-01）

| 维度 | 状态 | 说明 |
|------|:----:|------|
| 本地构建 | ✅ | `flutter build web --release` 持续通过 |
| CI 构建 | ✅ | GitHub Actions `ubuntu-latest` + 自动部署 |
| GitHub Pages | ✅ | https://dll.github.io/mad-fd/ 可访问 |
| Base href | ✅ | `/mad-fd/` 首尾斜杠正确 |
| Renderer | ✅ | HTML renderer（已从 canvaskit 切换） |
| 版本号 | ✅ | 3 处同步（index.html + manifest.json） |
| 包大小 | 39 MB | zip 后 ~39 MB |

### 关键踩坑

| # | 问题 | 根因 | 修复 |
|---|------|------|------|
| 1 | 资源 404 | base href 缺尾斜杠 | 固定 `/mad-fd/` |
| 2 | Git Bash 路径转换 | MSYS 自动转换 `/mad-fd/` | `MSYS_NO_PATHCONV=1` |
| 3 | CI deploy-web 硬编码版本 | commit message 写死 `v0.12.0` | 改为动态消息 |
| 4 | canvaskit 渲染问题 | 默认 renderer 在某些浏览器异常 | 改为 html renderer |

---

## 八、快速检查清单

- [ ] `flutter doctor` 显示 Web 端 ✓
- [ ] `flutter build web --release --base-href "/mad-fd/"` 本地通过
- [ ] 本地 `python -m http.server 8080` 能访问
- [ ] GitHub Actions `build-web` + `deploy-web` job 绿灯
- [ ] https://dll.github.io/mad-fd/ 能打开
- [ ] `web/index.html` + `web/manifest.json` 版本号对齐
