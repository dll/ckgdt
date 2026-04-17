import 'package:flutter/material.dart';
import '../../../services/ai_service.dart';
import '../../../data/local/quiz_dao.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../services/auth_service.dart';
import '../../widgets/markdown_bubble.dart';

/// 深度实践中心 — 每章提供多层次深入学习内容
/// 借鉴天天向上"学前-学中-学后"闭环，解决课时不足问题
class DeepPracticePage extends StatefulWidget {
  const DeepPracticePage({super.key});

  @override
  State<DeepPracticePage> createState() => _DeepPracticePageState();
}

class _DeepPracticePageState extends State<DeepPracticePage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _quizDao = QuizDao();
  final _learningRecordDao = LearningRecordDao();

  // 章节深度内容定义
  static const _chapters = [
    _ChapterDeepContent(
      chapter: '第1章',
      title: '移动应用开发技术体系全景',
      icon: Icons.panorama_wide_angle,
      color: Colors.blue,
      sections: [
        _DeepSection(
          title: '知识拓展：移动开发演进史',
          icon: Icons.history_edu,
          content: '从 Symbian → Windows Mobile → iOS/Android → 跨平台 → 鸿蒙分布式，'
              '了解每个时代的代表性技术栈、市场份额演变与技术驱动力。',
          keyPoints: [
            '2007：iPhone 发布，触屏革命',
            '2008：Android 开源生态启动',
            '2015：React Native 开启跨平台新时代',
            '2018：Flutter 1.0 发布，高性能跨平台',
            '2020：HarmonyOS 分布式理念',
            '2023：Kotlin Multiplatform 进入稳定版',
          ],
          practiceQuestions: [
            '原生开发与跨平台开发各自的适用场景是什么？',
            '为什么 Google 在已有 Android 的情况下还要推出 Flutter？',
            '分布式应用与传统移动应用的本质区别是什么？',
          ],
        ),
        _DeepSection(
          title: '核心概念：技术选型决策矩阵',
          icon: Icons.grid_on,
          content: '掌握移动开发技术选型的 5 维度评估模型：性能、开发效率、生态成熟度、'
              '团队技能匹配度、长期维护成本。',
          keyPoints: [
            '性能：原生 > Flutter > React Native > 小程序',
            '开发效率：Flutter ≈ RN > 原生 > 小程序',
            '生态成熟度：原生 > RN > Flutter > 鸿蒙',
            '学习曲线：小程序 < Flutter < RN < 原生双端',
            '企业案例：闲鱼(Flutter)、京东(RN)、微信(小程序)',
          ],
          practiceQuestions: [
            '为一个社交类 APP 选择技术栈，请给出你的决策过程。',
            '创业公司 MVP 阶段应优先考虑哪些技术选型因素？',
          ],
        ),
        _DeepSection(
          title: '动手练习：技术调研报告',
          icon: Icons.assignment,
          content: '选择一个你感兴趣的移动开发框架，撰写一份技术调研报告，包含：'
              '框架简介、核心特性、优劣势分析、适用场景、学习路线图。',
          keyPoints: [
            '报告结构：摘要→背景→技术分析→对比→结论',
            '数据来源：GitHub Stars、Stack Overflow 趋势、企业采用率',
            '建议字数：1500-2000 字',
          ],
          practiceQuestions: [
            '请完成一份关于 Flutter 的技术调研报告大纲。',
          ],
        ),
        _DeepSection(
          title: '实战挑战：跨框架 Hello World',
          icon: Icons.rocket_launch,
          content: '分别用 Flutter、React Native、原生 Android/iOS、微信小程序 '
              '创建 Hello World 项目，对比构建流程、项目结构和运行效果。',
          keyPoints: [
            'Flutter: flutter create → lib/main.dart',
            'React Native: npx react-native init → App.js',
            'Android: Android Studio → MainActivity.kt',
            '小程序: 微信开发者工具 → app.js + pages/index',
            '对比维度：初始化时间、项目大小、首屏渲染速度',
          ],
          practiceQuestions: [
            '哪个框架的 Hello World 体验最流畅？为什么？',
            '从项目结构对比中你发现了什么规律？',
          ],
        ),
      ],
    ),
    _ChapterDeepContent(
      chapter: '第2章',
      title: 'Android 与 iOS 原生开发基础',
      icon: Icons.phone_android,
      color: Colors.green,
      sections: [
        _DeepSection(
          title: '知识拓展：Android 架构演进',
          icon: Icons.architecture,
          content: 'Android 从 MVC → MVP → MVVM → MVI 的架构演进，'
              '以及 Jetpack 组件库如何简化现代 Android 开发。',
          keyPoints: [
            'MVC：Activity 承担过多职责，难以测试',
            'MVP：Presenter 解耦视图逻辑，接口过多',
            'MVVM：ViewModel + LiveData + DataBinding',
            'MVI：单向数据流，State 驱动 UI',
            'Jetpack Compose：声明式 UI，对标 Flutter',
            'Room + Hilt + Navigation：现代三件套',
          ],
          practiceQuestions: [
            'MVVM 中 ViewModel 的生命周期是如何管理的？',
            'Jetpack Compose 与 Flutter 的声明式 UI 有哪些异同？',
            '为什么 Google 推荐 MVI 而不是 MVVM？',
          ],
        ),
        _DeepSection(
          title: '核心概念：Activity 生命周期深度解析',
          icon: Icons.loop,
          content: 'Activity 7 个生命周期方法的调用时机、典型场景和常见陷阱。'
              '理解配置变更（旋转屏幕）、进程回收与状态恢复。',
          keyPoints: [
            'onCreate → onStart → onResume → 可交互',
            'onPause → onStop → 后台/不可见',
            'onDestroy → 销毁（配置变更也会触发）',
            'onSaveInstanceState → 保存瞬态数据',
            'ViewModel 在配置变更中存活',
            '常见坑：onStop 后 Fragment 事务崩溃',
          ],
          practiceQuestions: [
            '按 Home 键和按 Back 键的生命周期区别？',
            '横竖屏切换时如何保留数据？至少给出三种方案。',
          ],
        ),
        _DeepSection(
          title: '动手练习：构建 ToDo 应用',
          icon: Icons.checklist,
          content: '使用 Android Studio 从零构建一个 ToDo List 应用，'
              '涵盖 RecyclerView、Room 数据库、ViewModel、Material Design 组件。',
          keyPoints: [
            '步骤1：创建项目，配置 Gradle 依赖',
            '步骤2：设计 Entity + Dao + Database (Room)',
            '步骤3：实现 ViewModel + Repository',
            '步骤4：RecyclerView + ItemTouchHelper (滑动删除)',
            '步骤5：Material 3 主题 + FAB 添加任务',
            '步骤6：搜索、分类、提醒通知 (进阶)',
          ],
          practiceQuestions: [
            '在 Room 中如何实现模糊搜索？',
            '如何用 DiffUtil 优化 RecyclerView 性能？',
          ],
        ),
        _DeepSection(
          title: '实战挑战：仿微信聊天界面',
          icon: Icons.chat,
          content: '挑战实现微信聊天界面：消息气泡、头像、时间分组、'
              '下拉加载历史、软键盘适配、发送按钮动画。',
          keyPoints: [
            'RecyclerView 多 ViewType（左/右气泡）',
            '软键盘弹出时 ScrollToBottom',
            'Glide 加载网络头像',
            '消息时间分组：相差 5 分钟显示时间戳',
            'InputMethodManager 管理键盘',
            '气泡背景：9-patch drawable',
          ],
          practiceQuestions: [
            '如何实现"对方正在输入..."的实时提示？',
            '消息列表在大量数据时如何保证流畅性？',
          ],
        ),
      ],
    ),
    _ChapterDeepContent(
      chapter: '第3章',
      title: 'Flutter 与跨平台开发',
      icon: Icons.flutter_dash,
      color: Colors.cyan,
      sections: [
        _DeepSection(
          title: '知识拓展：Flutter 渲染引擎原理',
          icon: Icons.engineering,
          content: 'Flutter 三棵树(Widget/Element/RenderObject)架构、'
              'Skia 渲染引擎、帧调度流水线、Platform Channel 通信机制。',
          keyPoints: [
            'Widget：不可变配置，轻量级描述',
            'Element：Widget 的实例化，管理生命周期',
            'RenderObject：实际布局和绘制',
            'Skia → Impeller：渲染引擎演进',
            '60fps 帧预算：16.6ms 内完成构建+布局+绘制',
            'Platform Channel：MethodChannel / EventChannel',
          ],
          practiceQuestions: [
            'StatelessWidget 和 StatefulWidget 在三棵树中的区别？',
            '为什么 Flutter 可以实现真正的跨平台一致性？',
            'const Widget 对性能优化有什么影响？',
          ],
        ),
        _DeepSection(
          title: '核心概念：状态管理方案对比',
          icon: Icons.account_tree,
          content: '从 setState → InheritedWidget → Provider → Riverpod → BLoC → GetX，'
              '深入理解每种方案的适用规模和工程实践。',
          keyPoints: [
            'setState：简单场景，单 Widget 内部状态',
            'Provider：官方推荐，ChangeNotifier + Consumer',
            'Riverpod：Provider 进化，编译时安全',
            'BLoC：事件驱动，大型项目首选',
            'GetX：简洁但缺乏官方背书',
            '选型建议：小项目 Provider，大项目 BLoC/Riverpod',
          ],
          practiceQuestions: [
            '用 Provider 和 BLoC 分别实现计数器，对比代码量。',
            '什么时候应该把状态提升到全局？',
          ],
        ),
        _DeepSection(
          title: '动手练习：天气查询 App',
          icon: Icons.cloud,
          content: '使用 Flutter + Dio + Provider 构建天气查询应用：'
              '城市搜索、实时天气、7天预报、气温折线图。',
          keyPoints: [
            'HTTP 请求：Dio 封装 + 拦截器',
            '数据模型：JsonSerializable 自动生成',
            '状态管理：Provider + ChangeNotifier',
            'UI：渐变背景 + Lottie 天气动画',
            '图表：fl_chart 绘制温度曲线',
            '缓存：SharedPreferences 离线数据',
          ],
          practiceQuestions: [
            '如何处理 API 请求失败和无网络的场景？',
            '如何实现城市搜索的防抖(debounce)？',
          ],
        ),
        _DeepSection(
          title: '实战挑战：完整电商首页',
          icon: Icons.shopping_cart,
          content: '挑战实现一个电商首页：轮播图、分类导航、商品瀑布流、'
              '购物车 Badge、搜索栏、下拉刷新与上拉加载。',
          keyPoints: [
            'PageView.builder 实现轮播图',
            'GridView + StaggeredGrid 瀑布流',
            'SliverAppBar + CustomScrollView 折叠效果',
            'Hero 动画：商品图片无缝过渡',
            'RefreshIndicator + 分页加载',
            '购物车：ValueNotifier + Badge 实时计数',
          ],
          practiceQuestions: [
            '瀑布流如何实现图片自适应高度？',
            '大量商品图片如何优化内存使用？',
          ],
        ),
      ],
    ),
    _ChapterDeepContent(
      chapter: '第4章',
      title: '微信小程序开发',
      icon: Icons.wechat,
      color: Colors.green,
      sections: [
        _DeepSection(
          title: '知识拓展：小程序双线程架构',
          icon: Icons.merge_type,
          content: '小程序逻辑层(JsCore)与渲染层(WebView)分离的架构设计，'
              'setData 通信开销、性能优化策略与分包加载。',
          keyPoints: [
            '逻辑层：JsCore 运行 JS，无 DOM 操作',
            '渲染层：WebView 渲染 WXML/WXSS',
            'setData：跨线程序列化，是性能瓶颈',
            '优化：减少 setData 数据量和频率',
            '分包加载：主包 < 2MB，总包 < 20MB',
            'WXS：运行在渲染层的脚本，减少通信',
          ],
          practiceQuestions: [
            '为什么小程序不能使用 DOM API？这带来了什么好处？',
            '如何将 setData 的数据量优化到最小？',
          ],
        ),
        _DeepSection(
          title: '核心概念：小程序组件化开发',
          icon: Icons.widgets,
          content: '自定义组件的创建、通信(properties/triggerEvent)、'
              'Behavior 复用、插槽(slot)与组件生命周期。',
          keyPoints: [
            'Component 构造器 vs Page 构造器',
            'properties：父→子数据传递（类型+默认值）',
            'triggerEvent：子→父事件通知',
            'Behavior：类似 Mixin 的代码复用',
            '组件生命周期：created → attached → detached',
            '抽象节点：动态组件注入',
          ],
          practiceQuestions: [
            '设计一个通用的弹窗组件，支持标题、内容和按钮自定义。',
            'Behavior 和 JS 的 Mixin 有什么区别？',
          ],
        ),
        _DeepSection(
          title: '动手练习：校园服务小程序',
          icon: Icons.school,
          content: '开发一个校园服务小程序：课程表查看、成绩查询、'
              '图书馆座位预约、校园公告推送。',
          keyPoints: [
            '云开发：云函数 + 云数据库 + 云存储',
            '用户认证：wx.login + 后端 session',
            '课程表：自定义 Canvas 绘制',
            '实时消息：WebSocket + 订阅消息',
            '地图：map 组件 + 校园导航',
          ],
          practiceQuestions: [
            '小程序云开发和传统服务器部署各有什么优劣？',
            '如何实现课程表的拖拽调整功能？',
          ],
        ),
        _DeepSection(
          title: '实战挑战：电商下单流程',
          icon: Icons.payment,
          content: '完整实现：商品详情 → 规格选择 → 购物车 → 订单确认 → '
              '微信支付（模拟）→ 订单状态流转。',
          keyPoints: [
            'SKU 选择器：多规格矩阵联动',
            '购物车：本地存储 + 云同步',
            '地址管理：wx.chooseAddress',
            '支付流程：统一下单 → 调起支付 → 回调验证',
            '订单状态机：待付款→待发货→待收货→已完成',
          ],
          practiceQuestions: [
            '如何防止重复下单？前端和后端分别怎么处理？',
            'SKU 规格联动的核心算法是什么？',
          ],
        ),
      ],
    ),
    _ChapterDeepContent(
      chapter: '第5章',
      title: 'HarmonyOS 鸿蒙开发',
      icon: Icons.devices,
      color: Colors.red,
      sections: [
        _DeepSection(
          title: '知识拓展：分布式能力解析',
          icon: Icons.hub,
          content: '鸿蒙分布式软总线、分布式数据管理、分布式任务调度的'
              '技术原理与应用场景。',
          keyPoints: [
            '分布式软总线：设备自动发现、连接、传输',
            '分布式数据管理：跨设备数据同步',
            '分布式任务调度：Ability 跨设备流转',
            '超级终端：多设备协同为一个逻辑设备',
            '元服务(Atomic Service)：免安装即用',
            '一次开发多端部署(OHDE)',
          ],
          practiceQuestions: [
            '分布式软总线如何实现设备间低延迟通信？',
            '与 iOS Handoff 和 Android Nearby Share 对比差异。',
          ],
        ),
        _DeepSection(
          title: '核心概念：ArkUI 声明式开发',
          icon: Icons.code,
          content: 'ArkTS 语言基础、ArkUI 声明式语法、'
              '自定义组件、状态管理(@State/@Prop/@Link/@Provide/@Consume)。',
          keyPoints: [
            'ArkTS = TypeScript + 声明式 UI 扩展',
            '@State：组件内部状态',
            '@Prop：父→子单向同步',
            '@Link：父↔子双向同步',
            '@Provide/@Consume：跨组件层级',
            'ForEach + LazyForEach：列表渲染',
          ],
          practiceQuestions: [
            '@Prop 和 @Link 的使用场景分别是什么？',
            'ArkUI 与 Flutter 的声明式 UI 理念有何异同？',
          ],
        ),
        _DeepSection(
          title: '动手练习：鸿蒙计算器',
          icon: Icons.calculate,
          content: '使用 ArkUI 开发一个科学计算器，支持基础四则运算、'
              '括号优先级、历史记录和主题切换。',
          keyPoints: [
            'Grid 布局：4×6 按钮矩阵',
            '表达式解析：逆波兰算法',
            '历史记录：@StorageLink 持久化',
            '动画：数字滚动效果',
            '适配：手机 + 平板双布局',
          ],
          practiceQuestions: [
            '如何处理连续运算（如 1+2*3）的优先级问题？',
            '鸿蒙如何实现手机与平板的自适应布局？',
          ],
        ),
        _DeepSection(
          title: '实战挑战：跨设备协同白板',
          icon: Icons.draw,
          content: '挑战开发分布式白板应用：手机绘图 → 平板同步显示 → '
              'PC 端保存导出，体验鸿蒙分布式核心能力。',
          keyPoints: [
            '分布式数据对象：实时同步绘图数据',
            'Canvas 组件：触摸绘图',
            '笔触数据序列化：压缩传输',
            '权限管理：分布式设备授权',
            '离线缓存 + 在线合并',
          ],
          practiceQuestions: [
            '多设备同时绘图时如何解决冲突？',
            '如何优化绘图数据的传输效率？',
          ],
        ),
      ],
    ),
    _ChapterDeepContent(
      chapter: '第6章',
      title: '综合开发实践',
      icon: Icons.integration_instructions,
      color: Colors.deepPurple,
      sections: [
        _DeepSection(
          title: '知识拓展：DevOps 与持续集成',
          icon: Icons.build_circle,
          content: '移动应用 CI/CD 流水线设计：代码提交 → 自动构建 → '
              '自动化测试 → 灰度发布 → 监控预警。',
          keyPoints: [
            'Git Flow：feature/develop/release/hotfix',
            'CI 工具：GitHub Actions / GitLab CI / Jenkins',
            '自动构建：Fastlane (iOS) / Gradle (Android)',
            '测试金字塔：单元测试 > 集成测试 > E2E 测试',
            '灰度发布：按比例 / 按渠道 / AB Test',
            '监控：Sentry (崩溃) + Firebase Analytics',
          ],
          practiceQuestions: [
            '为 Flutter 项目设计一个 GitHub Actions 工作流。',
            '灰度发布中如何处理数据库 schema 变更？',
          ],
        ),
        _DeepSection(
          title: '核心概念：性能优化方法论',
          icon: Icons.speed,
          content: '移动应用性能优化的系统方法：启动速度、渲染流畅度、'
              '内存管理、网络优化、包体积控制。',
          keyPoints: [
            '启动优化：懒加载 + 预加载 + 并行初始化',
            '渲染优化：避免过度绘制、减少 Widget 重建',
            '内存优化：图片缓存策略、大列表回收',
            '网络优化：HTTP 缓存、请求合并、数据压缩',
            '包体积：Tree Shaking、资源压缩、按需加载',
            '工具：DevTools、Profile Mode、Benchmark',
          ],
          practiceQuestions: [
            '如何使用 Flutter DevTools 定位性能瓶颈？',
            '列举 5 种减少 Widget 重建的方法。',
          ],
        ),
        _DeepSection(
          title: '动手练习：完整项目架构搭建',
          icon: Icons.foundation,
          content: '从零搭建一个生产级 Flutter 项目：目录结构、依赖注入、'
              '网络层封装、错误处理、国际化、主题系统。',
          keyPoints: [
            '分层架构：presentation → domain → data',
            '依赖注入：get_it + injectable',
            '路由：go_router 声明式路由',
            '网络层：Dio + Retrofit + 统一错误处理',
            '国际化：flutter_localizations + ARB 文件',
            '环境切换：dev / staging / prod',
          ],
          practiceQuestions: [
            '为什么推荐三层架构而不是 MVC？',
            '如何设计统一的错误处理和用户提示机制？',
          ],
        ),
        _DeepSection(
          title: '实战挑战：毕设/课设级项目',
          icon: Icons.emoji_events,
          content: '自选一个具有实际价值的项目主题，完成从需求分析到上架/部署的全流程。'
              '推荐主题：校园社区、健康管理、学习工具、电商平台。',
          keyPoints: [
            '需求文档：用户故事 + 功能清单 + 原型图',
            '技术方案：架构图 + 数据库设计 + API 设计',
            '迭代开发：2周一个 Sprint',
            '代码质量：lint + 代码审查 + 单元测试覆盖率 > 60%',
            '演示汇报：3 分钟 Demo + 5 分钟技术分享',
            '项目管理：使用看板 (Kanban) 追踪进度',
          ],
          practiceQuestions: [
            '如何在有限时间内完成一个高质量的课设项目？',
            '项目答辩时评委最关注哪些方面？',
          ],
        ),
      ],
    ),
  ];

  // 用户学习进度（章节→节索引→是否完成）
  Map<String, Set<int>> _completedSections = {};
  int _expandedChapter = -1;
  int _selectedSection = -1;
  String? _selectedChapter;
  bool _isAiLoading = false;
  String _aiAnswer = '';
  String? _aiProvider;
  String? _aiModel;
  final _aiQuestionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _chapters.length, vsync: this);
    _loadProgress();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _aiQuestionController.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    // 从学习记录推断已完成的深度学习节
    final userId = _authService.currentUser?.userId;
    if (userId == null) return;

    try {
      final records = await _learningRecordDao.getRecords(userId);
      final completed = <String, Set<int>>{};
      for (final r in records) {
        final nodeTitle = r['node_title']?.toString() ?? '';
        // 匹配 "深度-第X章-N" 格式的记录
        final match = RegExp(r'深度-(.+)-(\d+)').firstMatch(nodeTitle);
        if (match != null) {
          final chapter = match.group(1)!;
          final idx = int.tryParse(match.group(2)!) ?? 0;
          completed.putIfAbsent(chapter, () => {}).add(idx);
        }
      }
      if (mounted) setState(() => _completedSections = completed);
    } catch (_) {}
  }

  Future<void> _markCompleted(String chapter, int sectionIdx) async {
    final userId = _authService.currentUser?.userId;
    if (userId == null) return;

    try {
      await _learningRecordDao.addRecord(
        userId: userId,
        nodeId: 'deep-$chapter-$sectionIdx',
        nodeTitle: '深度-$chapter-$sectionIdx',
        studyTime: '30',
      );
      setState(() {
        _completedSections.putIfAbsent(chapter, () => {}).add(sectionIdx);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已标记完成 ✓'), duration: Duration(seconds: 1)),
        );
      }
    } catch (_) {}
  }

  Future<void> _askAi(String question) async {
    setState(() { _isAiLoading = true; _aiAnswer = ''; _aiProvider = null; _aiModel = null; });
    try {
      final ai = AiService();
      final result = await ai.chatWithMeta(
        [{'role': 'user', 'content': question}],
        systemPrompt: '你是移动应用开发课程的AI助教。请用简洁、专业的语言回答问题。',
      );
      if (mounted) {
        setState(() {
          _aiAnswer = result.content;
          _aiProvider = result.provider;
          _aiModel = result.model;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _aiAnswer = '抱歉，AI 回答失败：$e');
    } finally {
      if (mounted) setState(() => _isAiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('深度实践中心'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelColor: Colors.white60,
          tabs: _chapters.map((c) => Tab(
            icon: Icon(c.icon, size: 18),
            text: c.chapter,
          )).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _chapters.map((ch) => _buildChapterContent(ch, isDark)).toList(),
      ),
    );
  }

  Widget _buildChapterContent(_ChapterDeepContent chapter, bool isDark) {
    final completed = _completedSections[chapter.chapter] ?? {};
    final total = chapter.sections.length;
    final done = completed.length;
    final progress = total > 0 ? done / total : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 章节头部 + 进度
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [chapter.color, chapter.color.withValues(alpha: 0.7)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(chapter.icon, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(chapter.title,
                        style: const TextStyle(color: Colors.white, fontSize: 17,
                          fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$done/$total', style: const TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 学习方法提示
          Card(
            color: isDark ? Colors.blueGrey[800] : Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.lightbulb, color: Colors.amber[700], size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '学习建议：按顺序完成 知识拓展 → 核心概念 → 动手练习 → 实战挑战',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.blue[900]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 各节内容
          ...List.generate(chapter.sections.length, (idx) {
            final section = chapter.sections[idx];
            final isCompleted = completed.contains(idx);
            final isExpanded = _selectedChapter == chapter.chapter && _selectedSection == idx;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isCompleted
                    ? BorderSide(color: Colors.green.withValues(alpha: 0.5), width: 1.5)
                    : BorderSide.none,
              ),
              child: Column(
                children: [
                  // 节标题
                  ListTile(
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.withValues(alpha: 0.15)
                            : chapter.color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : section.icon,
                        color: isCompleted ? Colors.green : chapter.color,
                        size: 20,
                      ),
                    ),
                    title: Text(section.title,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                        decoration: isCompleted ? TextDecoration.lineThrough : null)),
                    trailing: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: chapter.color,
                    ),
                    onTap: () => setState(() {
                      if (isExpanded) {
                        _selectedSection = -1;
                        _selectedChapter = null;
                      } else {
                        _selectedSection = idx;
                        _selectedChapter = chapter.chapter;
                      }
                      _aiAnswer = '';
                    }),
                  ),

                  // 展开详情
                  if (isExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          // 内容描述
                          Text(section.content,
                            style: TextStyle(fontSize: 13, height: 1.6,
                              color: isDark ? Colors.white70 : Colors.black87)),
                          const SizedBox(height: 12),

                          // 要点列表
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[850] : Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: chapter.color.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.bookmark, color: chapter.color, size: 16),
                                    const SizedBox(width: 4),
                                    Text('核心要点', style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13, color: chapter.color)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...section.keyPoints.map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('• ', style: TextStyle(color: chapter.color, fontSize: 13)),
                                      Expanded(child: Text(p, style: const TextStyle(fontSize: 12, height: 1.5))),
                                    ],
                                  ),
                                )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 思考题
                          Text('💡 思考与练习', style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13, color: chapter.color)),
                          const SizedBox(height: 6),
                          ...section.practiceQuestions.asMap().entries.map((e) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.indigo.withValues(alpha: 0.15) : Colors.indigo.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 20, height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: chapter.color.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text('${e.key + 1}',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                      color: chapter.color)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(e.value, style: const TextStyle(fontSize: 12, height: 1.4)),
                                ),
                                // AI 解答按钮
                                InkWell(
                                  onTap: () => _askAi(e.value),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.deepPurple.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.smart_toy, size: 12, color: Colors.deepPurple[400]),
                                        const SizedBox(width: 2),
                                        Text('AI', style: TextStyle(fontSize: 10, color: Colors.deepPurple[400])),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),

                          // AI 回答区域
                          if (_aiAnswer.isNotEmpty || _isAiLoading)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.deepPurple.withValues(alpha: 0.15) : Colors.deepPurple.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.smart_toy, size: 16, color: Colors.deepPurple[400]),
                                      const SizedBox(width: 4),
                                      Text('AI 解答', style: TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 12,
                                        color: Colors.deepPurple[400])),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_isAiLoading)
                                    const Center(child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ))
                                  else
                                    MarkdownBubble(
                                      content: _aiAnswer,
                                      provider: _aiProvider,
                                      model: _aiModel,
                                      compact: true,
                                      accentColor: Colors.deepPurple,
                                    ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 12),

                          // 自由提问
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _aiQuestionController,
                                  decoration: InputDecoration(
                                    hintText: '输入问题，向AI请教...',
                                    hintStyle: const TextStyle(fontSize: 12),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: _isAiLoading ? null : () {
                                  final q = _aiQuestionController.text.trim();
                                  if (q.isNotEmpty) {
                                    _askAi(q);
                                    _aiQuestionController.clear();
                                  }
                                },
                                child: const Text('提问', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // 操作按钮
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (!isCompleted)
                                FilledButton.icon(
                                  onPressed: () => _markCompleted(chapter.chapter, idx),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('标记完成', style: TextStyle(fontSize: 12)),
                                ),
                              if (isCompleted)
                                Chip(
                                  avatar: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  label: const Text('已完成', style: TextStyle(fontSize: 12)),
                                  backgroundColor: Colors.green.withValues(alpha: 0.1),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── 数据模型 ──────────────────────────────────────────────────────────

class _ChapterDeepContent {
  final String chapter;
  final String title;
  final IconData icon;
  final Color color;
  final List<_DeepSection> sections;
  const _ChapterDeepContent({
    required this.chapter, required this.title, required this.icon,
    required this.color, required this.sections,
  });
}

class _DeepSection {
  final String title;
  final IconData icon;
  final String content;
  final List<String> keyPoints;
  final List<String> practiceQuestions;
  const _DeepSection({
    required this.title, required this.icon, required this.content,
    required this.keyPoints, required this.practiceQuestions,
  });
}
