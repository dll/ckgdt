---
name: build-web
description: 构建 Flutter Web + base href 子路径 + GitHub Pages 自动部署。触发：用户说"构建 Web"/"部署 gh-pages"/"Web 发布"/"更新 Pages"。
---

# 构建 Web + 部署 GitHub Pages

## 标准命令

```bash
# 关键：必须用 MSYS_NO_PATHCONV=1 防止 Git Bash 路径转换 + 必须带 /ckgdt/ base href
MSYS_NO_PATHCONV=1 flutter build web --release --base-href "/ckgdt/"
```

**产物**：`build/web/` 整个静态站

**包大小**：~39 MB

## ⚠ 已知坑

### 坑 1：base href 被 Git Bash 转成 Windows 路径

**现象**：`Received a --base-href value of "C:/Program Files/Git/ckgdt/"`

**根因**：MSYS / Git Bash 把 `/ckgdt/` 当成 Windows 绝对路径自动转换。

**修复**：命令前加 `MSYS_NO_PATHCONV=1`。

### 坑 2：base href 不带斜杠尾导致资源 404

**现象**：访问 `https://dll.github.io/ckgdt/` 看到白屏 / Console 报 `Failed to load resource main.dart.js`

**根因**：base href 写 `/ckgdt`（缺尾斜杠）→ 浏览器解析相对路径错误。

**正确写法**：`--base-href "/ckgdt/"`（**首尾各一个斜杠**）

### 坑 3：Manifest description 是默认 "A new Flutter project."

**根因**：Flutter create 时的占位文案没改。

**修复**：
- `web/index.html` 的 `<meta name="description">` 改中文项目说明
- `web/manifest.json` 的 `"description"` 改中文项目说明

### 坑 4：Web 空白 / 部分元素不显示 / 登录框空白

**现象**：GitHub Pages 部署后页面空白或只显示部分元素，登录区域全部空白。

**根因**：`canvaskit` 渲染器需要 `SharedArrayBuffer`（依赖 `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp` 头），**GitHub Pages 无法设置这些头**，导致 canvaskit 静默初始化失败。

**修复**：构建完成后需将 `flutter_bootstrap.js` 中的 `renderer` 从 `canvaskit` 改为 `html`，然后部署。

手工修复：
```bash
# 构建后执行（或在 deploy_web.ps1 里已自动完成）
powershell -Command "(Get-Content build/web/flutter_bootstrap.js -Raw) -replace '\"renderer\":\"canvaskit\"', '\"renderer\":\"html\"' | Set-Content build/web/flutter_bootstrap.js"
```

自动部署脚本：
```powershell
.\scripts\deploy_web.ps1
```

> **不要在 `web/index.html` 里尝试其他 hack**。`flutter_bootstrap.js` 是生成的，renderer 选择逻辑在 JS 层面。替换字符串是唯一可靠的方式。

### 坑 5：Web 公网 URL 跟局域网同步 URL 混淆

**根因**：项目内"三端互通"页之前显示局域网 IP（如 `http://192.168.1.105:8765`），但学生想访问 Web 版需要公网 URL。

**修复**：`lib/core/constants/app_urls.dart` 已集中管理：
- `AppUrls.webApp` = `https://dll.github.io/ckgdt/`（公网 Web 入口）
- 局域网同步用 `cross_platform/sync_server` 动态拿本机 IP，不写死

## 部署 GitHub Pages

仓库：`git@github.com:dll/ckgdt.git`，分支：`gh-pages`

**完整脚本**：
```bash
mkdir -p D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy
cp -r D:/FlutterProjects/knowledge_graph_app/build/web/. D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy/

git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy init -q -b gh-pages
# longpaths 处理 URL 编码后超长中文文件名
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy config core.longpaths true
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy add -A
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy \
    -c user.email="ldl@github" -c user.name="ldl" \
    commit -q -m "deploy: web v0.13.0 base=/ckgdt/"

git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy \
    remote add origin git@github.com:dll/ckgdt.git
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy \
    push -u --force origin gh-pages

# 清理
rm -rf D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy
```

**force-push 是合理的** —— gh-pages 不存代码历史，每次部署就是覆盖。

### GitHub SSH 账号

仓库归属 `dll` 账号；本机 SSH key 公钥 SHA256 `dcsptJoCqj1gL7X3fkvtAY0fwzN9uB7oAuFKPBx9y4Q` 关联到 `dll`。

如果以后账号变了，记得跑：
```bash
ssh -T git@github.com   # 应回复 "Hi dll!"
```

## 升版同步（v0.13 → v0.14）

| 文件 | 字段 |
|------|------|
| `web/index.html` | `<title>`、`apple-mobile-web-app-title`、`application-name`（描述不带版本号） |
| `web/manifest.json` | `"name"`（带版本号）；`"short_name"` 不带；`"description"` 不带 |

## 打包格式（zip 入 dist/）

```
dist/移动图谱与数字孪生+web+v0.13.0.zip
├── 整个 build/web/ 内容
└── 启动说明.txt
```

启动说明.txt 推荐内容：
```
=== 本地启动 Web 版（不联网时用）===

【方法 1：Python 内置 server】
解压后 cd 到目录，运行：
  python -m http.server 8080
浏览器访问：http://localhost:8080/ckgdt/  ← 注意 /ckgdt/ 子路径

【方法 2：Node serve】
  npx serve -s . -l 8080

【在线访问（无需下载）】
  https://dll.github.io/ckgdt/

默认账号：学生 2023211985/211985 / 教师 206004 / 管理员 419116
```

## CI/CD 自动部署

`.github/workflows/ci.yml` 已配 `deploy-web` job：master push 自动跑 + force-push 到 gh-pages。

但 GitHub Actions 部署有 **5-10 分钟生效延迟**（GitHub Pages CDN）。如果要快速看到改动，本地手动 push 更快。

## 不要做的事

❌ **不要**写 `--base-href "/ckgdt"`（缺尾斜杠 → 资源 404）
❌ **不要**忘 `MSYS_NO_PATHCONV=1`（路径会被改）
❌ **不要**改成 web/index.html 的 `<base href="$FLUTTER_BASE_HREF">` —— 这是 Flutter 占位符
❌ **不要**漏 description 中文化（manifest.json + index.html 各改一处）
