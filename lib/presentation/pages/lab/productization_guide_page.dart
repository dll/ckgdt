import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 产品化引导检查清单页面
// 帮助学生将实验项目转化为完整产品，提供分类检查项与实用建议
// ─────────────────────────────────────────────────────────────────────────────

class ProductizationGuidePage extends StatefulWidget {
  const ProductizationGuidePage({super.key});

  @override
  State<ProductizationGuidePage> createState() =>
      _ProductizationGuidePageState();
}

class _ProductizationGuidePageState extends State<ProductizationGuidePage> {
  // ── 检查清单数据 ─────────────────────────────────────────────────────────
  late final List<_CheckCategory> _categories;

  @override
  void initState() {
    super.initState();
    _categories = _buildCategories();
    _loadProgress();
  }

  static const _prefsKey = 'productization_checked';

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey) ?? [];
    setState(() {
      for (final category in _categories) {
        for (final item in category.items) {
          item.isChecked = saved.contains(item.title);
        }
      }
    });
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final checked = <String>[];
    for (final category in _categories) {
      for (final item in category.items) {
        if (item.isChecked) checked.add(item.title);
      }
    }
    await prefs.setStringList(_prefsKey, checked);
  }

  // ── 计算总体进度 ─────────────────────────────────────────────────────────
  int get _totalItems =>
      _categories.fold<int>(0, (sum, c) => sum + c.items.length);

  int get _checkedItems =>
      _categories.fold<int>(0, (sum, c) => sum + c.checkedCount);

  double get _progressPercent =>
      _totalItems == 0 ? 0 : _checkedItems / _totalItems;

  Color _progressColor(double percent) {
    if (percent >= 0.9) return const Color(0xFF43A047);
    if (percent >= 0.6) return const Color(0xFF1E88E5);
    if (percent >= 0.3) return const Color(0xFFFB8C00);
    return const Color(0xFFE53935);
  }

  String _motivationalMessage(double percent) {
    if (percent >= 1.0) return '恭喜你！所有检查项均已完成，你的项目已具备产品化水准！';
    if (percent >= 0.9) return '就差最后一步了！坚持完成剩余项目，即将大功告成！';
    if (percent >= 0.6) return '进展不错！继续保持，你的项目正在走向成熟。';
    if (percent >= 0.3) return '已经有了良好的开端，加油完成更多检查项吧！';
    return '万事开头难，从第一个检查项开始，逐步迈向产品化！';
  }

  // ── 重置进度 ─────────────────────────────────────────────────────────────
  void _resetProgress() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置进度'),
        content: const Text('确定要重置所有检查项的完成状态吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          for (final category in _categories) {
            for (final item in category.items) {
              item.isChecked = false;
            }
          }
        });
        _saveProgress();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已重置所有检查项')),
        );
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final gradient = AppGradientTheme.of(context);
    final percent = _progressPercent;
    final pColor = _progressColor(percent);

    return Scaffold(
      appBar: AppBar(
        title: const Text('产品化检查清单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: '重置进度',
            onPressed: _resetProgress,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // ── 顶部渐变 Banner ──────────────────────────────────────────────
          _buildHeaderBanner(gradient, percent, pColor),
          const SizedBox(height: 16),

          // ── 各分类展开列表 ──────────────────────────────────────────────
          ..._categories.map((category) => _buildCategoryTile(category)),

          const SizedBox(height: 20),

          // ── 底部汇总卡片 ────────────────────────────────────────────────
          _buildSummaryCard(percent, pColor),
        ],
      ),
    );
  }

  // ── 顶部渐变 Banner ─────────────────────────────────────────────────────

  Widget _buildHeaderBanner(
      AppGradientTheme gradient, double percent, Color pColor) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: gradient.linearGradient,
        boxShadow: [
          BoxShadow(
            color: gradient.gradientStart.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '产品化检查清单',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '将实验项目转化为完整产品',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // 百分比环形指示器
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: percent,
                      strokeWidth: 5,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    Text(
                      '${(percent * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已完成 $_checkedItems / $_totalItems 项',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── 分类展开 Tile ───────────────────────────────────────────────────────

  Widget _buildCategoryTile(_CheckCategory category) {
    final total = category.items.length;
    final checked = category.checkedCount;
    final categoryPercent = total == 0 ? 0.0 : checked / total;
    final pColor = _progressColor(categoryPercent);
    final isComplete = checked == total;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: category.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(category.icon, color: category.color, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                category.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isComplete)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '已完成',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Text(
                '$checked/$total',
                style: TextStyle(
                  fontSize: 12,
                  color: pColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: categoryPercent,
              minHeight: 4,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(pColor),
            ),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        children: category.items
            .map((item) => _buildCheckItem(item, category.color))
            .toList(),
      ),
    );
  }

  // ── 单个检查项 ──────────────────────────────────────────────────────────

  Widget _buildCheckItem(_CheckItem item, Color categoryColor) {
    return CheckboxListTile(
      value: item.isChecked,
      onChanged: (val) {
        setState(() => item.isChecked = val ?? false);
        _saveProgress();
      },
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: categoryColor,
      title: Text(
        item.title,
        style: TextStyle(
          fontSize: 14,
          decoration: item.isChecked ? TextDecoration.lineThrough : null,
          color: item.isChecked ? Colors.grey : null,
        ),
      ),
      secondary: IconButton(
        icon: Icon(
          Icons.lightbulb_outline,
          size: 20,
          color: Colors.amber[700],
        ),
        tooltip: '查看建议',
        onPressed: () => _showTipDialog(item),
      ),
      dense: true,
    );
  }

  // ── 建议弹窗 ────────────────────────────────────────────────────────────

  void _showTipDialog(_CheckItem item) {
    final primary = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.tips_and_updates, color: Colors.amber[700], size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.tip,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[800],
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (item.reference.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '参考资源',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.reference,
                style: TextStyle(
                  fontSize: 12,
                  color: primary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ── 底部汇总卡片 ────────────────────────────────────────────────────────

  Widget _buildSummaryCard(double percent, Color pColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 完成度统计行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryStatItem(
                  icon: Icons.checklist,
                  value: '$_totalItems',
                  label: '总检查项',
                  color: Colors.blueGrey,
                ),
                _summaryStatItem(
                  icon: Icons.check_circle,
                  value: '$_checkedItems',
                  label: '已完成',
                  color: const Color(0xFF43A047),
                ),
                _summaryStatItem(
                  icon: Icons.pending,
                  value: '${_totalItems - _checkedItems}',
                  label: '待完成',
                  color: const Color(0xFFFB8C00),
                ),
                _summaryStatItem(
                  icon: Icons.speed,
                  value: '${(percent * 100).toInt()}%',
                  label: '完成度',
                  color: pColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            // 激励语
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    percent >= 0.9
                        ? Icons.celebration
                        : percent >= 0.6
                            ? Icons.trending_up
                            : percent >= 0.3
                                ? Icons.emoji_events
                                : Icons.flag,
                    color: pColor,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _motivationalMessage(percent),
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 分类完成度一览
            ...(_categories.map((c) {
              final cTotal = c.items.length;
              final cChecked = c.checkedCount;
              final cPercent = cTotal == 0 ? 0.0 : cChecked / cTotal;
              final cColor = _progressColor(cPercent);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(c.icon, size: 16, color: c.color),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: Text(
                        c.title,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: cPercent,
                          minHeight: 6,
                          backgroundColor:
                              Colors.grey.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(cColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$cChecked/$cTotal',
                      style: TextStyle(
                        fontSize: 11,
                        color: cColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            })),
          ],
        ),
      ),
    );
  }

  Widget _summaryStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 检查清单数据定义
  // ══════════════════════════════════════════════════════════════════════════

  List<_CheckCategory> _buildCategories() {
    return [
      // ── 1. 需求与设计 ───────────────────────────────────────────────────
      _CheckCategory(
        title: '需求与设计',
        icon: Icons.design_services,
        color: const Color(0xFF7C4DFF),
        items: [
          _CheckItem(
            title: '明确目标用户群体',
            tip: '通过用户画像（Persona）明确你的应用为谁服务。'
                '考虑年龄、职业、使用场景和核心痛点。'
                '建议制作 2-3 个典型用户画像卡片。',
            reference: '推荐工具：Figma Persona 模板、ProcessOn',
          ),
          _CheckItem(
            title: '完成竞品分析',
            tip: '调研至少 3 款同类应用，从功能、UI、性能、'
                '用户评价四个维度对比。制作竞品分析矩阵表，'
                '找出差异化优势和改进空间。',
            reference: '分析框架：SWOT 分析、功能对标矩阵',
          ),
          _CheckItem(
            title: '编写需求规格说明书',
            tip: '包含功能需求（FR）和非功能需求（NFR）。'
                '使用用例图或用户故事描述核心流程。'
                '标注优先级（P0/P1/P2），确保 MVP 范围清晰。',
            reference: '模板参考：IEEE 830 软件需求规格说明',
          ),
          _CheckItem(
            title: '完成 UI/UX 设计稿',
            tip: '先画线框图（Wireframe），确认信息架构和交互流程，'
                '再制作高保真设计稿。注意遵循 Material Design 3 规范，'
                '保持视觉一致性（色彩、字体、间距）。',
            reference: '工具推荐：Figma、MasterGo、即时设计',
          ),
          _CheckItem(
            title: '制定技术选型方案',
            tip: '对比不同技术方案的优劣，记录选型理由。'
                '包括框架选择、状态管理、网络库、本地存储等。'
                '考虑团队技术栈、社区活跃度和长期维护成本。',
            reference: 'Flutter 技术选型参考：pub.dev 评分与维护状态',
          ),
        ],
      ),

      // ── 2. 代码质量 ─────────────────────────────────────────────────────
      _CheckCategory(
        title: '代码质量',
        icon: Icons.code,
        color: const Color(0xFF00897B),
        items: [
          _CheckItem(
            title: '代码遵循规范（命名、注释、目录结构）',
            tip: '使用 Dart 官方命名规范：文件名 snake_case，'
                '类名 PascalCase，变量/方法 camelCase。'
                '每个公开 API 添加文档注释（///），'
                '目录结构按功能模块分层组织。',
            reference: 'dart.dev/guides/language/effective-dart/style',
          ),
          _CheckItem(
            title: '消除所有编译警告',
            tip: '运行 flutter analyze 检查所有警告和提示。'
                '逐一解决 unused imports、deprecated API、'
                '类型不匹配等问题。目标：0 warning、0 info。',
            reference: '命令：flutter analyze --no-fatal-infos',
          ),
          _CheckItem(
            title: '添加单元测试（覆盖率 > 60%）',
            tip: '对 Model 层的 fromMap/toMap、DAO 层的 CRUD、'
                'Service 层的业务逻辑编写单元测试。'
                '使用 flutter test --coverage 生成覆盖率报告，'
                '确保核心逻辑覆盖率不低于 60%。',
            reference: '命令：flutter test --coverage && genhtml coverage/lcov.info',
          ),
          _CheckItem(
            title: '添加集成测试',
            tip: '使用 integration_test 包编写端到端测试。'
                '至少覆盖主要用户流程：登录 → 浏览图谱 → 答题 → 查看进度。'
                '在真实设备或模拟器上运行验证。',
            reference: 'flutter.dev/docs/testing/integration-tests',
          ),
          _CheckItem(
            title: '代码审查（至少一轮）',
            tip: '邀请同学或导师进行代码审查。关注点：'
                '架构合理性、命名清晰度、异常处理完整性、'
                '潜在性能问题、安全漏洞。'
                '使用 PR + Review Comment 记录审查意见。',
            reference: '代码审查清单：Google Engineering Practices',
          ),
        ],
      ),

      // ── 3. 功能完整性 ───────────────────────────────────────────────────
      _CheckCategory(
        title: '功能完整性',
        icon: Icons.verified,
        color: const Color(0xFF1E88E5),
        items: [
          _CheckItem(
            title: '核心功能全部实现',
            tip: '对照需求规格说明书，逐一验证每个核心功能。'
                '使用测试用例矩阵追踪功能实现状态。'
                '所有 P0 功能必须 100% 完成，P1 完成度 > 80%。',
            reference: '参考本项目 docs/testing/test_cases.md',
          ),
          _CheckItem(
            title: '异常处理与错误提示',
            tip: '为所有网络请求、数据库操作、文件操作添加 try-catch。'
                '使用用户友好的错误提示替代技术性错误信息。'
                '关键操作失败时提供重试选项。',
            reference: '模式：Result<T> 封装成功/失败状态',
          ),
          _CheckItem(
            title: '网络断开/超时处理',
            tip: '检测网络连通性（connectivity_plus 包），'
                '在无网络时显示离线提示并降级到本地缓存。'
                '设置合理的请求超时时间（建议 15-30 秒）。',
            reference: 'pub.dev: connectivity_plus',
          ),
          _CheckItem(
            title: '空数据状态页面',
            tip: '为列表页、详情页的空数据状态设计专属空态页面。'
                '包含插画/图标 + 文字说明 + 操作引导按钮。'
                '避免显示空白页面让用户困惑。',
            reference: '设计参考：Material Design Empty States',
          ),
          _CheckItem(
            title: '加载状态指示器',
            tip: '所有异步操作都需要加载状态反馈：'
                '短时操作用 CircularProgressIndicator，'
                '长时操作用带进度百分比的加载页。'
                '骨架屏（Shimmer）可提升感知性能。',
            reference: 'pub.dev: shimmer',
          ),
        ],
      ),

      // ── 4. 用户体验 ─────────────────────────────────────────────────────
      _CheckCategory(
        title: '用户体验',
        icon: Icons.touch_app,
        color: const Color(0xFFE91E63),
        items: [
          _CheckItem(
            title: '启动页/引导页',
            tip: '设计品牌启动页（Splash Screen），展示应用图标和名称，'
                '持续 1.5-2 秒。首次安装显示 3-4 页引导页，'
                '介绍核心功能和使用方式。',
            reference: 'pub.dev: flutter_native_splash、introduction_screen',
          ),
          _CheckItem(
            title: '响应式布局（适配不同屏幕）',
            tip: '使用 MediaQuery 和 LayoutBuilder 适配不同屏幕尺寸。'
                '手机竖屏、平板横屏、桌面端三种布局断点。'
                '测试至少 3 种分辨率：360dp / 768dp / 1920dp。',
            reference: 'flutter.dev/docs/development/ui/layout/adaptive-responsive',
          ),
          _CheckItem(
            title: '暗色主题支持',
            tip: '本项目已通过 ThemeManager 支持亮/暗切换。'
                '确保所有自定义颜色在暗色模式下可读，'
                '避免硬编码 Colors.white/Colors.black。'
                '使用 Theme.of(context).colorScheme 获取语义化颜色。',
            reference: '本项目：lib/services/theme_manager.dart',
          ),
          _CheckItem(
            title: '操作反馈（Toast/SnackBar）',
            tip: '每个用户操作都应有即时反馈：'
                '成功 → 绿色 SnackBar；失败 → 红色 SnackBar；'
                '加载中 → Loading 指示器；确认 → Dialog。'
                '避免静默操作让用户不确定是否生效。',
            reference: 'Material Design: Snackbar 规范',
          ),
          _CheckItem(
            title: '手势操作支持',
            tip: '为常用操作添加手势快捷方式：'
                '下拉刷新（RefreshIndicator）、'
                '左右滑动删除（Dismissible）、'
                '双指缩放（InteractiveViewer）。'
                '确保手势不与系统手势冲突。',
            reference: '本项目图谱页已使用 InteractiveViewer',
          ),
        ],
      ),

      // ── 5. 安全与隐私 ───────────────────────────────────────────────────
      _CheckCategory(
        title: '安全与隐私',
        icon: Icons.security,
        color: const Color(0xFFFF6D00),
        items: [
          _CheckItem(
            title: '输入校验与防注入',
            tip: '对所有用户输入进行合法性校验：'
                '长度限制、特殊字符过滤、类型检查。'
                'SQL 操作必须使用参数化查询（?占位符），'
                '禁止字符串拼接 SQL 语句。',
            reference: 'sqflite 参数化查询：db.query(table, where: "id = ?", whereArgs: [id])',
          ),
          _CheckItem(
            title: '敏感数据加密存储',
            tip: '密码、Token 等敏感数据不能明文存储。'
                '使用 flutter_secure_storage 替代 SharedPreferences '
                '存储敏感信息。API Key 不要硬编码在源码中。',
            reference: 'pub.dev: flutter_secure_storage',
          ),
          _CheckItem(
            title: '网络通信使用 HTTPS',
            tip: '所有网络请求必须使用 HTTPS 协议。'
                '在 Android 的 network_security_config.xml 中'
                '禁止明文流量（cleartextTrafficPermitted=false）。'
                'iOS 确保 ATS（App Transport Security）开启。',
            reference: 'Android: res/xml/network_security_config.xml',
          ),
          _CheckItem(
            title: '添加隐私政策声明',
            tip: '应用内添加隐私政策页面，说明：'
                '收集哪些数据、如何使用、如何保护、用户权利。'
                '上架应用商店必须提供隐私政策 URL。'
                '遵循《个人信息保护法》要求。',
            reference: '模板参考：App Privacy Policy Generator',
          ),
          _CheckItem(
            title: '权限最小化申请',
            tip: '只申请应用必需的系统权限，用时才申请（runtime permission）。'
                '检查 AndroidManifest.xml 和 Info.plist，'
                '删除不必要的权限声明。'
                '向用户说明每个权限的使用目的。',
            reference: 'pub.dev: permission_handler',
          ),
        ],
      ),

      // ── 6. 发布准备 ─────────────────────────────────────────────────────
      _CheckCategory(
        title: '发布准备',
        icon: Icons.publish,
        color: const Color(0xFF43A047),
        items: [
          _CheckItem(
            title: '应用图标与启动图',
            tip: '设计 1024x1024 的应用图标原图，'
                '使用 flutter_launcher_icons 自动生成各尺寸。'
                '图标应简洁、辨识度高，在小尺寸下清晰可辨。'
                '启动图与品牌色保持一致。',
            reference: 'pub.dev: flutter_launcher_icons',
          ),
          _CheckItem(
            title: '应用签名配置',
            tip: 'Android: 生成 keystore 文件，配置 key.properties 和 '
                'build.gradle 签名信息。'
                'iOS: 配置 Apple Developer 证书和 Provisioning Profile。'
                '签名文件妥善保管，不要提交到 Git 仓库！',
            reference: 'flutter.dev/docs/deployment/android',
          ),
          _CheckItem(
            title: '版本号管理',
            tip: '遵循语义化版本号：MAJOR.MINOR.PATCH+BUILD。'
                '在 pubspec.yaml 中更新 version 字段。'
                '每次发布递增 build number，'
                '维护 CHANGELOG.md 记录版本变更。',
            reference: '当前版本：pubspec.yaml → version: 1.0.0+1',
          ),
          _CheckItem(
            title: '发布说明编写',
            tip: '为每个版本编写面向用户的更新日志：'
                '新功能、改进、修复的 Bug。'
                '语言简洁易懂，避免技术术语。'
                '附带截图展示重要的新功能。',
            reference: '格式参考：Keep a Changelog (keepachangelog.com)',
          ),
          _CheckItem(
            title: '应用商店截图准备',
            tip: '准备 5-8 张应用核心页面截图。'
                '推荐分辨率：1242x2688（iPhone）/ 1080x1920（Android）。'
                '可添加文字说明、品牌元素，突出核心卖点。'
                '录制 15-30 秒功能预览视频更佳。',
            reference: '推荐工具：Screenshot Framer、AppMockUp',
          ),
        ],
      ),

      // ── 7. 文档与演示 ───────────────────────────────────────────────────
      _CheckCategory(
        title: '文档与演示',
        icon: Icons.description,
        color: const Color(0xFF5C6BC0),
        items: [
          _CheckItem(
            title: 'README.md 编写',
            tip: '包含以下部分：项目简介、功能截图、技术栈、'
                '项目结构、环境搭建步骤、运行方法、'
                '贡献指南、许可证。'
                '使用 Badge 展示构建状态、测试覆盖率等。',
            reference: '模板参考：github.com/othneildrew/Best-README-Template',
          ),
          _CheckItem(
            title: 'API 文档（如有后端）',
            tip: '使用 Swagger/OpenAPI 规范编写 API 文档。'
                '包含请求方法、URL、参数、响应体、错误码。'
                '提供在线可交互文档（Swagger UI）便于测试。',
            reference: '工具推荐：Apifox、Swagger Editor',
          ),
          _CheckItem(
            title: '用户手册',
            tip: '编写面向终端用户的操作指南，'
                '以截图 + 步骤说明的形式呈现。'
                '覆盖所有核心功能的操作流程，'
                '包含常见问题解答（FAQ）。',
            reference: '格式：Markdown / PDF / 应用内帮助页',
          ),
          _CheckItem(
            title: '演示视频录制',
            tip: '录制 3-5 分钟的功能演示视频，'
                '展示完整的用户使用流程。'
                '添加旁白解说和字幕，'
                '使用专业录屏工具确保画质清晰。',
            reference: '工具推荐：OBS Studio、Bandicam、scrcpy（Android 投屏）',
          ),
          _CheckItem(
            title: '答辩 PPT 制作',
            tip: '包含以下章节：项目背景与动机、需求分析、'
                '技术架构、核心功能演示、测试结果、'
                '总结与展望。控制在 15-20 页，'
                '每页一个核心观点，配图多于文字。',
            reference: '本项目视频脚本：docs/video/',
          ),
        ],
      ),
    ];
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 数据模型
// ══════════════════════════════════════════════════════════════════════════════

/// 检查分类
class _CheckCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<_CheckItem> items;

  _CheckCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  int get checkedCount => items.where((i) => i.isChecked).length;
}

/// 单个检查项
class _CheckItem {
  final String title;
  final String tip;
  final String reference;
  bool isChecked = false;

  _CheckItem({
    required this.title,
    required this.tip,
    this.reference = '',
  });
}
