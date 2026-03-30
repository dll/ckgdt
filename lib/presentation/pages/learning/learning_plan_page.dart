import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';

class LearningPlanPage extends StatefulWidget {
  const LearningPlanPage({super.key});

  @override
  State<LearningPlanPage> createState() => _LearningPlanPageState();
}

class _LearningPlanPageState extends State<LearningPlanPage> {
  final _authService = AuthService();

  final List<Map<String, dynamic>> _plans = [
    {
      'title': 'Flutter入门计划',
      'description': '7天学会Flutter基础开发',
      'progress': 60,
      'days': 7,
      'completedDays': 4,
      'chapters': ['Flutter概述', 'Dart语言基础', 'Widget介绍', '状态管理'],
      'color': Colors.blue,
    },
    {
      'title': 'Android开发进阶',
      'description': '14天掌握Android高级特性',
      'progress': 30,
      'days': 14,
      'completedDays': 4,
      'chapters': ['自定义View', '性能优化', 'NDK开发', '架构模式'],
      'color': Colors.green,
    },
    {
      'title': '跨平台开发实战',
      'description': '30天完成一个完整项目',
      'progress': 10,
      'days': 30,
      'completedDays': 3,
      'chapters': ['项目规划', '需求分析', '架构设计', '编码实现', '测试部署'],
      'color': Colors.purple,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习计划'),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeader();
          }
          return _buildPlanCard(_plans[index - 1]);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePlanDialog(context),
        backgroundColor: const Color(0xFF667eea),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    final totalProgress = _plans.isEmpty
        ? 0.0
        : _plans.map((p) => p['progress'] as int).reduce((a, b) => a + b) /
            _plans.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '总体进度',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: totalProgress / 100,
                      minHeight: 10,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF667eea)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${totalProgress.toInt()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF667eea),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '正在参与 ${_plans.length} 个学习计划',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showPlanDetail(context, plan),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (plan['color'] as Color).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.calendar_today,
                      color: plan['color'] as Color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan['title'] as String,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          plan['description'] as String,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deletePlan(plan);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除计划'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (plan['progress'] as int) / 100,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                            plan['color'] as Color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${plan['progress']}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: plan['color'] as Color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已完成 ${plan['completedDays']}/${plan['days']} 天',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    '${(plan['chapters'] as List).length} 个章节',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlanDetail(BuildContext context, Map<String, dynamic> plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan['title'] as String,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: (plan['chapters'] as List).length,
                    itemBuilder: (context, index) {
                      final isCompleted = index < plan['completedDays'];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isCompleted ? Colors.green : Colors.grey[300],
                          child: isCompleted
                              ? const Icon(Icons.check, color: Colors.white)
                              : Text('${index + 1}'),
                        ),
                        title: Text(
                          plan['chapters'][index] as String,
                          style: TextStyle(
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: isCompleted ? Colors.grey : null,
                          ),
                        ),
                        trailing: isCompleted
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : const Icon(Icons.radio_button_unchecked,
                                color: Colors.grey),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreatePlanDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建学习计划'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: '计划名称',
                  hintText: '输入计划名称',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: '计划描述',
                  hintText: '输入计划描述',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('学习计划创建功能开发中')),
                );
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  void _deletePlan(Map<String, dynamic> plan) {
    setState(() {
      _plans.remove(plan);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 "${plan['title']}"')),
    );
  }
}
