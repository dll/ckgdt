# MAD 知识图谱教学系统 — 三端部署说明

> 版本：v0.8.0 | 更新日期：2026-04-16

---

## 一、Android 端（APK）

### 构建

```bash
flutter build apk --release
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`（约 115 MB）

### 安装

1. **直接安装**：将 APK 传到手机，点击安装（需开启"允许安装未知来源应用"）
2. **ADB 安装**：
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```
3. **分发**：将 APK 上传到网盘/课程群，学生下载安装即可

### 注意事项

- 最低支持 Android 5.0（API 21）
- 首次启动会从 assets 复制预置数据库，约需 2-3 秒
- 如需缩小体积，可按 ABI 分包：
  ```bash
  flutter build apk --release --split-per-abi
  ```
  生成 arm64-v8a（约 50 MB）和 armeabi-v7a 两个包

---

## 二、Windows 端（桌面应用）

### 构建

```bash
flutter build windows --release
```

产物目录：`build\windows\x64\runner\Release\`

### 部署

1. **整体复制**：将 `build\windows\x64\runner\Release\` 整个文件夹复制到目标电脑
2. **运行**：双击 `knowledge_graph_app.exe` 即可启动
3. **打包分发**：将 Release 文件夹压缩为 ZIP，分发给用户解压使用

### 注意事项

- 需要 Windows 10 及以上（x64）
- 依赖 Visual C++ Redistributable（大多数 Windows 已预装）
- 如目标电脑缺少运行库，可从微软官网下载：https://aka.ms/vs/17/release/vc_redist.x64.exe

---

## 三、Web 端（浏览器访问）

Web 端是最便捷的部署方式，无需安装，浏览器打开即用。

### 构建

```bash
flutter build web --release
```

产物目录：`build/web/`（约 72 MB）

### 方式 A：一键启动（推荐，本地/教室演示）

项目已内置 Web 服务器，**双击即可启动**：

```
web_server/
├── knowledge_graph_web.exe    ← 双击运行
└── server.dart                ← 源码
```

**使用步骤**：

1. 确保 `build/web/` 目录已构建（执行过 `flutter build web --release`）
2. 双击 `web_server/knowledge_graph_web.exe`
3. 自动启动本地服务并打开浏览器，默认地址：`http://localhost:8080`
4. 按 `Ctrl+C` 停止服务

**自定义端口**：

```bash
web_server/knowledge_graph_web.exe --port 3000
```

**部署到其他电脑**：

将以下两个内容复制到同一目录：
```
目标文件夹/
├── knowledge_graph_web.exe    ← 从 web_server/ 复制
└── web/                       ← 从 build/web/ 复制
```
双击 exe 即可运行。

### 方式 B：Nginx 部署（服务器/长期运行）

适合部署到校园服务器，供全校师生访问。

1. **安装 Nginx**（以 Ubuntu 为例）：
   ```bash
   sudo apt update && sudo apt install nginx -y
   ```

2. **复制 Web 产物**：
   ```bash
   sudo cp -r build/web/* /var/www/html/mad/
   ```

3. **配置 Nginx**（`/etc/nginx/sites-available/mad`）：
   ```nginx
   server {
       listen 80;
       server_name your-domain.com;   # 或 IP 地址

       root /var/www/html/mad;
       index index.html;

       # Flutter Web SPA 路由支持
       location / {
           try_files $uri $uri/ /index.html;
       }

       # 静态资源缓存
       location ~* \.(js|css|png|jpg|jpeg|gif|ico|wasm)$ {
           expires 7d;
           add_header Cache-Control "public, immutable";
       }

       # WASM MIME 类型
       types {
           application/wasm wasm;
       }
   }
   ```

4. **启用站点并重启**：
   ```bash
   sudo ln -s /etc/nginx/sites-available/mad /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl restart nginx
   ```

5. **访问**：浏览器打开 `http://your-domain.com` 或 `http://服务器IP`

### 方式 C：Python 快速启动（临时演示）

无需任何额外工具，Python 3 自带 HTTP 服务器：

```bash
cd build/web
python -m http.server 8080
```

浏览器打开 `http://localhost:8080`。

> 注意：Python 简易服务器不支持 SPA 路由回退，仅适合临时演示。

### 方式 D：Docker 部署

```dockerfile
FROM nginx:alpine
COPY build/web /usr/share/nginx/html
EXPOSE 80
```

```bash
docker build -t mad-kg .
docker run -d -p 8080:80 mad-kg
```

### Web 端注意事项

| 项目 | 说明 |
|------|------|
| 浏览器兼容 | Chrome 88+、Edge 88+、Firefox 78+、Safari 15.4+ |
| 数据存储 | 使用 IndexedDB（浏览器本地），清除浏览器数据会丢失 |
| 首次加载 | 约 72 MB 资源，建议局域网或有线网络环境 |
| HTTPS | 生产环境建议配置 SSL 证书（Let's Encrypt 免费） |
| 视频播放 | Web 端视频功能受限，建议使用桌面端或移动端 |
| 语音功能 | Web 端不支持讯飞语音，TTS 使用浏览器原生 API |

---

## 四、快速对照表

| 项目 | Android | Windows | Web |
|------|---------|---------|-----|
| 构建命令 | `flutter build apk --release` | `flutter build windows --release` | `flutter build web --release` |
| 产物位置 | `build/app/outputs/flutter-apk/` | `build/windows/x64/runner/Release/` | `build/web/` |
| 产物大小 | ~115 MB（完整）/ ~50 MB（arm64） | ~60 MB（整个目录） | ~72 MB |
| 安装方式 | 直接安装 APK | 解压运行 exe | 浏览器访问 |
| 数据库 | SQLite 文件 | SQLite 文件 | IndexedDB |
| 最低要求 | Android 5.0 | Windows 10 x64 | 现代浏览器 |
| 离线使用 | 支持 | 支持 | 首次加载后支持 |

---

## 五、AI 功能配置

三端部署后，AI 功能（智能体对话、技能生成）需要配置 API Key：

1. 打开应用 → **设置** → **AI 配置**
2. 选择服务商（支持 13 个：DeepSeek / 智谱 / 通义千问 / Kimi / OpenAI 等）
3. 填入 API Key
4. 点击"测试连接"验证
5. 保存即可使用

> 推荐使用 **DeepSeek**（国内免费额度）或 **智谱 GLM-4-Flash**（免费）进行教学演示。

---

## 六、默认账号

| 角色 | 用户名 | 密码 |
|------|--------|------|
| 管理员 | 419116 | 419116 |
| 学生 | 学号 | 学号后 6 位 |

> 密码规则：用户 ID 的后 6 位。
