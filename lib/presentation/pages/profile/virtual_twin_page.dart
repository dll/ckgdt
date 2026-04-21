import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/agent/agent_registry.dart';
import '../../widgets/agent_chat_overlay.dart';

/// 数字孪生仪表盘页面 — 教师/学生共用
///
/// 教师端显示"虚拟教师"仪表盘（教学进度/班级学情/图谱覆盖/教学反思/下节课建议/待批任务）
/// 学生端显示"虚拟学生"仪表盘（学习状态/知识图谱健康度/能力雷达/成长曲线/下一步/学习风格）
class VirtualTwinPage extends StatefulWidget {
  const VirtualTwinPage({super.key});

  @override
  State<VirtualTwinPage> createState() => _VirtualTwinPageState();
}

class _VirtualTwinPageState extends State<VirtualTwinPage> {
  final _authService = AuthService();
  final _registry = AgentRegistry.instance;
  String? _activeQuery;
  String _reply = '';
  bool _isLoading = false;

  bool get _isTeacher => _authService.isTeacher || _authService.isAdmin;
  String get _agentId => _isTeacher ? 'virtual_teacher' : 'virtual_student';
  String get _title => _isTeacher ? '虚拟教师' : '虚拟学生';
  String get _emoji => _isTeacher ? '👩‍🏫' : '🧑‍🎓';
  String get _subtitle => _isTeacher
      ? '教学数字孪生 — 映射教学进度与班级学情'
      : '学习数字孪生 — 映射知识掌握与成长动态';

  List<_QuickAction> get _actions => _isTeacher
      ? [
          _QuickAction('教学仪表盘', Icons.dashboard, Colors.blue, '教学仪表盘'),
          _QuickAction('班级学情分析', Icons.people, Colors.green, '班级学情分析'),
          _QuickAction('图谱覆盖度', Icons.account_tree, Colors.orange, '图谱覆盖度'),
          _QuickAction('教学反思', Icons.psychology, Colors.purple, '教学反思'),
          _QuickAction('下节课建议', Icons.lightbulb, Colors.amber, '下节课建议'),
          _QuickAction('待批任务', Icons.assignment, Colors.red, '待批任务'),
        ]
      : [
          _QuickAction('查看我的状态', Icons.dashboard, Colors.blue, '查看我的状态'),
          _QuickAction('知识图谱健康度', Icons.account_tree, Colors.green, '知识图谱健康度'),
          _QuickAction('能力雷达分析', Icons.radar, Colors.orange, '能力雷达分析'),
          _QuickAction('成长曲线', Icons.show_chart, Colors.purple, '成长曲线'),
          _QuickAction('下一步学什么', Icons.lightbulb, Colors.amber, '下一步学什么'),
          _QuickAction('学习风格诊断', Icons.style, Colors.teal, '学习风格诊断'),
        ];

  @override
  void initState() {
    super.initState();
    if (!_registry.isInitialized) _registry.initialize();
    // 自动加载仪表盘
    _sendQuery(_isTeacher ? '教学仪表盘' : '查看我的状态');
  }

  Future<void> _sendQuery(String query) async {
    setState(() {
      _activeQuery = query;
      _isLoading = true;
      _reply = '';
    });

    try {
      final agent = _registry.getAgent(_agentId);
      if (agent == null) {
        setState(() {
          _reply = '智能体未找到，请确认系统已初始化。';
          _isLoading = false;
        });
        return;
      }
      final result = await agent.handleMessage(query, _registry.session);
      setState(() {
        _reply = result.content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _reply = '加载失败：$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$_emoji $_title'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: '与$_title对话',
            onPressed: () =>
                AgentChatOverlay.show(context, agentId: _agentId),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部描述
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isTeacher
                    ? [Colors.indigo.withValues(alpha: 0.08), Colors.purple.withValues(alpha: 0.04)]
                    : [Colors.blue.withValues(alpha: 0.08), Colors.cyan.withValues(alpha: 0.04)],
              ),
            ),
            child: Text(
              _subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
          // 快捷操作按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions.map((action) {
                final isActive = _activeQuery == action.query;
                return ActionChip(
                  avatar: Icon(action.icon, size: 16,
                      color: isActive ? Colors.white : action.color),
                  label: Text(action.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive ? Colors.white : null,
                      )),
                  backgroundColor: isActive ? action.color : null,
                  onPressed: () => _sendQuery(action.query),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在生成数字孪生报告...'),
                      ],
                    ),
                  )
                : _reply.isEmpty
                    ? Center(
                        child: Text('点击上方按钮查看对应分析',
                            style: TextStyle(color: Colors.grey[400])),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _reply,
                          style: const TextStyle(fontSize: 14, height: 1.6),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final String query;
  const _QuickAction(this.label, this.icon, this.color, this.query);
}
