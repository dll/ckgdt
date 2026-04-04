# 0202 iOS原生开发技术图谱
*基于刘东良教授教学大纲制定*

## 图谱说明
本图谱基于《移动应用开发》课程第二章"原生开发基础"（3学时）和相关实验内容，系统梳理iOS原生开发所需的核心技术栈，注重Swift语言特性和现代开发实践。

## 1. 开发基础（对应课程第二章）

### 1.1 Swift编程语言掌握
- **Swift基础语法**
  - 变量与常量（var/let）
  - 基本数据类型（Int、Double、String、Bool）
  - 集合类型（Array、Dictionary、Set）
  - 控制流（if、for、while、switch）
  - 函数定义与调用
  - 闭包与高阶函数

- **Swift高级特性**
  - 可选类型（Optional）与安全解包
  - 协议导向编程（Protocol）
  - 扩展（Extension）机制
  - 泛型编程
  - 错误处理（Error Handling）
  - 内存管理（ARC自动引用计数）

- **面向对象编程**
  - 类与结构体区别
  - 继承与多态
  - 属性（存储属性、计算属性）
  - 方法与下标
  - 初始化器与析构器

### 1.2 开发环境搭建（对应实验1）
- **Xcode IDE掌握**
  - Xcode安装与配置
  - 项目创建与管理
  - Interface Builder可视化设计
  - 代码编辑器功能
  - 调试器使用技巧
  - 模拟器操作与管理

- **开发工具链**
  - Swift Package Manager依赖管理
  - CocoaPods第三方库管理
  - Git版本控制集成
  - Instruments性能分析工具
  - TestFlight测试分发

### 1.3 AI编程工具集成
- **GitHub Copilot在iOS开发中的应用**
  - Swift代码自动补全
  - UIKit API智能提示
  - SwiftUI组件生成
  - 单元测试代码辅助

- **CodeGeeX辅助开发**
  - 中文注释生成
  - 代码重构建议
  - 性能优化提示
  - 调试代码生成

## 2. 核心框架体系

### 2.1 UIKit框架精通（实验2重点）
- **视图控制器架构**
  - UIViewController生命周期深度理解
  - viewDidLoad、viewWillAppear、viewDidAppear
  - viewWillDisappear、viewDidDisappear
  - 视图控制器容器管理
  - 模态展示与导航控制

- **UINavigationController导航控制**
  - 导航栈管理
  - 导航栏定制
  - 导航转场动画
  - 返回按钮处理

- **UITabBarController标签控制**
  - 标签页配置
  - 标签栏定制
  - 页面切换管理
  - 徽章数字显示

### 2.2 基础UI组件掌握
- **文本与输入控件**
  - UILabel文本显示与样式
  - UITextField单行输入框
  - UITextView多行文本编辑
  - 输入验证与格式化
  - 键盘管理与响应

- **交互控件**
  - UIButton按钮设计与事件
  - UISwitch开关控制
  - UISlider滑块控件
  - UISegmentedControl分段控制

- **显示控件**
  - UIImageView图片显示
  - UIProgressView进度条
  - UIActivityIndicatorView活动指示器
  - UIScrollView滚动视图

### 2.3 Auto Layout布局系统
- **约束系统基础**
  - 约束创建与配置
  - 优先级设置
  - 约束冲突解决
  - 安全区域适配

- **现代布局技术**
  - UIStackView栈视图布局
  - Size Classes适配
  - 动态字体支持
  - 多设备屏幕适配

### 2.4 Foundation框架
- **数据类型与集合**
  - String字符串处理
  - Array数组操作
  - Dictionary字典管理
  - Set集合运算
  - Date日期时间处理

- **文件与数据处理**
  - FileManager文件管理
  - Data数据操作
  - JSON序列化与反序列化
  - Codable协议使用

## 3. 数据存储技术

### 3.1 本地存储方案
- **UserDefaults轻量存储**
  - 用户偏好设置保存
  - 应用配置信息存储
  - 数据类型支持
  - 同步与异步操作
  - 数据迁移策略

- **文件系统操作**
  - iOS沙盒机制理解
  - Documents目录使用
  - Library目录管理
  - tmp临时目录
  - 文件读写操作
  - 目录创建与删除

- **归档与序列化**
  - NSCoding协议实现
  - Codable协议使用
  - JSON数据处理
  - PropertyList存储
  - 自定义数据格式

### 3.2 数据库存储
- **SQLite数据库**
  - SQLite.swift框架使用
  - 数据库设计原则
  - 表结构创建与修改
  - CRUD操作实现
  - 事务处理机制
  - 数据库迁移

- **Core Data框架**
  - 数据模型设计
  - NSManagedObject实体
  - NSManagedObjectContext上下文
  - 数据获取与保存
  - 关系映射
  - 版本迁移

### 3.3 云端存储集成
- **iCloud同步**
  - iCloud Drive集成
  - CloudKit框架使用
  - 用户身份验证
  - 数据同步策略
  - 冲突解决机制

- **第三方云服务**
  - Firebase Firestore
  - AWS DynamoDB
  - 阿里云数据库
  - 腾讯云数据库

## 4. 网络编程技术

### 4.1 HTTP网络通信（重点内容）
- **URLSession原生网络框架**
  - URLSessionDataTask数据任务
  - URLSessionDownloadTask下载任务
  - URLSessionUploadTask上传任务
  - 后台传输配置
  - 缓存策略设置
  - 证书验证与安全

- **网络请求封装**
  - GET/POST请求构建
  - 请求头设置
  - 参数序列化
  - 响应数据解析
  - 错误统一处理
  - 重试机制实现

### 4.2 第三方网络库
- **Alamofire网络库**
  - 简化网络请求
  - 链式调用语法
  - 请求/响应拦截器
  - 文件上传下载
  - 网络状态监听

- **Moya网络抽象层**
  - 类型安全的网络层
  - Provider模式
  - 插件机制
  - 测试友好设计

### 4.3 JSON数据处理
- **Codable协议**
  - 自动序列化与反序列化
  - 自定义编码键
  - 嵌套对象处理
  - 可选属性处理
  - 日期格式转换

- **数据模型设计**
  - Struct vs Class选择
  - 可选类型使用
  - 默认值设置
  - 数据验证

## 5. 现代UI开发

### 5.1 SwiftUI声明式框架（重点）
- **SwiftUI基础组件**
  - Text文本组件
  - Image图片组件
  - Button按钮组件
  - TextField输入框
  - List列表组件
  - NavigationView导航视图

- **布局与容器**
  - VStack垂直堆栈
  - HStack水平堆栈
  - ZStack层叠堆栈
  - ScrollView滚动视图
  - LazyVGrid网格布局

- **状态管理**
  - @State局部状态
  - @Binding数据绑定
  - @ObservedObject观察对象
  - @EnvironmentObject环境对象
  - @StateObject状态对象

- **数据绑定与更新**
  - 单向数据流
  - 双向数据绑定
  - 数据驱动UI更新
  - 条件渲染
  - 列表数据绑定

### 5.2 传统UIKit开发
- **Storyboard可视化设计**
  - 界面拖拽设计
  - Segue页面跳转
  - IBOutlet属性连接
  - IBAction方法连接
  - 约束设置与调试

- **XIB文件复用**
  - 自定义视图组件
  - 组件封装复用
  - 动态加载XIB
  - 数据传递机制

### 5.3 动画与交互
- **UIKit动画**
  - UIView.animate基础动画
  - 关键帧动画
  - 转场动画
  - 弹簧动画
  - 自定义转场

- **SwiftUI动画**
  - 隐式动画
  - 显式动画
  - 转场效果
  - 路径动画
  - 组合动画

## 6. 图像与多媒体

### 6.1 图像处理技术
- **UIImage图像操作**
  - 图像加载与缓存
  - 图像缩放与裁剪
  - 图像格式转换
  - 圆角与蒙版处理

- **Core Graphics绘图**
  - 2D图形绘制
  - 贝塞尔曲线
  - 渐变填充
  - 文字渲染
  - PDF生成

- **第三方图像库**
  - Kingfisher图片缓存
  - SDWebImage异步加载
  - 图片压缩优化
  - 内存管理策略

### 6.2 相机与相册
- **系统相机调用**
  - UIImagePickerController使用
  - 相机权限请求
  - 拍照与录像功能
  - 图片编辑功能

- **Photos框架**
  - 相册访问权限
  - PHPhotoLibrary相册操作
  - PHAsset资源管理
  - 相册图片选择器

### 6.3 音视频处理
- **AVFoundation框架**
  - AVPlayer视频播放
  - AVAudioPlayer音频播放
  - 播放控制与进度
  - 音频会话管理
  - 后台播放设置

## 7. 设备功能集成

### 7.1 传感器与定位
- **Core Motion运动框架**
  - 加速度计数据获取
  - 陀螺仪方向检测
  - 磁力计数据处理
  - 运动数据分析
  - 步数统计功能

- **Core Location定位服务**
  - GPS定位功能
  - 位置权限管理
  - 地理围栏监听
  - 位置更新策略
  - 地理编码与反编码

### 7.2 系统服务集成
- **通知服务**
  - 本地通知创建
  - 远程推送配置
  - 通知权限申请
  - 通知内容定制
  - 通知响应处理

- **系统数据访问**
  - Contacts通讯录框架
  - EventKit日历事件
  - HealthKit健康数据
  - 权限请求与管理
  - 数据隐私保护

### 7.3 设备能力调用
- **Face ID与Touch ID**
  - 生物识别验证
  - LocalAuthentication框架
  - 安全策略配置
  - 失败处理机制

- **系统分享**
  - UIActivityViewController分享
  - 自定义分享活动
  - 分享内容配置
  - 社交媒体集成

## 8. 应用架构设计（课程目标4重点）

### 8.1 MVC架构模式
- **Model数据层**
  - 数据模型定义
  - 网络请求封装
  - 数据持久化
  - 业务逻辑处理

- **View视图层**
  - UIViewController作为Controller
  - UIView视图组件
  - 用户交互处理
  - 界面更新逻辑

- **Controller控制层**
  - 视图控制器职责
  - 数据与视图绑定
  - 用户事件响应
  - 页面导航控制

### 8.2 MVVM架构模式（推荐）
- **ViewModel业务层**
  - 业务逻辑封装
  - 数据格式化
  - 状态管理
  - 测试友好设计

- **数据绑定机制**
  - 属性观察（Property Observer）
  - 通知中心（NotificationCenter）
  - 委托模式（Delegate）
  - 闭包回调

- **响应式编程**
  - Combine框架使用
  - Publisher与Subscriber
  - 数据流管理
  - 异步操作处理

### 8.3 依赖注入与解耦
- **协议导向编程**
  - Protocol定义接口
  - 依赖抽象而非具体
  - 可测试性提升
  - 模块化设计

- **依赖注入容器**
  - Swinject框架使用
  - 服务注册与解析
  - 生命周期管理
  - 单元测试模拟

## 9. 性能优化技术

### 9.1 内存管理策略
- **ARC自动引用计数**
  - 强引用（Strong Reference）
  - 弱引用（Weak Reference）
  - 无主引用（Unowned Reference）
  - 循环引用检测与解决
  - 闭包循环引用处理

- **内存优化实践**
  - 对象生命周期管理
  - 大对象及时释放
  - 图片内存优化
  - 缓存策略设计
  - 内存警告处理

### 9.2 性能监控与分析
- **Instruments性能分析**
  - Time Profiler CPU分析
  - Allocations内存分析
  - Leaks内存泄漏检测
  - Network网络分析
  - Energy Log电量分析

- **性能指标监控**
  - 启动时间测量
  - 帧率监控
  - 内存使用监控
  - 网络性能分析
  - 电量消耗分析

### 9.3 UI性能优化
- **渲染优化**
  - 视图层级优化
  - 图片压缩与缓存
  - 异步渲染
  - 预加载策略
  - 滚动性能优化

- **启动速度优化**
  - 减少启动时间
  - 延迟初始化
  - 资源预加载
  - 启动画面优化

## 10. 测试与调试

### 10.1 单元测试实践
- **XCTest测试框架**
  - 测试用例设计
  - XCTAssert断言方法
  - 异步测试处理
  - 性能测试编写
  - 测试数据准备
  - Mock对象使用

- **测试驱动开发**
  - TDD开发流程
  - 测试先行理念
  - 重构与测试
  - 测试覆盖率分析

### 10.2 UI自动化测试
- **XCUITest UI测试**
  - 界面元素定位
  - 用户交互模拟
  - 断言验证
  - 可访问性测试
  - 截图对比测试

### 10.3 调试技能掌握
- **Xcode调试器**
  - 断点设置与管理
  - 变量监视窗口
  - 调用栈分析
  - 内存视图查看
  - 异常断点处理

- **LLDB命令行调试**
  - po命令打印对象
  - 表达式求值
  - 运行时修改
  - 调试脚本编写

- **日志与诊断**
  - os_log日志系统
  - 自定义日志分类
  - 控制台日志查看
  - 崩溃日志分析

## 11. 应用发布与部署

### 11.1 证书与签名配置
- **开发者账号管理**
  - Apple Developer账号注册
  - 团队成员管理
  - 设备注册管理
  - 证书生命周期

- **Code Signing代码签名**
  - 开发证书配置
  - 发布证书申请
  - Provisioning Profile配置
  - App ID标识符设置
  - 自动签名vs手动签名

### 11.2 App Store发布流程
- **App Store Connect管理**
  - 应用信息填写
  - 版本管理
  - 价格与销售范围
  - 应用内购买配置
  - TestFlight测试分发

- **审核与发布**
  - App Review Guidelines遵循
  - 隐私政策制定
  - 应用审核流程
  - 被拒常见原因
  - 版本更新管理

### 11.3 企业内部分发
- **Ad Hoc分发**
  - 测试设备管理
  - 内部测试流程
  - 分发链接生成
  - 安装问题排查

- **Enterprise分发**
  - 企业开发者账号
  - In-House应用分发
  - MDM管理部署
  - 企业应用更新

## 12. 学习路径与实践项目

### 12.1 基础阶段学习路径
1. **环境搭建**：Xcode安装与配置
2. **Swift语言**：语法基础与面向对象
3. **UI开发**：UIKit基础组件使用
4. **数据处理**：本地存储与网络请求
5. **调试技能**：断点调试与日志分析

### 12.2 进阶阶段学习路径
1. **SwiftUI掌握**：声明式UI开发
2. **架构设计**：MVVM模式应用
3. **性能优化**：内存管理与性能调优
4. **测试开发**：单元测试与UI测试
5. **发布部署**：App Store发布流程

### 12.3 推荐实践项目
- **天气应用**：网络请求、定位服务、SwiftUI界面
- **笔记应用**：Core Data数据库、搜索功能、云同步
- **照片管理**：相册访问、图片处理、分享功能
- **音乐播放器**：音频播放、媒体控制、后台播放

---

**制定依据**：刘东良教授《移动应用开发》教学大纲  
**适用课程**：第二章"原生开发基础"及相关实验  
**更新时间**：2025年8月  
**版本**：v2.0
