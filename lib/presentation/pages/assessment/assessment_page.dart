import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';

/// 考核页面 — 参考 Python 版 assessment_tab.py
/// 五大子页: 分组管理 / 项目立项 / 贡献评分 / 答辩安排 / 成绩统计
class AssessmentPage extends StatefulWidget {
  const AssessmentPage({super.key});

  @override
  State<AssessmentPage> createState() => _AssessmentPageState();
}

class _AssessmentPageState extends State<AssessmentPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // Tab 栏
        Container(
          color: primary.withValues(alpha: 0.05),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primary,
            tabs: const [
              Tab(icon: Icon(Icons.groups, size: 18), text: '分组'),
              Tab(icon: Icon(Icons.assignment, size: 18), text: '项目'),
              Tab(icon: Icon(Icons.star_rate, size: 18), text: '贡献'),
              Tab(icon: Icon(Icons.record_voice_over, size: 18), text: '答辩'),
              Tab(icon: Icon(Icons.leaderboard, size: 18), text: '成绩'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GroupTab(authService: _authService),
              _ProjectTab(authService: _authService),
              _ContributionTab(authService: _authService),
              _DefenseTab(authService: _authService),
              _ScoreTab(authService: _authService),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 分组管理 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _GroupTab extends StatefulWidget {
  final AuthService authService;
  const _GroupTab({required this.authService});

  @override
  State<_GroupTab> createState() => _GroupTabState();
}

class _GroupTabState extends State<_GroupTab> {
  // 模拟数据
  final List<Map<String, dynamic>> _groups = [
    {
      'name': '第1组',
      'leader': '张三',
      'members': ['张三', '李四', '王五', '赵六', '孙七', '周八'],
      'project': '智慧校园生活服务平台',
    },
    {
      'name': '第2组',
      'leader': '陈九',
      'members': ['陈九', '吴十', '郑一', '钱二', '冯三', '褚四'],
      'project': '在线学习辅助平台',
    },
    {
      'name': '第3组',
      'leader': '卫五',
      'members': ['卫五', '蒋六', '沈七', '韩八', '杨九', '朱十'],
      'project': '智能健康运动记录平台',
    },
    {
      'name': '第4组',
      'leader': '秦一',
      'members': ['秦一', '许二', '何三', '吕四', '施五', '张六'],
      'project': '二手物品交易平台',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 统计卡片
        _buildStatsRow(),
        const SizedBox(height: 16),
        // 分组列表
        ..._groups.map((g) => _buildGroupCard(g)),
      ],
    );
  }

  Widget _buildStatsRow() {
    final totalMembers = _groups.fold<int>(
        0, (sum, g) => sum + (g['members'] as List).length);
    return Row(
      children: [
        _statCard('小组数', '${_groups.length}', Icons.groups, Colors.blue),
        const SizedBox(width: 10),
        _statCard('总人数', '$totalMembers', Icons.people, Colors.green),
        const SizedBox(width: 10),
        _statCard('人均', '${(totalMembers / _groups.length).toStringAsFixed(1)}',
            Icons.person, Colors.orange),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final members = group['members'] as List;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withValues(alpha: 0.1),
          child: Text(group['name'].toString().replaceAll('第', '').replaceAll('组', ''),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.blue)),
        ),
        title: Text(group['name'],
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '组长: ${group['leader']} · ${members.length}人 · ${group['project']}',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('组员列表',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: members
                      .map((m) => Chip(
                            avatar: CircleAvatar(
                              backgroundColor: m == group['leader']
                                  ? Colors.orange
                                  : Colors.grey[300],
                              radius: 12,
                              child: Text(m.toString().substring(0, 1),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: m == group['leader']
                                          ? Colors.white
                                          : Colors.black87)),
                            ),
                            label: Text(m.toString(),
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Text('项目: ${group['project']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 项目立项 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ProjectTab extends StatelessWidget {
  final AuthService authService;
  const _ProjectTab({required this.authService});

  static const _projects = [
    {
      'name': '智慧校园生活服务平台',
      'group': '第1组',
      'status': '开发中',
      'progress': 0.65,
      'tech': 'Flutter + Android 原生 + UniApp',
      'desc': '面向高校师生的跨平台校园服务，整合课表、场馆预约、校园导航等功能',
    },
    {
      'name': '在线学习辅助平台',
      'group': '第2组',
      'status': '开发中',
      'progress': 0.50,
      'tech': 'Flutter + React Native + 小程序',
      'desc': '提供在线学习、笔记管理、学习计划和协作讨论功能',
    },
    {
      'name': '智能健康运动记录平台',
      'group': '第3组',
      'status': '设计阶段',
      'progress': 0.30,
      'tech': 'Flutter + HarmonyOS + iOS',
      'desc': '记录运动轨迹、健康数据分析、社交分享健身成果',
    },
    {
      'name': '二手物品交易平台',
      'group': '第4组',
      'status': '测试阶段',
      'progress': 0.80,
      'tech': 'Flutter + 小程序 + Android',
      'desc': '校园二手商品发布、搜索、即时聊天、交易管理',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _projects.length,
      itemBuilder: (ctx, i) => _buildProjectCard(context, _projects[i]),
    );
  }

  Widget _buildProjectCard(BuildContext context, Map<String, dynamic> project) {
    final progress = (project['progress'] as double);
    final statusColor = switch (project['status']) {
      '测试阶段' => Colors.orange,
      '开发中' => Colors.blue,
      '设计阶段' => Colors.purple,
      '已完成' => Colors.green,
      _ => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(project['name'] as String,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(project['status'] as String,
                      style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(project['desc'] as String,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.group, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(project['group'] as String,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(width: 12),
                Icon(Icons.code, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(project['tech'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis),
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
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(statusColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${(progress * 100).toInt()}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 贡献评分 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ContributionTab extends StatelessWidget {
  final AuthService authService;
  const _ContributionTab({required this.authService});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    // 评分维度
    const dimensions = [
      {'name': '功能完整性', 'max': 25, 'icon': Icons.check_circle},
      {'name': '技术实现深度', 'max': 20, 'icon': Icons.code},
      {'name': '跨框架整合', 'max': 25, 'icon': Icons.integration_instructions},
      {'name': '性能与质量', 'max': 15, 'icon': Icons.speed},
      {'name': '文档与协作', 'max': 15, 'icon': Icons.description},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 评分标准说明
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [primary.withValues(alpha: 0.08), primary.withValues(alpha: 0.02)],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.rule, color: primary, size: 20),
                    const SizedBox(width: 8),
                    Text('综合评分体系（100分）',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: primary)),
                  ],
                ),
                const SizedBox(height: 12),
                ...dimensions.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(d['icon'] as IconData,
                              size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(d['name'] as String,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${d['max']}分',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: primary,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 课程总评构成
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('课程总评成绩构成',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _scoreComponent('理论考核', 40, Colors.blue, [
                  '平时成绩 15%（课堂5%+作业5%+小测5%）',
                  '期末考试 25%（选择8%+简答10%+综合7%）',
                ]),
                _scoreComponent('实验考核', 35, Colors.green, [
                  '实验1-6 各5%（环境/Android/Flutter/UniApp/小程序/华为）',
                  '实验7 综合实战 5%',
                ]),
                _scoreComponent('综合项目', 25, Colors.orange, [
                  '项目设计 8%',
                  '技术实现 10%',
                  '团队协作 4%',
                  '项目答辩 3%',
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreComponent(
      String title, int percent, Color color, List<String> details) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('$title ($percent%)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: color)),
            ],
          ),
          ...details.map((d) => Padding(
                padding: const EdgeInsets.only(left: 22, top: 3),
                child: Text(d,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              )),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 答辩安排 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _DefenseTab extends StatelessWidget {
  final AuthService authService;
  const _DefenseTab({required this.authService});

  @override
  Widget build(BuildContext context) {
    final defenseGroups = [
      {
        'group': '第1组',
        'project': '智慧校园生活服务平台',
        'time': '第16周 周一 9:00-9:15',
        'location': '实验楼A301',
        'status': '待答辩',
      },
      {
        'group': '第2组',
        'project': '在线学习辅助平台',
        'time': '第16周 周一 9:15-9:30',
        'location': '实验楼A301',
        'status': '待答辩',
      },
      {
        'group': '第3组',
        'project': '智能健康运动记录平台',
        'time': '第16周 周一 9:30-9:45',
        'location': '实验楼A301',
        'status': '待答辩',
      },
      {
        'group': '第4组',
        'project': '二手物品交易平台',
        'time': '第16周 周一 9:45-10:00',
        'location': '实验楼A301',
        'status': '待答辩',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 答辩流程说明
        Card(
          color: Colors.amber.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber[800], size: 18),
                    const SizedBox(width: 8),
                    Text('答辩流程（15分钟/组）',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[800])),
                  ],
                ),
                const SizedBox(height: 8),
                _flowStep('1', '项目演示', '5分钟', Colors.blue),
                _flowStep('2', '技术讲解', '5分钟', Colors.green),
                _flowStep('3', '评委提问', '3分钟', Colors.orange),
                _flowStep('4', '评分记录', '2分钟', Colors.purple),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('答辩安排',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...defenseGroups
            .map((d) => _buildDefenseCard(context, d)),
      ],
    );
  }

  Widget _flowStep(String num, String title, String time, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          CircleAvatar(
              radius: 12,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Text(num,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: color))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(time, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildDefenseCard(BuildContext context, Map<String, dynamic> defense) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.withValues(alpha: 0.1),
          child: const Icon(Icons.record_voice_over,
              color: Colors.indigo, size: 20),
        ),
        title: Text('${defense['group']}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(defense['project'] as String,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.schedule, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(defense['time'] as String,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(width: 8),
                Icon(Icons.location_on, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(defense['location'] as String,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(defense['status'] as String,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber[800],
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 成绩统计 Tab
// ══════════════════════════════════════════════════════════════════════════════

class _ScoreTab extends StatelessWidget {
  final AuthService authService;
  const _ScoreTab({required this.authService});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final scores = [
      {'group': '第4组', 'project': '二手物品交易平台', 'score': 92, 'rank': 1},
      {'group': '第1组', 'project': '智慧校园生活服务平台', 'score': 88, 'rank': 2},
      {'group': '第2组', 'project': '在线学习辅助平台', 'score': 85, 'rank': 3},
      {'group': '第3组', 'project': '智能健康运动记录平台', 'score': 78, 'rank': 4},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 统计概览
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.7)],
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _overviewItem('平均分', '85.8', Icons.analytics),
                Container(width: 1, height: 40, color: Colors.white30),
                _overviewItem('最高分', '92', Icons.emoji_events),
                Container(width: 1, height: 40, color: Colors.white30),
                _overviewItem('及格率', '100%', Icons.check_circle),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 排行榜
        const Text('成绩排行',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...scores.map((s) => _buildScoreCard(context, s)),

        const SizedBox(height: 16),

        // 成绩明细说明
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('评分维度明细',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                _dimensionBar('功能完整性', 22, 25, Colors.blue),
                _dimensionBar('技术实现深度', 17, 20, Colors.green),
                _dimensionBar('跨框架整合', 21, 25, Colors.purple),
                _dimensionBar('性能与质量', 12, 15, Colors.orange),
                _dimensionBar('文档与协作', 13, 15, Colors.teal),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _overviewItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _buildScoreCard(BuildContext context, Map<String, dynamic> score) {
    final rank = score['rank'] as int;
    final rankColor = rank == 1
        ? Colors.amber
        : rank == 2
            ? Colors.grey.shade400
            : rank == 3
                ? Colors.brown.shade300
                : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor.withValues(alpha: 0.15),
          child: Text('#$rank',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: rankColor, fontSize: 14)),
        ),
        title: Text(score['group'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(score['project'] as String,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        trailing: Text('${score['score']}',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: (score['score'] as int) >= 90
                    ? Colors.green
                    : (score['score'] as int) >= 80
                        ? Colors.blue
                        : Colors.orange)),
      ),
    );
  }

  Widget _dimensionBar(String name, int score, int max, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(name, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / max,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$score/$max',
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
