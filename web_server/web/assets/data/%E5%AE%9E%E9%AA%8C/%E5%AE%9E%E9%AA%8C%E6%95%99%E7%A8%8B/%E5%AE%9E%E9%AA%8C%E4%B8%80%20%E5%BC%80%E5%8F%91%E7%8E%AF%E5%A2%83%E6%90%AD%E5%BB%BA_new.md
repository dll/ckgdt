# 实验一：移动应用开发环境搭建

## 实验项目基本信息

- **实验编号**：d20301035101、d20301009201
- **学时分配**：2学时
- **实验类型**：验证型
- **每组人数**：6人
- **对应课程目标**：课程目标1

## 🎯 核心步骤列表

### 📋 实验概览
1. **需求分析阶段**：明确各平台环境依赖与版本要求
2. **环境搭建阶段**：下载安装6大主流开发工具
3. **AI辅助编码阶段**：使用TRAE生成Hello World模板代码
4. **测试验证阶段**：在模拟器/真机上验证项目运行
5. **部署运维阶段**：记录环境配置文档，总结常见问题

### 🛠️ 开发工具清单
| 序号 | 开发工具 | 主要用途 | 验证项目 |
|------|----------|----------|----------|
| 1 | Android Studio | Android原生开发 | Kotlin HelloWorld |
| 2 | Flutter SDK | 跨平台开发 | Dart HelloWorld |
| 3 | 微信开发者工具 | 小程序开发 | 微信小程序HelloWorld |
| 4 | DevEco Studio | 鸿蒙应用开发 | HarmonyOS HelloWorld |
| 5 | HBuilderX | Uniapp开发 | Vue HelloWorld |
| 6 | Visual Studio | MAUI开发 | C# HelloWorld |

### ✅ 成功标准
- [ ] 6个开发工具成功安装并启动
- [ ] 6个HelloWorld项目成功创建
- [ ] 所有项目成功编译运行
- [ ] 模拟器/真机调试正常
- [ ] 环境配置文档完整

---

## 实验任务与案例

### 核心任务
搭建完整的移动应用开发工具链，根据组内分工完成对应平台环境配置，使用AI辅助生成Hello World模板代码，验证各平台开发环境可用性。

### 实战案例
组内6名成员分别负责一个技术栈，创建并运行"智慧校园"主题的HelloWorld项目，掌握从环境搭建到项目部署的完整流程，并输出环境配置文档。

---

## 第一课时：环境准备与工具安装（1学时）

### 1.1 需求分析阶段

#### 步骤1：明确环境依赖要求
1. **Android开发环境**
   - JDK 17+
   - Android Studio 2024.1+
   - Android SDK 34+

2. **Flutter开发环境**
   - Flutter 3.19+
   - Dart 3.3+

3. **鸿蒙开发环境**
   - DevEco Studio 5.0+
   - HarmonyOS SDK 5.0+

4. **Uniapp开发环境**
   - HBuilderX 4.0+
   - Node.js 18+

5. **MAUI开发环境**
   - Visual Studio 2022
   - .NET 8.0

6. **微信小程序开发环境**
   - 微信开发者工具

### 1.2 Android Studio环境搭建

#### 步骤1：下载与安装
1. 访问官网：https://developer.android.com/studio
2. 下载Windows/macOS版本
3. 运行安装程序，勾选：
   - Android Studio
   - Android SDK
   - Android Virtual Device
4. 完成安装

#### 步骤2：配置验证
1. 启动Android Studio
2. 创建Empty Activity项目
3. 使用AI辅助生成HelloWorld代码

### 1.3 Flutter环境搭建

#### 步骤1：下载Flutter SDK
1. 访问：https://flutter.dev/docs/get-started/install
2. 下载对应系统版本
3. 解压到指定目录（如：D:\flutter）
4. 添加到系统PATH环境变量

#### 步骤2：配置验证
1. 运行`flutter doctor`检查环境
2. 创建Flutter项目：`flutter create hello_flutter`
3. 使用AI辅助生成Dart代码

---

## 第二课时：多平台环境配置与验证（1学时）

### 2.1 鸿蒙开发环境搭建

#### 步骤1：下载DevEco Studio
1. 访问：https://developer.harmonyos.com/
2. 下载DevEco Studio
3. 完成安装

#### 步骤2：创建鸿蒙项目
1. 启动DevEco Studio
2. 创建Empty Ability项目
3. 使用AI辅助生成ArkTS代码

### 2.2 Uniapp开发环境搭建

#### 步骤1：安装HBuilderX
1. 访问：https://www.dcloud.io/hbuilderx.html
2. 下载HBuilderX
3. 完成安装

#### 步骤2：创建Uniapp项目
1. 新建uni-app项目
2. 使用AI辅助生成Vue代码

### 2.3 MAUI开发环境搭建

#### 步骤1：安装Visual Studio
1. 安装Visual Studio 2022
2. 勾选".NET MAUI" workload

#### 步骤2：创建MAUI项目
1. 新建.NET MAUI项目
2. 使用AI辅助生成C#代码

### 2.4 微信小程序开发环境

#### 步骤1：安装微信开发者工具
1. 访问：https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html
2. 下载并安装
3. 扫码登录

#### 步骤2：创建小程序项目
1. 新建小程序项目
2. 使用AI辅助生成小程序代码

### 2.5 测试验证阶段

#### 步骤1：编译运行验证
1. 在各自模拟器上运行HelloWorld
2. 记录运行结果

#### 步骤2：问题排查与解决
1. 汇总常见问题
2. 讨论解决方案

---

## 总结与思考

### 实验总结
- 掌握6大主流移动开发工具的安装配置
- 了解各平台的HelloWorld创建流程
- 体验AI辅助代码生成工具的使用
- 完成环境配置文档的编写

### 课后思考
1. 各开发工具的优缺点分析
2. 如何根据项目需求选择合适的开发工具
3. AI辅助开发对效率的提升分析
