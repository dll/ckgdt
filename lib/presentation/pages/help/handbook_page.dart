import 'package:flutter/material.dart';

/// 用户手册页面 — 根据角色显示对应的操作指南
/// 支持：学生手册 / 教师手册 / 管理员手册
class HandbookPage extends StatelessWidget {
  final String role; // 'student' / 'teacher' / 'admin'

  const HandbookPage({super.key, required this.role});

  String get _title {
    switch (role) {
      case 'admin':
        return '管理员手册';
      case 'teacher':
        return '教师手册';
      default:
        return '学生手册';
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '关于本手册',
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 欢迎横幅
          _buildWelcomeBanner(context, primary, isDark),
          const SizedBox(height: 20),
          // 根据角色生成章节
          ..._buildSections(context, primary, isDark),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // 欢迎横幅
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildWelcomeBanner(BuildContext context, Color primary, bool isDark) {
    final bannerColor = role == 'admin'
        ? Colors.deepPurple
        : role == 'teacher'
            ? Colors.indigo
            : primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bannerColor, bannerColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            role == 'admin'
                ? Icons.admin_panel_settings
                : role == 'teacher'
                    ? Icons.school
                    : Icons.menu_book,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  role == 'admin'
                      ? '系统管理与数据维护操作指南'
                      : role == 'teacher'
                          ? '教学管理与课程评价操作指南'
                          : '从入门到精通的学习全流程指南',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // 根据角色生成章节
  // ══════════════════════════════════════════════════════════════════════

  List<Widget> _buildSections(BuildContext context, Color primary, bool isDark) {
    switch (role) {
      case 'admin':
        return _adminSections(primary, isDark);
      case 'teacher':
        return _teacherSections(primary, isDark);
      default:
        return _studentSections(primary, isDark);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // 学生手册
  // ──────────────────────────────────────────────────────────────────────

  List<Widget> _studentSections(Color primary, bool isDark) {
    return [
      _section(
        icon: Icons.login,
        color: Colors.blue,
        title: '一、登录系统',
        isDark: isDark,
        steps: const [
          _Step('打开应用', '启动知识图谱教学系统，进入登录页面'),
          _Step('输入学号', '在用户名输入框输入你的学号（如 2201001）'),
          _Step('输入密码', '密码为学号后6位（如学号 2201001，密码为 201001）'),
          _Step('点击登录', '验证成功后进入系统首页'),
        ],
        tips: const ['首次使用请确认学号已录入系统', '如无法登录请联系管理员'],
      ),

      _section(
        icon: Icons.home,
        color: Colors.teal,
        title: '二、首页导航',
        isDark: isDark,
        steps: const [
          _Step('底部导航栏', '共有多个功能Tab，左右滑动或点击切换'),
          _Step('功能卡片', '首页展示功能菜单卡片，点击可快速跳转'),
          _Step('个人菜单', '右上角头像图标 → 学习中心 / 学习进度 / 设置'),
          _Step('搜索功能', '右上角搜索图标 → 全局搜索知识点'),
        ],
      ),

      _section(
        icon: Icons.account_tree,
        color: Colors.green,
        title: '三、知识图谱',
        isDark: isDark,
        steps: const [
          _Step('浏览图谱列表', '点击「知识图谱」Tab 查看所有章节图谱'),
          _Step('查看图谱详情', '点击某个图谱进入交互式详情页'),
          _Step('操作图谱', '双指缩放/拖拽平移，点击节点查看详情'),
          _Step('学习节点', '点击节点详情中的「开始学习」记录学习进度'),
          _Step('收藏节点', '点击「收藏」按钮将重要节点加入收藏夹'),
        ],
        tips: const ['节点颜色越深表示内容越核心', '收藏的节点可在收藏页面统一查看'],
      ),

      _section(
        icon: Icons.route,
        color: Colors.orange,
        title: '四、学习路径',
        isDark: isDark,
        steps: const [
          _Step('查看学习计划', '点击「学习计划」Tab 查看推荐的学习路径'),
          _Step('了解章节安排', '每个计划展示章节列表和完成进度'),
          _Step('跟踪进度', '已完成的章节显示绿色对勾'),
        ],
      ),

      _section(
        icon: Icons.quiz,
        color: Colors.purple,
        title: '五、章节测验',
        isDark: isDark,
        steps: const [
          _Step('选择章节', '点击「章节测验」Tab，选择要测试的章节'),
          _Step('开始答题', '系统随机出题，点击选项选择答案'),
          _Step('提交判定', '选择后点击提交，系统即时判定对错'),
          _Step('查看解析', '答错的题目显示正确答案和红色标记'),
          _Step('错题本', '答错的题目自动加入错题本，可随时复习'),
        ],
        tips: const [
          '绿色 = 正确，红色 = 错误',
          '错题本中显示错误次数，重点复习高频错题',
          '可通过顶部清空按钮重置错题本',
        ],
      ),

      _section(
        icon: Icons.science,
        color: Colors.teal,
        title: '六、实验管理',
        isDark: isDark,
        steps: const [
          _Step('查看实验任务', '点击「实验」Tab 查看 6 个实验任务'),
          _Step('了解要求', '每个实验显示详细要求、截止日期'),
          _Step('提交实验', '将代码推送到 Gitee 仓库对应分支'),
          _Step('提交报告', '实验报告放在 docs/reports/ 目录下'),
          _Step('查看评分', '教师批改后可查看实验成绩和评语'),
        ],
        tips: const [
          '实验报告命名: 实验X_姓名.md',
          '代码提交到自己的 feat-xxx 分支',
          '注意截止日期，过期可能无法提交',
        ],
      ),

      _section(
        icon: Icons.source,
        color: Colors.blueGrey,
        title: '七、Git 仓库规范',
        isDark: isDark,
        steps: const [
          _Step('仓库命名', '小组仓库格式: cg{组号}-{项目简称}，如 cg1-sclspdi'),
          _Step('分支命名', '个人分支格式: feat-{姓名拼音首字母小写}，如 feat-cjn'),
          _Step('字母要求', '分支名必须 2~5 个全小写字母，不含中文'),
          _Step('提交消息', '格式: <类型>: <描述>，如 feat: 完成实验一'),
          _Step('克隆仓库',
              'git clone https://gitee.com/chzuczldl/cg1-xxx.git'),
          _Step('创建分支',
              'git checkout -b feat-xxx && git push -u origin feat-xxx'),
        ],
        tips: const [
          '⚠️ 不符合规范的仓库和分支将不被系统识别',
          '分支名错误示例: feat-CJN(大写), feat-陈(中文), feature-cjn(前缀错)',
          '更多规范请查看「仓库」Tab → 提交规范',
        ],
      ),

      _section(
        icon: Icons.assignment,
        color: Colors.orange,
        title: '八、课程考核',
        isDark: isDark,
        steps: const [
          _Step('了解评分体系', '平时30% + 实验30% + 期末考核40%'),
          _Step('综合项目', '6人一组完成综合项目，推送到小组仓库'),
          _Step('项目答辩', '答辩材料放在 docs/defense/ 目录下'),
          _Step('团队协作', 'Git 提交记录作为协作评分依据'),
        ],
      ),

      _section(
        icon: Icons.palette,
        color: Colors.indigo,
        title: '九、作品展示',
        isDark: isDark,
        steps: const [
          _Step('提交作品', '将作品推送到 works/ 目录'),
          _Step('编写说明', '必须包含 README.md（作品名称/截图/技术栈）'),
          _Step('添加截图', '截图放在 works/assets/ 目录下'),
          _Step('查看展示', '在「作品」Tab 查看全班作品展示'),
        ],
      ),

      _section(
        icon: Icons.video_library,
        color: Colors.red,
        title: '十、学习资源',
        isDark: isDark,
        steps: const [
          _Step('视频教程', '点击「视频教程」Tab 观看章节教学视频'),
          _Step('课程资料', '点击「课程资料」Tab 查看 PDF/PPT 课件'),
          _Step('切换标签', 'PDF 文档和 PPT 课件通过顶部 Tab 切换'),
        ],
      ),

      _section(
        icon: Icons.trending_up,
        color: Colors.green,
        title: '十一、学习进度',
        isDark: isDark,
        steps: const [
          _Step('查看成绩', '「学习进度」→ 测验成绩 Tab 查看历次成绩'),
          _Step('成绩趋势', '折线图展示成绩变化趋势'),
          _Step('学习记录', '「学习记录」Tab 查看已学习节点统计'),
        ],
      ),
    ];
  }

  // ──────────────────────────────────────────────────────────────────────
  // 教师手册
  // ──────────────────────────────────────────────────────────────────────

  List<Widget> _teacherSections(Color primary, bool isDark) {
    return [
      _section(
        icon: Icons.login,
        color: Colors.blue,
        title: '一、登录与身份',
        isDark: isDark,
        steps: const [
          _Step('教师登录', '使用教师工号登录，密码为工号后6位'),
          _Step('身份标识', '登录后右上角显示「教师」角色标识'),
          _Step('教师工作台', '右上角头像 → 教师工作台，可集中管理'),
        ],
      ),

      _section(
        icon: Icons.account_tree,
        color: Colors.green,
        title: '二、知识图谱管理',
        isDark: isDark,
        steps: const [
          _Step('浏览图谱', '与学生相同，浏览所有章节知识图谱'),
          _Step('查看节点', '点击节点查看详细知识点内容'),
          _Step('图谱数据', '图谱数据来源于 Markdown 文件自动导入'),
        ],
      ),

      _section(
        icon: Icons.science,
        color: Colors.teal,
        title: '三、实验任务管理',
        isDark: isDark,
        steps: const [
          _Step('查看任务列表', '「实验」Tab → 教师额外显示「任务管理」子Tab'),
          _Step('管理实验任务', '可新增/编辑/删除实验任务定义'),
          _Step('查看学生提交', '查看各实验的学生提交情况和状态'),
          _Step('批改评分', '对学生提交的实验进行评分和反馈'),
          _Step('统计分析', '查看实验完成率、平均分等统计数据'),
        ],
        tips: const [
          '实验任务定义同步到 Gitee 仓库 mad-fd',
          '学生代码通过 Gitee 分支查看',
        ],
      ),

      _section(
        icon: Icons.source,
        color: Colors.blueGrey,
        title: '四、仓库监控',
        isDark: isDark,
        steps: const [
          _Step('查看仓库列表', '「仓库」Tab → 查看所有 cg 前缀学生仓库'),
          _Step('查看学生详情', '选择仓库 → 「学生详情」Tab 查看分支和提交'),
          _Step('提交分析', '查看每个学生的提交频率、代码量'),
          _Step('规范检查', '系统自动过滤不符合规范的仓库和分支'),
        ],
        tips: const [
          '仓库规范: cg{组号}-{项目简称}',
          '分支规范: feat-{姓名拼音首字母小写}',
          '「提交规范」Tab 可展示给学生参考',
        ],
      ),

      _section(
        icon: Icons.assignment,
        color: Colors.orange,
        title: '五、课程考核管理',
        isDark: isDark,
        steps: const [
          _Step('分组管理', '「考核」Tab → 分组管理 → 创建/编辑项目分组'),
          _Step('项目立项', '审核学生的项目选题和立项申请'),
          _Step('贡献评分', '根据 Git 提交记录评定团队贡献分'),
          _Step('答辩安排', '设置答辩时间、地点、评审老师'),
          _Step('成绩统计', '自动汇总各项成绩，导出统计报表'),
        ],
      ),

      _section(
        icon: Icons.emoji_events,
        color: Colors.amber,
        title: '六、课程达成度',
        isDark: isDark,
        steps: const [
          _Step('创建批次', '「达成」Tab → 创建达成度计算批次'),
          _Step('录入成绩', '手动录入或从测验成绩自动计算'),
          _Step('计算达成度', '一键计算 4 个课程目标的达成度'),
          _Step('生成报告', '生成 Markdown 格式的达成度报告'),
          _Step('导出结果', '复制报告到剪贴板或导出文件'),
        ],
        tips: const [
          '课程目标权重: 15% + 25% + 30% + 30%',
          '达成度 ≥ 90% 优秀, ≥ 70% 良好, ≥ 60% 中等',
        ],
      ),

      _section(
        icon: Icons.quiz,
        color: Colors.purple,
        title: '七、测验与题库',
        isDark: isDark,
        steps: const [
          _Step('浏览题库', '「章节测验」Tab 查看各章节题目'),
          _Step('学生成绩', '通过「学习进度」查看学生的测验成绩'),
          _Step('错题分析', '错题本统计帮助了解学生薄弱环节'),
        ],
      ),

      _section(
        icon: Icons.video_library,
        color: Colors.red,
        title: '八、教学资源',
        isDark: isDark,
        steps: const [
          _Step('视频教程', '15 个章节教学视频，可在课堂播放'),
          _Step('课件管理', 'PDF/PPT 课件按章节组织'),
          _Step('素材中心', 'AI 辅助生成课件/脚本/UML 图'),
        ],
      ),

      _section(
        icon: Icons.settings,
        color: Colors.grey,
        title: '九、系统设置',
        isDark: isDark,
        steps: const [
          _Step('Gitee 配置', '「仓库」→ Gitee设置 → 配置访问令牌'),
          _Step('数据同步', '系统启动时自动同步远程课程配置'),
          _Step('清除缓存', '「Gitee设置」→ 清除缓存按钮刷新数据'),
          _Step('主题切换', '设置页面可切换亮色/暗色主题'),
        ],
      ),
    ];
  }

  // ──────────────────────────────────────────────────────────────────────
  // 管理员手册
  // ──────────────────────────────────────────────────────────────────────

  List<Widget> _adminSections(Color primary, bool isDark) {
    return [
      _section(
        icon: Icons.login,
        color: Colors.blue,
        title: '一、管理员登录',
        isDark: isDark,
        steps: const [
          _Step('默认账号', '管理员账号 419116，密码 419116'),
          _Step('管理面板', '底部导航栏最右侧显示「管理」Tab'),
          _Step('完整权限', '管理员拥有教师的全部权限 + 系统管理权限'),
        ],
      ),

      // 包含教师的所有章节
      ..._teacherSections(primary, isDark),

      _section(
        icon: Icons.people,
        color: Colors.blue,
        title: '十、学生管理',
        isDark: isDark,
        steps: const [
          _Step('查看学生列表', '「管理」Tab → 学生管理 → 查看所有注册学生'),
          _Step('导入学生', '从 JSON 文件批量导入学生信息'),
          _Step('管理状态', '启用/禁用学生账号'),
          _Step('重置密码', '学生密码固定为学号后6位，无法自定义'),
        ],
        tips: const ['默认密码规则不可更改，所有用户统一使用学号后6位'],
      ),

      _section(
        icon: Icons.storage,
        color: Colors.green,
        title: '十一、数据管理',
        isDark: isDark,
        steps: const [
          _Step('数据备份', '「管理」→ 数据管理 → 导出 JSON 数据备份'),
          _Step('数据导入', '从 JSON 文件恢复/导入数据'),
          _Step('数据库维护', '系统启动时自动清理空图谱和旧数据'),
          _Step('达成度数据', '可导出达成度数据供教务使用'),
        ],
      ),

      _section(
        icon: Icons.cloud_sync,
        color: Colors.orange,
        title: '十二、远程资源管理',
        isDark: isDark,
        steps: const [
          _Step('Gitee 令牌', '「仓库」→ Gitee设置 → 配置/更换访问令牌'),
          _Step('资源同步', '系统启动时自动从 mad-fd 仓库同步课程配置'),
          _Step('配置管理', 'data/course_config/ 目录下的 JSON 文件'),
          _Step('缓存管理', '一键清除本地缓存，强制重新同步'),
        ],
        tips: const [
          '令牌泄露时需立即在 Gitee 网站撤销并重新生成',
          'mad-fd 仓库存储: 实验定义/章节/考核方案/报告模板',
        ],
      ),

      _section(
        icon: Icons.analytics,
        color: Colors.purple,
        title: '十三、仓库分析',
        isDark: isDark,
        steps: const [
          _Step('仓库统计', '「管理」→ 仓库分析 → 查看所有仓库提交统计'),
          _Step('学生活跃度', '分析各学生的提交频率和代码量'),
          _Step('趋势分析', '查看提交量随时间的变化趋势'),
          _Step('导出报告', '统计数据可导出用于考核参考'),
        ],
      ),

      _section(
        icon: Icons.security,
        color: Colors.red,
        title: '十四、安全注意事项',
        isDark: isDark,
        steps: const [
          _Step('令牌安全', 'Gitee 令牌不要分享给学生或公开'),
          _Step('数据备份', '定期通过「数据管理」导出备份'),
          _Step('密码规则', '用户密码固定为学号后6位，这是系统设计'),
          _Step('数据库文件', '不要手动修改 assets/learning_data.db'),
        ],
      ),
    ];
  }

  // ══════════════════════════════════════════════════════════════════════
  // 通用组件
  // ══════════════════════════════════════════════════════════════════════

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required bool isDark,
    required List<_Step> steps,
    List<String>? tips,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 步骤列表
              ...steps.asMap().entries.map((entry) {
                final idx = entry.key;
                final step = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${idx + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: color)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(step.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(step.desc,
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // 提示
              if (tips != null && tips.isNotEmpty) ...[
                const Divider(height: 20),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 16, color: Colors.amber[700]),
                          const SizedBox(width: 6),
                          Text('提示',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[700])),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...tips.map((tip) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text('• $tip',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于本手册'),
        content: const Text(
          '本手册提供系统各功能的操作指引。\n\n'
          '• 学生手册：学习全流程指南\n'
          '• 教师手册：教学管理与评价指南\n'
          '• 管理员手册：系统管理与数据维护指南\n\n'
          '手册内容会随系统更新自动同步。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }
}

/// 操作步骤数据类
class _Step {
  final String title;
  final String desc;
  const _Step(this.title, this.desc);
}
