import 'package:flutter/foundation.dart';

import '../data/local/knowledge_graph_dao.dart';
import '../data/local/course_dao.dart';
import '../data/models/course_model.dart';

/// Provides seed data (~120 concepts, ~200 relations) covering all 6 chapters
/// of the "移动应用开发" course.  Call [seedIfEmpty] at app startup so the
/// knowledge graph is populated for first-time users.
///
/// Usage:
/// ```dart
/// final service = KnowledgeSeedService();
/// await service.seedIfEmpty();
/// ```
class KnowledgeSeedService {
  final KnowledgeGraphDao _dao = KnowledgeGraphDao();
  final CourseDao _courseDao = CourseDao();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Seeds concepts and relations only when the `knowledge_concepts` table is
  /// empty, making it safe to call on every app launch.
  Future<void> seedIfEmpty() async {
    final count = await _dao.conceptCount();
    if (count > 0) {
      debugPrint('[KnowledgeSeedService] 已有 $count 个概念，跳过种子数据');
      return;
    }

    debugPrint('[KnowledgeSeedService] 概念表为空，开始写入种子数据...');

    final course = await _courseDao.getActiveCourse();
    if (_shouldSeedGenericCourse(course)) {
      await _seedGenericCourse(course!);
      final conceptCount = await _dao.conceptCount();
      final relCount = await _dao.relationCount();
      debugPrint(
        '[KnowledgeSeedService] 已为《${course.name}》生成通用课程图谱：'
        '$conceptCount 个概念，$relCount 条关系',
      );
      return;
    }

    await _seedConcepts();
    final conceptCount = await _dao.conceptCount();
    debugPrint('[KnowledgeSeedService] 概念写入完成，共 $conceptCount 条');

    await _seedRelations();
    final relCount = await _dao.relationCount();
    debugPrint('[KnowledgeSeedService] 关系写入完成，共 $relCount 条');

    debugPrint('[KnowledgeSeedService] 种子数据初始化完毕 ✓');
  }

  bool _shouldSeedGenericCourse(CourseModel? course) {
    if (course == null) return false;
    final name = course.name.trim();
    if (name.isEmpty) return false;
    if (name.contains('移动应用开发')) return false;
    return course.chapters.isNotEmpty;
  }

  Future<void> _seedGenericCourse(CourseModel course) async {
    final chapterTitles = course.chapters.isNotEmpty
        ? course.chapters
        : List.generate(
            course.chapterCount,
            (i) => '第${i + 1}章 ${course.name}核心内容${i + 1}',
          );

    final ids = <String, int>{};
    Future<int> add(
      String key,
      String name,
      String type,
      int chapter,
      String description,
      String importance,
      String keywords,
    ) async {
      final id = await _dao.addConcept(_c(
        name,
        type,
        chapter,
        description,
        importance,
        keywords,
      ));
      ids[key] = id;
      return id;
    }

    await add(
      'course',
      course.name,
      'concept',
      1,
      course.description.isNotEmpty
          ? course.description
          : '《${course.name}》课程总体知识结构',
      'core',
      '${course.name},课程,知识体系',
    );

    for (var i = 0; i < chapterTitles.length; i++) {
      final chapterNo = i + 1;
      final chapter = _normalizeChapterTitle(chapterTitles[i], chapterNo);
      final chapterKey = 'chapter_$chapterNo';
      final coreKey = 'core_$chapterNo';
      final methodKey = 'method_$chapterNo';
      final practiceKey = 'practice_$chapterNo';

      await add(
        chapterKey,
        chapter,
        'concept',
        chapterNo,
        '《${course.name}》第$chapterNo章：$chapter',
        'core',
        '$chapter,${course.name},第$chapterNo章',
      );
      await add(
        coreKey,
        '$chapter 核心概念',
        'concept',
        chapterNo,
        '支撑"$chapter"学习的关键概念集合',
        'important',
        '$chapter,核心概念,关键知识',
      );
      await add(
        methodKey,
        '$chapter 方法与过程',
        'pattern',
        chapterNo,
        '完成"$chapter"学习任务所需的方法、流程或规范',
        'important',
        '$chapter,方法,流程,规范',
      );
      await add(
        practiceKey,
        '$chapter 实践应用',
        'technology',
        chapterNo,
        '围绕"$chapter"开展案例、实验、作业或项目实践',
        'important',
        '$chapter,实践,案例,应用',
      );
    }

    Future<void> rel(
      String sourceKey,
      String targetKey,
      String type,
      String label, [
      double weight = 1.0,
    ]) async {
      final sourceId = ids[sourceKey];
      final targetId = ids[targetKey];
      if (sourceId == null || targetId == null) return;
      await _dao.addRelation({
        'source_concept_id': sourceId,
        'target_concept_id': targetId,
        'relation_type': type,
        'relation_label': label,
        'description': '$sourceKey → $targetKey ($label)',
        'bidirectional': 0,
        'weight': weight,
        'ai_generated': 0,
        'confidence': 0.8,
      });
    }

    for (var i = 0; i < chapterTitles.length; i++) {
      final chapterNo = i + 1;
      await rel('course', 'chapter_$chapterNo', 'contains', '课程章节');
      await rel('chapter_$chapterNo', 'core_$chapterNo', 'contains', '核心概念');
      await rel('core_$chapterNo', 'method_$chapterNo', 'supports', '方法支撑');
      await rel(
          'method_$chapterNo', 'practice_$chapterNo', 'applied_in', '实践应用');
      if (chapterNo > 1) {
        await rel(
          'chapter_${chapterNo - 1}',
          'chapter_$chapterNo',
          'prerequisite',
          '前置章节',
          0.7,
        );
      }
    }
  }

  String _normalizeChapterTitle(String raw, int chapterNo) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '第$chapterNo章';
    final withoutPrefix = trimmed.replaceFirst(
      RegExp(r'^第?\s*[一二三四五六七八九十\d]+\s*[章节讲]\s*[:：、.\-]?\s*'),
      '',
    );
    return withoutPrefix.isEmpty ? trimmed : withoutPrefix;
  }

  // ── Concept seed data ─────────────────────────────────────────────────────

  /// Helper to build a concept map with the expected DB column names.
  Map<String, dynamic> _c(
    String name,
    String type,
    int chapter,
    String description,
    String importance,
    String keywords,
  ) {
    return {
      'concept_name': name,
      'concept_type': type,
      'chapter': chapter,
      'description': description,
      'importance': importance,
      'keywords': keywords,
    };
  }

  Future<void> _seedConcepts() async {
    final concepts = <Map<String, dynamic>>[
      // ══════════════════════════════════════════════════════════════════════
      // Chapter 1 — 移动应用开发技术体系全景 (19 concepts)
      // ══════════════════════════════════════════════════════════════════════
      _c('移动应用开发', 'concept', 1, '面向移动设备（手机、平板等）的应用程序设计与开发总称', 'core',
          '移动开发,App,应用程序,移动端'),
      _c('原生应用', 'concept', 1, '使用平台原生语言和SDK开发的应用，性能最优但需分平台开发', 'core',
          '原生开发,Native,平台SDK'),
      _c('WebApp', 'technology', 1, '基于Web技术（HTML/CSS/JS）构建的移动端应用', 'important',
          'Web应用,HTML5,浏览器,SPA'),
      _c('混合应用', 'concept', 1, '结合Web技术和原生容器的混合开发方式', 'core',
          'Hybrid,混合开发,WebView,原生容器'),
      _c('跨平台应用', 'concept', 1, '一套代码同时运行在多个平台的应用开发方式', 'core',
          '跨平台,多平台,代码复用,一次开发'),
      _c('小程序', 'technology', 1, '运行在宿主应用内的轻量级应用形态，无需安装', 'important',
          '微信小程序,支付宝小程序,轻应用'),
      _c('多端应用', 'concept', 1, '同时适配手机、平板、PC、IoT等多种终端的应用', 'important',
          '多端适配,全场景,多设备'),
      _c('PWA', 'technology', 1, 'Progressive Web App，渐进式Web应用，支持离线和推送',
          'supplementary', '渐进式,Service Worker,离线缓存,Web Manifest'),
      _c('响应式设计', 'concept', 1, '界面根据屏幕尺寸自动适配布局的设计理念', 'important',
          '自适应,媒体查询,弹性布局,断点'),
      _c('移动端UI设计', 'concept', 1, '面向移动设备的用户界面设计原则与规范', 'important',
          'UI设计,交互设计,界面规范,设计系统'),
      _c('性能优化', 'concept', 1, '提升应用响应速度、减少资源消耗的技术手段', 'important',
          '性能,优化,渲染性能,内存管理'),
      _c('用户体验', 'concept', 1, '用户使用产品过程中的主观感受与满意度', 'important',
          'UX,体验设计,可用性,易用性'),
      _c('状态管理', 'concept', 1, '管理应用运行时数据状态的架构方案', 'core', '状态,数据流,响应式,状态容器'),
      _c('组件化开发', 'pattern', 1, '将UI拆分为可复用组件进行模块化开发的模式', 'important',
          '组件,模块化,复用,封装'),
      _c('生命周期', 'concept', 1, '应用或组件从创建到销毁的状态变化过程', 'core', '生命周期,创建,销毁,状态转换'),
      _c('声明式UI', 'pattern', 1, '通过描述"界面应该是什么样"来构建UI的编程范式', 'important',
          '声明式,描述式,Flutter,SwiftUI'),
      _c('命令式UI', 'pattern', 1, '通过步骤指令逐步操作UI元素的传统编程范式', 'supplementary',
          '命令式,过程式,DOM操作,UIKit'),
      _c('应用分发', 'concept', 1, '将应用发布到应用商店或其他渠道供用户下载安装', 'supplementary',
          '发布,应用商店,分发渠道,上架'),
      _c('HarmonyOS平台', 'platform', 1, '华为自研的分布式操作系统平台', 'important',
          '鸿蒙,华为,分布式,HarmonyOS'),

      // ══════════════════════════════════════════════════════════════════════
      // Chapter 2 — Android与iOS原生开发基础 (25 concepts)
      // ══════════════════════════════════════════════════════════════════════
      _c(
          'Android四大组件',
          'concept',
          2,
          'Activity/Service/BroadcastReceiver/ContentProvider构成Android核心',
          'core',
          'Activity,Service,BroadcastReceiver,ContentProvider'),
      _c('Activity', 'concept', 2, 'Android应用中一个屏幕界面的基本单元', 'core',
          'Activity,界面,屏幕,交互'),
      _c('Activity生命周期', 'concept', 2, 'Activity从创建到销毁经历的状态回调序列', 'core',
          'onCreate,onResume,onPause,onDestroy'),
      _c('Intent', 'concept', 2, 'Android组件间通信的消息对象，用于启动组件和传递数据', 'important',
          'Intent,消息传递,隐式Intent,显式Intent'),
      _c(
          'Android布局系统',
          'technology',
          2,
          'Android XML布局体系，包括LinearLayout、ConstraintLayout等',
          'important',
          'XML布局,ConstraintLayout,LinearLayout,布局'),
      _c('RecyclerView', 'technology', 2, 'Android高性能列表控件，支持复杂列表和网格展示',
          'important', 'RecyclerView,列表,Adapter,ViewHolder'),
      _c('Jetpack', 'framework', 2, 'Google推出的Android开发组件库套件', 'core',
          'Jetpack,AndroidX,架构组件,官方库'),
      _c('Jetpack Compose', 'framework', 2, 'Android现代声明式UI框架，替代传统XML布局',
          'core', 'Compose,声明式UI,Kotlin,现代Android'),
      _c('Kotlin语言', 'language', 2, 'Google推荐的Android官方开发语言', 'core',
          'Kotlin,JVM,协程,空安全'),
      _c('Android Studio', 'tool', 2, 'Google官方Android集成开发环境', 'core',
          'IDE,开发工具,调试,模拟器'),
      _c('Gradle', 'tool', 2, 'Android项目的自动化构建工具', 'important',
          '构建工具,依赖管理,编译,打包'),
      _c('Android权限管理', 'concept', 2, 'Android运行时权限申请与安全管理机制', 'important',
          '权限,运行时权限,安全,隐私'),
      _c('Android数据存储', 'concept', 2, 'Android本地数据持久化方案，含SP/SQLite/Room',
          'important', 'SharedPreferences,SQLite,Room,文件存储'),
      _c('iOS开发', 'concept', 2, '面向Apple iOS平台的原生应用开发', 'core',
          'iOS,Apple,iPhone,iPad'),
      _c('Swift语言', 'language', 2, 'Apple推出的现代编程语言，用于iOS/macOS开发', 'core',
          'Swift,Apple,类型安全,协议'),
      _c('Objective-C', 'language', 2, 'Apple早期主力开发语言，面向对象的C语言超集',
          'supplementary', 'ObjC,消息传递,运行时,遗留代码'),
      _c('UIKit', 'framework', 2, 'iOS传统命令式UI框架', 'important',
          'UIKit,UIViewController,Storyboard,命令式'),
      _c('SwiftUI', 'framework', 2, 'Apple现代声明式UI框架，跨Apple平台统一开发', 'core',
          'SwiftUI,声明式,Preview,跨Apple平台'),
      _c('ViewController', 'concept', 2, 'iOS中管理视图层级和用户交互的控制器', 'important',
          'UIViewController,视图控制器,MVC,导航'),
      _c('iOS应用生命周期', 'concept', 2, 'iOS应用从启动到终止经历的状态转换', 'important',
          'AppDelegate,SceneDelegate,前后台切换,状态'),
      _c('iOS导航模式', 'concept', 2, 'iOS中常见的页面导航方式（Push/Modal/Tab）', 'important',
          'NavigationController,TabBar,模态,导航栈'),
      _c('Xcode', 'tool', 2, 'Apple官方集成开发环境，支持iOS/macOS开发', 'core',
          'IDE,开发工具,Interface Builder,Instruments'),
      _c('CocoaPods', 'tool', 2, 'iOS/macOS主流依赖管理工具', 'supplementary',
          '依赖管理,Podfile,第三方库,包管理'),
      _c('iOS数据持久化', 'concept', 2, 'iOS本地数据存储方案，含UserDefaults/CoreData/Realm',
          'important', 'UserDefaults,CoreData,Realm,数据存储'),
      _c('Material Design', 'concept', 2, 'Google推出的设计语言和规范体系', 'important',
          'MD,设计规范,组件库,动效'),

      // ══════════════════════════════════════════════════════════════════════
      // Chapter 3 — Flutter等混合开发技术 (25 concepts)
      // ══════════════════════════════════════════════════════════════════════
      _c('Flutter', 'framework', 3, 'Google开源跨平台UI框架，使用Dart语言，自绘引擎', 'core',
          'Flutter,Google,跨平台,自绘引擎'),
      _c('Dart语言', 'language', 3, 'Flutter专用编程语言，支持JIT/AOT编译', 'core',
          'Dart,JIT,AOT,强类型'),
      _c('Widget', 'concept', 3, 'Flutter中一切皆Widget的核心概念，UI的基本构建单元', 'core',
          'Widget,组件,Element,RenderObject'),
      _c('StatefulWidget', 'concept', 3, '拥有可变状态的Widget，通过State对象管理状态', 'core',
          'StatefulWidget,State,setState,有状态'),
      _c('StatelessWidget', 'concept', 3, '不可变的Widget，适用于纯展示型UI', 'important',
          'StatelessWidget,不可变,纯展示,build'),
      _c('Flutter状态管理', 'concept', 3, 'Flutter应用中管理和共享状态的各种方案', 'core',
          'Provider,Riverpod,Bloc,GetX'),
      _c('Provider', 'framework', 3, 'Flutter官方推荐的轻量级状态管理方案', 'important',
          'Provider,InheritedWidget,ChangeNotifier,依赖注入'),
      _c('Flutter布局系统', 'concept', 3, 'Flutter基于约束的布局模型（Row/Column/Stack等）',
          'important', '布局,Flex,约束,盒模型'),
      _c('Flutter路由导航', 'concept', 3, 'Flutter中页面跳转与路由管理机制', 'important',
          'Navigator,Route,路由表,页面跳转'),
      _c('Hot Reload', 'technology', 3, 'Flutter的热重载功能，修改代码后即时刷新UI',
          'important', '热重载,即时刷新,开发效率,JIT'),
      _c('渲染引擎', 'technology', 3, 'Flutter自带的Skia/Impeller渲染引擎，不依赖原生控件',
          'important', 'Skia,Impeller,渲染,GPU'),
      _c('平台通道', 'technology', 3, 'Flutter与原生平台通信的桥接机制', 'important',
          'MethodChannel,Platform Channel,原生通信,桥接'),
      _c('Flutter插件开发', 'concept', 3, '封装原生功能为Flutter可用插件的开发方式',
          'supplementary', '插件,Package,原生封装,pub.dev'),
      _c('Dart异步编程', 'concept', 3, 'Dart的Future/Stream/async-await异步编程模型',
          'core', 'Future,Stream,async,await'),
      _c('React Native', 'framework', 3, 'Facebook开源的跨平台框架，使用JavaScript/React',
          'core', 'RN,React,Facebook,JavaScript'),
      _c('JavaScript', 'language', 3, 'Web前端核心语言，也用于React Native等跨平台开发',
          'important', 'JS,ECMAScript,动态类型,前端'),
      _c('JSX语法', 'concept', 3, 'React/RN中将HTML嵌入JavaScript的语法扩展',
          'supplementary', 'JSX,模板,React,标签语法'),
      _c('Bridge桥接', 'technology', 3, 'React Native中JS与原生模块通信的桥接层', 'important',
          'Bridge,序列化,异步通信,JSI'),
      _c('Uniapp', 'framework', 3, '基于Vue.js的多端统一开发框架', 'important',
          'uni-app,DCloud,Vue,多端'),
      _c('Vue.js', 'framework', 3, '渐进式JavaScript前端框架', 'supplementary',
          'Vue,MVVM,响应式,渐进式'),
      _c('MAUI', 'framework', 3, '微软跨平台UI框架，.NET Multi-platform App UI',
          'supplementary', '.NET,Microsoft,C#,Xamarin'),
      _c('C#语言', 'language', 3, '微软开发的面向对象编程语言，用于MAUI/.NET', 'supplementary',
          'C#,.NET,微软,面向对象'),
      _c('跨平台性能对比', 'concept', 3, '不同跨平台方案在性能、开发效率等方面的对比分析', 'important',
          '性能对比,渲染方式,开发效率,框架对比'),
      _c('WebView', 'technology', 3, '在原生应用中嵌入Web内容的组件', 'supplementary',
          'WebView,内嵌浏览器,H5,混合'),
      _c('混合应用开发', 'concept', 3, '结合Web与原生技术进行应用开发的综合方案', 'important',
          'Hybrid,Cordova,Ionic,混合'),

      // ══════════════════════════════════════════════════════════════════════
      // Chapter 4 — 微信小程序开发 (23 concepts)
      // ══════════════════════════════════════════════════════════════════════
      _c('微信小程序', 'platform', 4, '运行在微信客户端内的轻量级应用，无需安装', 'core',
          '小程序,微信,轻应用,即用即走'),
      _c('MINA框架', 'framework', 4, '微信小程序的底层框架，提供组件和API', 'core',
          'MINA,小程序框架,微信框架,底层'),
      _c('WXML', 'language', 4, '微信小程序的标记语言，类似HTML', 'core',
          'WXML,模板,数据绑定,条件渲染'),
      _c('WXSS', 'language', 4, '微信小程序的样式语言，类似CSS', 'important',
          'WXSS,样式,rpx,选择器'),
      _c('小程序生命周期', 'concept', 4, '小程序App和Page级别的生命周期函数', 'core',
          'onLaunch,onShow,onLoad,onReady'),
      _c('小程序组件', 'concept', 4, '小程序内置UI组件体系（view/text/image等）', 'important',
          '组件,view,text,swiper'),
      _c('小程序API', 'concept', 4, '微信提供的各类接口（网络/存储/设备/开放能力）', 'important',
          'wx.request,wx.setStorage,API,接口'),
      _c('云开发', 'technology', 4, '微信提供的Serverless后端服务（数据库/存储/函数）', 'important',
          '云函数,云数据库,云存储,Serverless'),
      _c('小程序状态管理', 'concept', 4, '小程序中页面间数据共享和状态管理方案', 'important',
          'globalData,状态管理,数据共享,EventBus'),
      _c('WXS脚本', 'language', 4, '小程序的脚本语言，可在WXML中直接执行', 'supplementary',
          'WXS,内联脚本,过滤器,计算'),
      _c('小程序路由', 'concept', 4, '小程序页面跳转与路由管理（navigateTo/redirectTo等）',
          'important', '路由,navigateTo,switchTab,页面栈'),
      _c('小程序自定义组件', 'concept', 4, '自定义可复用的小程序组件及组件间通信', 'important',
          '自定义组件,Component,properties,triggerEvent'),
      _c('Taro', 'framework', 4, '多端统一开发框架，支持转换为小程序/H5/RN', 'supplementary',
          'Taro,京东,React,多端编译'),
      _c('微信开发者工具', 'tool', 4, '微信官方小程序开发、调试和发布工具', 'core', 'IDE,开发工具,调试,真机预览'),
      _c('小程序分包加载', 'technology', 4, '将小程序拆分为多个子包按需加载以优化体积', 'supplementary',
          '分包,subpackage,按需加载,体积优化'),
      _c('微信支付', 'technology', 4, '微信小程序内的支付功能集成', 'supplementary',
          '支付,wx.requestPayment,商户,订单'),
      _c('小程序插件', 'technology', 4, '可被其他小程序引用的功能模块', 'supplementary',
          '插件,复用,第三方,扩展'),
      _c('小程序双线程模型', 'concept', 4, '小程序逻辑层(JsCore)和渲染层(WebView)分离的架构', 'core',
          '双线程,逻辑层,渲染层,JsCore'),
      _c('小程序网络请求', 'concept', 4, '小程序中发起HTTP请求与服务端通信', 'important',
          'wx.request,HTTPS,域名配置,请求'),
      _c('小程序数据缓存', 'concept', 4, '小程序本地数据缓存机制', 'supplementary',
          'Storage,缓存,本地存储,wx.setStorage'),
      _c('rpx单位', 'concept', 4, '小程序响应式像素单位，可根据屏幕宽度自适应', 'supplementary',
          'rpx,像素,自适应,屏幕适配'),
      _c('小程序发布流程', 'concept', 4, '小程序从开发到上线的审核与发布流程', 'supplementary',
          '发布,审核,体验版,正式版'),
      _c('TypeScript', 'language', 4, 'JavaScript的强类型超集，可用于小程序开发',
          'supplementary', 'TS,类型系统,编译,JavaScript超集'),

      // ══════════════════════════════════════════════════════════════════════
      // Chapter 5 — HarmonyOS多端应用开发 (21 concepts)
      // ══════════════════════════════════════════════════════════════════════
      _c('HarmonyOS NEXT', 'platform', 5, '华为纯自研鸿蒙操作系统，全面替代Android底座', 'core',
          '鸿蒙,华为,原生鸿蒙,全自研'),
      _c('ArkUI', 'framework', 5, 'HarmonyOS声明式UI开发框架', 'core',
          'ArkUI,声明式,UI框架,鸿蒙UI'),
      _c('ArkTS', 'language', 5, 'HarmonyOS应用开发语言，TypeScript的超集', 'core',
          'ArkTS,TypeScript,鸿蒙语言,静态类型'),
      _c('DevEco Studio', 'tool', 5, '华为官方HarmonyOS集成开发环境', 'core',
          'IDE,开发工具,华为,预览器'),
      _c('Stage模型', 'concept', 5, 'HarmonyOS应用的现代应用模型，取代FA模型', 'core',
          'Stage,应用模型,UIAbility,AbilityStage'),
      _c('UIAbility', 'concept', 5, 'Stage模型中的UI能力组件，类似Android Activity',
          'core', 'UIAbility,窗口,Ability,界面'),
      _c('ArkUI组件', 'concept', 5, 'ArkUI框架的内置UI组件体系', 'important',
          'Text,Column,Row,List,组件'),
      _c('ArkUI状态管理', 'concept', 5, 'ArkUI中的@State/@Prop/@Link等状态装饰器', 'core',
          '@State,@Prop,@Link,装饰器'),
      _c('分布式能力', 'technology', 5, 'HarmonyOS的跨设备分布式协同核心能力', 'core',
          '分布式,跨设备,协同,超级终端'),
      _c('分布式数据管理', 'technology', 5, 'HarmonyOS跨设备数据同步与分布式数据库', 'important',
          '分布式数据,数据同步,跨设备存储,KV数据库'),
      _c('元服务', 'concept', 5, 'HarmonyOS免安装、即用即走的轻量服务形态', 'important',
          '元服务,Atomic Service,免安装,即用'),
      _c('卡片服务', 'technology', 5, 'HarmonyOS桌面卡片，提供信息展示和快捷交互', 'important',
          '服务卡片,Widget,信息展示,桌面'),
      _c('鸿蒙通知系统', 'concept', 5, 'HarmonyOS的通知管理与推送机制', 'supplementary',
          '通知,推送,NotificationManager,消息'),
      _c('HAP/HAR', 'concept', 5, 'HarmonyOS的应用包格式和共享包格式', 'important',
          'HAP,HAR,应用包,共享包'),
      _c('鸿蒙路由导航', 'concept', 5, 'HarmonyOS中的页面路由和导航管理', 'important',
          'router,Navigation,路由,页面跳转'),
      _c('鸿蒙网络请求', 'concept', 5, 'HarmonyOS中的HTTP网络通信能力', 'important',
          'http,网络请求,数据获取,API调用'),
      _c('鸿蒙数据持久化', 'concept', 5, 'HarmonyOS的本地数据存储方案（Preferences/RDB）',
          'important', 'Preferences,RDB,数据持久化,存储'),
      _c('IoT开发', 'concept', 5, '基于HarmonyOS的物联网设备应用开发', 'supplementary',
          'IoT,物联网,嵌入式,智能设备'),
      _c('鸿蒙安全机制', 'concept', 5, 'HarmonyOS的权限管理和安全控制体系', 'supplementary',
          '权限,安全,访问控制,隐私'),
      _c('鸿蒙多端适配', 'concept', 5, 'HarmonyOS一套代码适配多种设备形态', 'important',
          '多端适配,响应式布局,自适应,栅格'),
      _c('鸿蒙动画系统', 'concept', 5, 'ArkUI的属性动画和转场动画能力', 'supplementary',
          '动画,transition,属性动画,转场'),

      // ══════════════════════════════════════════════════════════════════════
      // Chapter 6 — 综合开发实践 (22 concepts)
      // ══════════════════════════════════════════════════════════════════════
      _c('应用架构', 'pattern', 6, '应用程序的整体结构组织和分层设计', 'core', '架构,分层,设计,模式'),
      _c('MVVM模式', 'pattern', 6, 'Model-View-ViewModel架构模式，支持数据绑定', 'core',
          'MVVM,ViewModel,数据绑定,分离关注'),
      _c('MVP模式', 'pattern', 6, 'Model-View-Presenter架构模式，Presenter中介',
          'important', 'MVP,Presenter,接口,测试'),
      _c('MVC模式', 'pattern', 6, 'Model-View-Controller经典架构模式', 'important',
          'MVC,Controller,经典,分层'),
      _c('数据存储方案', 'concept', 6, '应用中本地和远程数据持久化策略的综合方案', 'important',
          '数据存储,持久化,缓存,同步'),
      _c('SQLite数据库', 'technology', 6, '轻量级嵌入式关系型数据库，广泛用于移动应用', 'core',
          'SQLite,关系型,SQL,本地数据库'),
      _c('网络编程', 'concept', 6, '移动应用中的网络通信技术（HTTP/WebSocket等）', 'important',
          'HTTP,REST,WebSocket,网络'),
      _c('API接口', 'concept', 6, '应用与后端服务通信的接口设计与调用', 'important',
          'API,RESTful,接口文档,数据交换'),
      _c('综合项目实践', 'concept', 6, '结合所学技术完成完整移动应用项目开发', 'core',
          '项目实践,实战,综合应用,案例'),
      _c('单元测试', 'concept', 6, '针对函数/方法/类的最小可测试单元进行验证', 'important',
          '单元测试,断言,Mock,测试用例'),
      _c('Widget测试', 'concept', 6, 'Flutter中针对Widget组件的UI测试', 'important',
          'Widget测试,testWidgets,find,pump'),
      _c('集成测试', 'concept', 6, '验证多个模块协同工作的端到端测试', 'supplementary',
          '集成测试,E2E,端到端,自动化'),
      _c('Git版本控制', 'tool', 6, '分布式版本控制系统，管理代码历史和协作', 'core', 'Git,版本控制,分支,合并'),
      _c('CI/CD', 'technology', 6, '持续集成与持续部署，自动化构建和发布流程', 'supplementary',
          'CI,CD,自动化,流水线'),
      _c('代码规范', 'concept', 6, '团队统一的代码风格和编码标准', 'important',
          '规范,Lint,风格指南,统一标准'),
      _c('需求分析', 'concept', 6, '分析用户需求并转化为功能规格的过程', 'important',
          '需求,用户故事,功能规格,分析'),
      _c('原型设计', 'concept', 6, '通过原型工具快速验证产品设计的方法', 'supplementary',
          '原型,线框图,Figma,Axure'),
      _c('调试技巧', 'concept', 6, '定位和修复应用Bug的技术方法', 'important',
          '调试,断点,日志,DevTools'),
      _c('性能测试', 'concept', 6, '评估应用性能指标的测试方法', 'supplementary',
          '性能测试,基准测试,压力测试,Profile'),
      _c('应用打包发布', 'concept', 6, '将应用编译打包并发布到各应用商店的流程', 'important',
          '打包,签名,发布,应用商店'),
      _c('依赖管理', 'concept', 6, '管理项目第三方库依赖的工具与实践', 'important',
          '依赖,包管理,pub,npm'),
      _c('响应式编程', 'pattern', 6, '基于数据流和变化传播的编程范式', 'supplementary',
          '响应式,Stream,RxDart,数据流'),
    ];

    debugPrint('[KnowledgeSeedService] 开始插入 ${concepts.length} 个概念...');
    int inserted = 0;
    for (final concept in concepts) {
      try {
        final id = await _dao.addConcept(concept);
        if (id > 0) inserted++;
      } catch (e) {
        debugPrint(
          '[KnowledgeSeedService] 插入概念失败: ${concept['concept_name']} — $e',
        );
      }
    }
    debugPrint('[KnowledgeSeedService] 概念插入结果: $inserted / ${concepts.length}');
  }

  // ── Relation seed data ────────────────────────────────────────────────────

  Future<void> _seedRelations() async {
    // Build a name → id lookup from all concepts currently in the DB.
    final allConcepts = await _dao.getAllConcepts();
    final nameToId = <String, int>{};
    for (final c in allConcepts) {
      final name = c['concept_name']?.toString();
      final id = c['id'] as int?;
      if (name != null && id != null) nameToId[name] = id;
    }

    // ── Raw relation definitions ────────────────────────────────────────
    // Format: [source, target, type, label, bidirectional, weight]
    final rawRelations = <List<dynamic>>[
      // ================================================================
      //  Chapter 1 — Internal relations
      // ================================================================
      ['移动应用开发', '原生应用', 'part_of', '包含', 0, 0.9],
      ['移动应用开发', 'WebApp', 'part_of', '包含', 0, 0.8],
      ['移动应用开发', '混合应用', 'part_of', '包含', 0, 0.9],
      ['移动应用开发', '跨平台应用', 'part_of', '包含', 0, 0.9],
      ['移动应用开发', '小程序', 'part_of', '包含', 0, 0.8],
      ['移动应用开发', '多端应用', 'part_of', '包含', 0, 0.8],
      ['WebApp', 'PWA', 'builds_upon', '演进为', 0, 0.8],
      ['原生应用', '混合应用', 'compared_with', '对比', 1, 0.9],
      ['原生应用', '跨平台应用', 'compared_with', '对比', 1, 0.9],
      ['混合应用', '跨平台应用', 'compared_with', '对比', 1, 0.8],
      ['声明式UI', '命令式UI', 'compared_with', '对比', 1, 0.9],
      ['移动端UI设计', '响应式设计', 'related_to', '涉及', 0, 0.8],
      ['移动端UI设计', '用户体验', 'related_to', '影响', 0, 0.8],
      ['性能优化', '用户体验', 'related_to', '提升', 0, 0.8],
      ['状态管理', '组件化开发', 'related_to', '配合使用', 1, 0.7],
      ['生命周期', '状态管理', 'related_to', '关联', 1, 0.7],
      ['声明式UI', '组件化开发', 'related_to', '天然支持', 0, 0.7],
      ['小程序', '应用分发', 'related_to', '免安装分发', 0, 0.6],
      ['移动应用开发', 'HarmonyOS平台', 'related_to', '目标平台', 0, 0.7],

      // ================================================================
      //  Chapter 2 — Internal relations
      // ================================================================
      ['Android四大组件', 'Activity', 'part_of', '包含', 0, 0.95],
      ['Activity', 'Activity生命周期', 'related_to', '具有', 0, 0.95],
      ['Activity', 'Intent', 'related_to', '通过Intent启动', 0, 0.9],
      ['Activity', 'Android布局系统', 'related_to', '使用布局', 0, 0.8],
      ['Android布局系统', 'RecyclerView', 'part_of', '包含', 0, 0.7],
      ['Jetpack', 'Jetpack Compose', 'part_of', '包含', 0, 0.9],
      ['Kotlin语言', 'Jetpack Compose', 'prerequisite', '前置知识', 0, 0.9],
      ['Kotlin语言', 'Android Studio', 'applied_in', '用于', 0, 0.8],
      ['Android Studio', 'Gradle', 'related_to', '内置构建', 0, 0.8],
      ['Android四大组件', 'Android权限管理', 'related_to', '需要权限', 0, 0.7],
      ['Android四大组件', 'Android数据存储', 'related_to', '配合使用', 0, 0.7],
      ['iOS开发', 'Swift语言', 'prerequisite', '需要掌握', 0, 0.95],
      ['iOS开发', 'Objective-C', 'related_to', '遗留支持', 0, 0.6],
      ['Swift语言', 'Objective-C', 'alternative_to', '替代', 0, 0.8],
      ['UIKit', 'SwiftUI', 'compared_with', '对比', 1, 0.9],
      ['UIKit', 'ViewController', 'related_to', '核心组件', 0, 0.9],
      ['iOS开发', 'iOS应用生命周期', 'related_to', '涵盖', 0, 0.8],
      ['iOS开发', 'iOS导航模式', 'related_to', '涵盖', 0, 0.7],
      ['iOS开发', 'Xcode', 'applied_in', '使用工具', 0, 0.9],
      ['iOS开发', 'CocoaPods', 'related_to', '依赖管理', 0, 0.7],
      ['iOS开发', 'iOS数据持久化', 'related_to', '数据存储', 0, 0.7],
      ['Jetpack Compose', 'Material Design', 'applied_in', '遵循规范', 0, 0.8],

      // ================================================================
      //  Chapter 3 — Internal relations
      // ================================================================
      ['Flutter', 'Dart语言', 'prerequisite', '前置知识', 0, 0.95],
      ['Flutter', 'Widget', 'part_of', '核心概念', 0, 0.95],
      ['Widget', 'StatefulWidget', 'part_of', '子类型', 0, 0.95],
      ['Widget', 'StatelessWidget', 'part_of', '子类型', 0, 0.95],
      ['StatefulWidget', 'StatelessWidget', 'compared_with', '对比', 1, 0.9],
      ['Flutter', 'Flutter状态管理', 'part_of', '核心概念', 0, 0.9],
      ['Flutter状态管理', 'Provider', 'part_of', '方案之一', 0, 0.8],
      ['StatefulWidget', 'Flutter状态管理', 'related_to', '基础方式', 0, 0.8],
      ['Flutter', 'Flutter布局系统', 'part_of', '核心概念', 0, 0.9],
      ['Flutter', 'Flutter路由导航', 'part_of', '核心概念', 0, 0.8],
      ['Flutter', 'Hot Reload', 'part_of', '开发特性', 0, 0.8],
      ['Flutter', '渲染引擎', 'part_of', '底层引擎', 0, 0.9],
      ['Flutter', '平台通道', 'part_of', '原生通信', 0, 0.8],
      ['平台通道', 'Flutter插件开发', 'prerequisite', '前置知识', 0, 0.8],
      ['Dart语言', 'Dart异步编程', 'part_of', '语言特性', 0, 0.9],
      ['React Native', 'JavaScript', 'prerequisite', '前置知识', 0, 0.95],
      ['React Native', 'JSX语法', 'part_of', '语法特性', 0, 0.8],
      ['React Native', 'Bridge桥接', 'part_of', '核心机制', 0, 0.9],
      ['Flutter', 'React Native', 'compared_with', '框架对比', 1, 0.95],
      ['Uniapp', 'Vue.js', 'prerequisite', '基于Vue', 0, 0.9],
      ['MAUI', 'C#语言', 'prerequisite', '前置知识', 0, 0.9],
      ['Flutter', 'MAUI', 'compared_with', '框架对比', 1, 0.7],
      ['Flutter', 'Uniapp', 'compared_with', '框架对比', 1, 0.7],
      ['React Native', 'Uniapp', 'compared_with', '框架对比', 1, 0.7],
      ['React Native', 'MAUI', 'alternative_to', '替代方案', 1, 0.6],
      ['混合应用开发', 'WebView', 'related_to', '核心技术', 0, 0.8],
      ['跨平台性能对比', 'Flutter', 'related_to', '对比对象', 0, 0.8],
      ['跨平台性能对比', 'React Native', 'related_to', '对比对象', 0, 0.8],

      // ================================================================
      //  Chapter 4 — Internal relations
      // ================================================================
      ['微信小程序', 'MINA框架', 'part_of', '底层框架', 0, 0.95],
      ['微信小程序', 'WXML', 'part_of', '标记语言', 0, 0.9],
      ['微信小程序', 'WXSS', 'part_of', '样式语言', 0, 0.9],
      ['微信小程序', '小程序生命周期', 'part_of', '核心概念', 0, 0.9],
      ['微信小程序', '小程序组件', 'part_of', '组件体系', 0, 0.9],
      ['微信小程序', '小程序API', 'part_of', 'API体系', 0, 0.9],
      ['微信小程序', '云开发', 'extends', '扩展能力', 0, 0.8],
      ['微信小程序', '小程序状态管理', 'part_of', '状态方案', 0, 0.7],
      ['WXML', 'WXS脚本', 'related_to', '内嵌脚本', 0, 0.7],
      ['微信小程序', '小程序路由', 'part_of', '路由机制', 0, 0.8],
      ['小程序组件', '小程序自定义组件', 'builds_upon', '扩展', 0, 0.8],
      ['微信小程序', 'Taro', 'related_to', '开发框架', 0, 0.7],
      ['微信小程序', '微信开发者工具', 'applied_in', '使用工具', 0, 0.9],
      ['微信小程序', '小程序分包加载', 'extends', '优化方案', 0, 0.7],
      ['微信小程序', '微信支付', 'extends', '支付能力', 0, 0.7],
      ['微信小程序', '小程序插件', 'extends', '插件机制', 0, 0.6],
      ['微信小程序', '小程序双线程模型', 'part_of', '架构模型', 0, 0.9],
      ['小程序API', '小程序网络请求', 'part_of', '包含', 0, 0.8],
      ['小程序API', '小程序数据缓存', 'part_of', '包含', 0, 0.8],
      ['WXSS', 'rpx单位', 'part_of', '单位系统', 0, 0.7],
      ['微信小程序', '小程序发布流程', 'related_to', '发布流程', 0, 0.7],
      ['TypeScript', 'WXML', 'related_to', '可配合使用', 0, 0.5],
      ['Taro', 'TypeScript', 'related_to', '支持', 0, 0.6],

      // ================================================================
      //  Chapter 5 — Internal relations
      // ================================================================
      ['HarmonyOS NEXT', 'ArkUI', 'part_of', 'UI框架', 0, 0.95],
      ['HarmonyOS NEXT', 'ArkTS', 'prerequisite', '开发语言', 0, 0.95],
      ['HarmonyOS NEXT', 'DevEco Studio', 'applied_in', '使用工具', 0, 0.9],
      ['HarmonyOS NEXT', 'Stage模型', 'part_of', '应用模型', 0, 0.9],
      ['Stage模型', 'UIAbility', 'part_of', '核心组件', 0, 0.95],
      ['ArkUI', 'ArkUI组件', 'part_of', '组件体系', 0, 0.9],
      ['ArkUI', 'ArkUI状态管理', 'part_of', '状态管理', 0, 0.9],
      ['HarmonyOS NEXT', '分布式能力', 'part_of', '核心能力', 0, 0.9],
      ['分布式能力', '分布式数据管理', 'part_of', '数据层', 0, 0.9],
      ['HarmonyOS NEXT', '元服务', 'part_of', '服务形态', 0, 0.8],
      ['HarmonyOS NEXT', '卡片服务', 'part_of', '服务形态', 0, 0.8],
      ['元服务', '卡片服务', 'related_to', '关联', 1, 0.7],
      ['HarmonyOS NEXT', '鸿蒙通知系统', 'part_of', '系统能力', 0, 0.6],
      ['HarmonyOS NEXT', 'HAP/HAR', 'part_of', '包管理', 0, 0.8],
      ['HarmonyOS NEXT', '鸿蒙路由导航', 'part_of', '路由机制', 0, 0.8],
      ['HarmonyOS NEXT', '鸿蒙网络请求', 'part_of', '网络能力', 0, 0.7],
      ['HarmonyOS NEXT', '鸿蒙数据持久化', 'part_of', '数据存储', 0, 0.7],
      ['HarmonyOS NEXT', 'IoT开发', 'extends', '应用场景', 0, 0.6],
      ['HarmonyOS NEXT', '鸿蒙安全机制', 'part_of', '安全体系', 0, 0.6],
      ['HarmonyOS NEXT', '鸿蒙多端适配', 'part_of', '多端方案', 0, 0.8],
      ['ArkUI', '鸿蒙动画系统', 'part_of', '动画能力', 0, 0.7],
      ['ArkTS', 'TypeScript', 'builds_upon', '基于TS扩展', 0, 0.9],

      // ================================================================
      //  Chapter 6 — Internal relations
      // ================================================================
      ['应用架构', 'MVVM模式', 'part_of', '架构模式', 0, 0.9],
      ['应用架构', 'MVP模式', 'part_of', '架构模式', 0, 0.8],
      ['应用架构', 'MVC模式', 'part_of', '架构模式', 0, 0.8],
      ['MVVM模式', 'MVP模式', 'compared_with', '架构对比', 1, 0.8],
      ['MVVM模式', 'MVC模式', 'compared_with', '架构对比', 1, 0.8],
      ['MVP模式', 'MVC模式', 'compared_with', '架构对比', 1, 0.8],
      ['MVC模式', 'MVVM模式', 'builds_upon', '演进为', 0, 0.7],
      ['数据存储方案', 'SQLite数据库', 'part_of', '包含', 0, 0.9],
      ['网络编程', 'API接口', 'related_to', '调用接口', 0, 0.9],
      ['综合项目实践', '应用架构', 'applied_in', '应用', 0, 0.9],
      ['综合项目实践', '数据存储方案', 'applied_in', '应用', 0, 0.8],
      ['综合项目实践', '网络编程', 'applied_in', '应用', 0, 0.8],
      ['单元测试', 'Widget测试', 'related_to', '测试层次', 1, 0.8],
      ['Widget测试', '集成测试', 'related_to', '测试层次', 1, 0.7],
      ['单元测试', '集成测试', 'builds_upon', '递进关系', 0, 0.7],
      ['Git版本控制', 'CI/CD', 'prerequisite', '前置知识', 0, 0.8],
      ['代码规范', 'Git版本控制', 'related_to', '协作规范', 1, 0.6],
      ['需求分析', '原型设计', 'prerequisite', '前序步骤', 0, 0.9],
      ['原型设计', '综合项目实践', 'prerequisite', '设计先行', 0, 0.7],
      ['调试技巧', '性能测试', 'related_to', '配合使用', 1, 0.6],
      ['应用打包发布', 'CI/CD', 'related_to', '自动化发布', 0, 0.7],
      ['依赖管理', 'Git版本控制', 'related_to', '配合使用', 1, 0.6],
      ['响应式编程', 'Flutter状态管理', 'related_to', '相关范式', 0, 0.7],

      // ================================================================
      //  Cross-chapter relations
      // ================================================================
      // Ch1 → Ch2
      ['原生应用', 'Android四大组件', 'part_of', 'Android原生', 0, 0.9],
      ['原生应用', 'iOS开发', 'part_of', 'iOS原生', 0, 0.9],
      ['移动应用开发', 'Android Studio', 'related_to', '开发工具', 0, 0.7],
      ['移动应用开发', 'Xcode', 'related_to', '开发工具', 0, 0.7],
      ['生命周期', 'Activity生命周期', 'applied_in', 'Android中', 0, 0.9],
      ['生命周期', 'iOS应用生命周期', 'applied_in', 'iOS中', 0, 0.9],
      ['声明式UI', 'Jetpack Compose', 'applied_in', 'Android中', 0, 0.9],
      ['声明式UI', 'SwiftUI', 'applied_in', 'iOS中', 0, 0.9],
      ['命令式UI', 'UIKit', 'applied_in', 'iOS中', 0, 0.9],
      ['命令式UI', 'Android布局系统', 'applied_in', 'Android中', 0, 0.8],
      ['状态管理', 'Android数据存储', 'related_to', '数据持久化', 0, 0.6],
      ['移动端UI设计', 'Material Design', 'applied_in', 'MD规范', 0, 0.8],

      // Ch1 → Ch3
      ['跨平台应用', 'Flutter', 'applied_in', '代表框架', 0, 0.95],
      ['跨平台应用', 'React Native', 'applied_in', '代表框架', 0, 0.9],
      ['跨平台应用', 'Uniapp', 'applied_in', '代表框架', 0, 0.7],
      ['混合应用', '混合应用开发', 'related_to', '详细展开', 0, 0.9],
      ['状态管理', 'Flutter状态管理', 'applied_in', 'Flutter中', 0, 0.9],
      ['组件化开发', 'Widget', 'applied_in', 'Flutter中', 0, 0.9],
      ['声明式UI', 'Flutter', 'applied_in', 'Flutter采用', 0, 0.95],
      ['性能优化', '渲染引擎', 'related_to', '渲染优化', 0, 0.7],
      ['生命周期', 'StatefulWidget', 'applied_in', 'Flutter中', 0, 0.8],
      ['移动应用开发', 'Flutter', 'related_to', '主流框架', 0, 0.9],

      // Ch1 → Ch4
      ['小程序', '微信小程序', 'applied_in', '代表产品', 0, 0.95],
      ['状态管理', '小程序状态管理', 'applied_in', '小程序中', 0, 0.7],
      ['生命周期', '小程序生命周期', 'applied_in', '小程序中', 0, 0.8],
      ['组件化开发', '小程序自定义组件', 'applied_in', '小程序中', 0, 0.7],

      // Ch1 → Ch5
      ['多端应用', 'HarmonyOS NEXT', 'applied_in', '鸿蒙平台', 0, 0.9],
      ['HarmonyOS平台', 'HarmonyOS NEXT', 'builds_upon', '演进为', 0, 0.95],
      ['声明式UI', 'ArkUI', 'applied_in', '鸿蒙中', 0, 0.9],
      ['状态管理', 'ArkUI状态管理', 'applied_in', '鸿蒙中', 0, 0.8],
      ['生命周期', 'UIAbility', 'applied_in', '鸿蒙中', 0, 0.7],
      ['响应式设计', '鸿蒙多端适配', 'applied_in', '鸿蒙中', 0, 0.7],

      // Ch1 → Ch6
      ['移动应用开发', '综合项目实践', 'related_to', '实践应用', 0, 0.8],
      ['移动应用开发', '应用架构', 'related_to', '架构基础', 0, 0.8],
      ['状态管理', 'MVVM模式', 'related_to', '架构支持', 0, 0.7],
      ['性能优化', '性能测试', 'related_to', '测试验证', 0, 0.7],
      ['应用分发', '应用打包发布', 'related_to', '发布流程', 0, 0.8],
      ['用户体验', '原型设计', 'related_to', '设计验证', 0, 0.6],

      // Ch2 → Ch3
      ['Kotlin语言', 'Dart语言', 'compared_with', '语言对比', 1, 0.7],
      ['Swift语言', 'Dart语言', 'compared_with', '语言对比', 1, 0.7],
      ['Jetpack Compose', 'Flutter', 'compared_with', '声明式框架对比', 1, 0.9],
      ['SwiftUI', 'Flutter', 'compared_with', '声明式框架对比', 1, 0.9],
      ['Jetpack Compose', 'SwiftUI', 'compared_with', '声明式框架对比', 1, 0.8],
      ['Android数据存储', 'SQLite数据库', 'related_to', '使用SQLite', 0, 0.7],
      ['iOS数据持久化', 'SQLite数据库', 'related_to', '使用SQLite', 0, 0.6],
      ['Activity生命周期', 'StatefulWidget', 'compared_with', '生命周期对比', 1, 0.6],
      ['Android布局系统', 'Flutter布局系统', 'compared_with', '布局对比', 1, 0.7],
      ['iOS导航模式', 'Flutter路由导航', 'compared_with', '导航对比', 1, 0.7],
      ['Material Design', 'Flutter', 'applied_in', 'Flutter遵循MD', 0, 0.8],

      // Ch2 → Ch5
      ['Jetpack Compose', 'ArkUI', 'compared_with', '声明式框架对比', 1, 0.8],
      ['Activity', 'UIAbility', 'compared_with', '组件对比', 1, 0.8],
      ['Activity生命周期', 'Stage模型', 'compared_with', '模型对比', 1, 0.7],
      ['Android Studio', 'DevEco Studio', 'compared_with', 'IDE对比', 1, 0.8],
      ['Gradle', 'HAP/HAR', 'compared_with', '构建对比', 1, 0.6],
      ['Android权限管理', '鸿蒙安全机制', 'compared_with', '安全对比', 1, 0.6],
      ['Android数据存储', '鸿蒙数据持久化', 'compared_with', '存储对比', 1, 0.7],
      ['Kotlin语言', 'ArkTS', 'compared_with', '语言对比', 1, 0.7],

      // Ch2 → Ch6
      ['Android四大组件', 'MVC模式', 'applied_in', '架构实践', 0, 0.6],
      ['ViewController', 'MVC模式', 'applied_in', '经典MVC', 0, 0.7],
      ['Xcode', '调试技巧', 'related_to', 'Instruments', 0, 0.6],
      ['CocoaPods', '依赖管理', 'applied_in', 'iOS依赖', 0, 0.7],
      ['Gradle', '依赖管理', 'applied_in', 'Android依赖', 0, 0.7],

      // Ch3 → Ch4
      ['Flutter', '微信小程序', 'compared_with', '技术对比', 1, 0.7],
      ['React Native', '微信小程序', 'compared_with', '技术对比', 1, 0.6],
      ['Uniapp', 'Taro', 'compared_with', '多端框架对比', 1, 0.7],
      ['Uniapp', '微信小程序', 'related_to', '支持小程序', 0, 0.7],
      ['JavaScript', 'WXML', 'related_to', '类似语法', 0, 0.5],
      ['Vue.js', 'MINA框架', 'related_to', '语法相似', 0, 0.6],
      ['Dart异步编程', '小程序网络请求', 'compared_with', '异步对比', 1, 0.5],
      ['Hot Reload', '微信开发者工具', 'compared_with', '开发效率对比', 1, 0.6],
      ['Flutter布局系统', 'WXSS', 'compared_with', '布局对比', 1, 0.5],
      ['Flutter路由导航', '小程序路由', 'compared_with', '路由对比', 1, 0.6],

      // Ch3 → Ch5
      ['Flutter', 'HarmonyOS NEXT', 'compared_with', '平台对比', 1, 0.8],
      ['Dart语言', 'ArkTS', 'compared_with', '语言对比', 1, 0.7],
      ['Flutter状态管理', 'ArkUI状态管理', 'compared_with', '状态管理对比', 1, 0.8],
      ['Flutter布局系统', 'ArkUI组件', 'compared_with', '布局对比', 1, 0.7],
      ['Flutter路由导航', '鸿蒙路由导航', 'compared_with', '路由对比', 1, 0.7],
      ['渲染引擎', 'ArkUI', 'compared_with', '渲染对比', 1, 0.6],
      ['SwiftUI', 'ArkUI', 'compared_with', '声明式框架对比', 1, 0.8],

      // Ch3 → Ch6
      ['Flutter', 'Widget测试', 'related_to', '测试方式', 0, 0.8],
      ['Dart语言', '单元测试', 'related_to', '编写测试', 0, 0.7],
      ['Flutter', 'MVVM模式', 'applied_in', '推荐架构', 0, 0.7],
      ['Provider', 'MVVM模式', 'related_to', '状态绑定', 0, 0.7],
      ['Dart异步编程', '响应式编程', 'related_to', 'Stream关联', 0, 0.7],
      ['Dart异步编程', '网络编程', 'applied_in', '网络请求', 0, 0.7],
      ['平台通道', 'SQLite数据库', 'related_to', '数据库访问', 0, 0.5],
      ['Flutter', '应用打包发布', 'related_to', '打包流程', 0, 0.7],

      // Ch4 → Ch5
      ['微信小程序', 'HarmonyOS NEXT', 'compared_with', '平台对比', 1, 0.7],
      ['小程序双线程模型', 'Stage模型', 'compared_with', '架构对比', 1, 0.6],
      ['微信开发者工具', 'DevEco Studio', 'compared_with', 'IDE对比', 1, 0.7],
      ['小程序组件', 'ArkUI组件', 'compared_with', '组件对比', 1, 0.6],
      ['小程序生命周期', 'UIAbility', 'compared_with', '生命周期对比', 1, 0.6],
      ['元服务', '微信小程序', 'compared_with', '轻应用对比', 1, 0.7],

      // Ch4 → Ch6
      ['微信小程序', '综合项目实践', 'applied_in', '项目实践', 0, 0.6],
      ['云开发', '数据存储方案', 'related_to', '存储方案', 0, 0.6],
      ['小程序发布流程', '应用打包发布', 'related_to', '发布流程', 0, 0.7],
      ['TypeScript', '代码规范', 'related_to', '类型安全', 0, 0.5],

      // Ch5 → Ch6
      ['HarmonyOS NEXT', '综合项目实践', 'applied_in', '项目实践', 0, 0.7],
      ['ArkTS', '单元测试', 'related_to', '编写测试', 0, 0.5],
      ['DevEco Studio', '调试技巧', 'related_to', '调试工具', 0, 0.6],
      ['鸿蒙数据持久化', '数据存储方案', 'related_to', '鸿蒙存储', 0, 0.7],
      ['鸿蒙网络请求', '网络编程', 'related_to', '鸿蒙网络', 0, 0.7],
      ['HAP/HAR', '应用打包发布', 'related_to', '鸿蒙打包', 0, 0.7],
      ['鸿蒙多端适配', '响应式编程', 'related_to', '自适应开发', 0, 0.5],

      // Additional cross-chapter prerequisite chains
      ['移动应用开发', 'Kotlin语言', 'prerequisite', '学习Android', 0, 0.7],
      ['移动应用开发', 'Swift语言', 'prerequisite', '学习iOS', 0, 0.7],
      ['移动应用开发', 'Dart语言', 'prerequisite', '学习Flutter', 0, 0.7],
      ['JavaScript', 'TypeScript', 'prerequisite', '基础语言', 0, 0.9],
      ['JavaScript', 'Vue.js', 'prerequisite', '前端基础', 0, 0.9],
      ['需求分析', '应用架构', 'prerequisite', '需求先于设计', 0, 0.8],
      ['应用架构', '综合项目实践', 'prerequisite', '架构先于实践', 0, 0.8],
      ['Git版本控制', '综合项目实践', 'prerequisite', '版本管理', 0, 0.7],
      ['代码规范', '综合项目实践', 'prerequisite', '编码规范', 0, 0.6],
    ];

    debugPrint(
      '[KnowledgeSeedService] 开始插入 ${rawRelations.length} 条关系...',
    );

    int inserted = 0;
    int skipped = 0;
    for (final r in rawRelations) {
      final sourceName = r[0] as String;
      final targetName = r[1] as String;
      final relationType = r[2] as String;
      final label = r[3] as String;
      final bidirectional = r[4] as int;
      final weight = (r[5] as num).toDouble();

      final sourceId = nameToId[sourceName];
      final targetId = nameToId[targetName];

      if (sourceId == null || targetId == null) {
        debugPrint(
          '[KnowledgeSeedService] 跳过关系: "$sourceName" → "$targetName" '
          '(sourceId=$sourceId, targetId=$targetId)',
        );
        skipped++;
        continue;
      }

      try {
        final id = await _dao.addRelation({
          'source_concept_id': sourceId,
          'target_concept_id': targetId,
          'relation_type': relationType,
          'relation_label': label,
          'description': '$sourceName → $targetName ($label)',
          'bidirectional': bidirectional,
          'weight': weight,
          'ai_generated': 0,
          'confidence': 1.0,
        });
        if (id > 0) inserted++;
      } catch (e) {
        debugPrint(
          '[KnowledgeSeedService] 插入关系失败: "$sourceName" → "$targetName" — $e',
        );
      }
    }

    debugPrint(
      '[KnowledgeSeedService] 关系插入结果: $inserted / ${rawRelations.length} '
      '(跳过 $skipped 条)',
    );
  }
}
