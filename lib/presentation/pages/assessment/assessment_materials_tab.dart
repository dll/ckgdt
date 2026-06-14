import 'package:flutter/material.dart';
import '../../../services/course_context_service.dart';
import '../lab/lab_material_preview_page.dart';

/// 考核材料 Tab — 展示 4 份过程报告材料 + 4 份最终报告材料 + 制度说明
///
/// 数据源：assets `data/考核/` 目录（已在 pubspec.yaml 注册）
/// 点击进入 [LabMaterialPreviewPage] 渲染 Markdown，agentId 设为 'assessment'
class AssessmentMaterialsTab extends StatelessWidget {
  const AssessmentMaterialsTab({super.key});

  static const _processMaterials = [
    _AssessmentMaterial(
      title: '第一周报告 - 项目启动',
      assetPath: 'data/考核/第一周报告-项目启动.md',
      week: '第1周',
      icon: Icons.rocket_launch,
      color: Colors.blue,
    ),
    _AssessmentMaterial(
      title: '第二周报告 - 核心开发',
      assetPath: 'data/考核/第二周报告-核心开发.md',
      week: '第2周',
      icon: Icons.code,
      color: Colors.green,
    ),
    _AssessmentMaterial(
      title: '第三周报告 - 系统整合',
      assetPath: 'data/考核/第三周报告-系统整合.md',
      week: '第3周',
      icon: Icons.merge_type,
      color: Colors.orange,
    ),
    _AssessmentMaterial(
      title: '第四周报告 - 测试交付',
      assetPath: 'data/考核/第四周报告-测试交付.md',
      week: '第4周',
      icon: Icons.verified,
      color: Colors.purple,
    ),
  ];

  static const _finalMaterials = [
    _AssessmentMaterial(
      title: '考核报告1 - 答辩报告',
      assetPath: 'data/考核/考核报告1-答辩报告.md',
      week: '答辩',
      icon: Icons.record_voice_over,
      color: Colors.red,
    ),
    _AssessmentMaterial(
      title: '考核报告2 - 个人报告',
      assetPath: 'data/考核/考核报告2-个人报告.md',
      week: '个人',
      icon: Icons.person,
      color: Colors.blue,
    ),
    _AssessmentMaterial(
      title: '考核报告3 - 小组报告',
      assetPath: 'data/考核/考核报告3-小组报告.md',
      week: '小组',
      icon: Icons.groups,
      color: Colors.green,
    ),
    _AssessmentMaterial(
      title: '考核报告4 - 项目报告',
      assetPath: 'data/考核/考核报告4-项目报告.md',
      week: '项目',
      icon: Icons.folder_special,
      color: Colors.orange,
    ),
  ];

  static const _references = [
    _AssessmentMaterial(
      title: '《移动应用开发》考核说明',
      assetPath: 'data/考核/《移动应用开发》考核说明.md',
      week: '说明',
      icon: Icons.info_outline,
      color: Colors.indigo,
    ),
    _AssessmentMaterial(
      title: '考核报告体系说明',
      assetPath: 'data/考核/考核报告体系说明.md',
      week: '体系',
      icon: Icons.account_tree,
      color: Colors.teal,
    ),
    _AssessmentMaterial(
      title: '课程考核大作业',
      assetPath: 'data/考核/课程考核大作业.md',
      week: '大作业',
      icon: Icons.assignment_turned_in,
      color: Colors.deepPurple,
    ),
    _AssessmentMaterial(
      title: '移动应用开发综合考核方案',
      assetPath: 'data/考核/移动应用开发综合考核方案+new.md',
      week: '方案',
      icon: Icons.description,
      color: Colors.brown,
    ),
  ];

  static const _genericReferences = [
    _AssessmentMaterial(
      title: '考核报告体系说明',
      assetPath: 'data/考核/考核报告体系说明.md',
      week: '体系',
      icon: Icons.account_tree,
      color: Colors.teal,
    ),
    _AssessmentMaterial(
      title: '课程考核大作业',
      assetPath: 'data/考核/课程考核大作业.md',
      week: '大作业',
      icon: Icons.assignment_turned_in,
      color: Colors.deepPurple,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: CourseContextService().activeCourseName(),
      builder: (context, snapshot) {
        final courseName = snapshot.data ?? '';
        final references =
            CourseContextService.isDefaultMobileCourseName(courseName)
                ? _references
                : _genericReferences;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildSection(context, '过程报告材料', '四周开发周期，每周一份过程性报告', Icons.timeline,
                Colors.indigo, _processMaterials),
            const SizedBox(height: 16),
            _buildSection(context, '最终报告材料', '考核大作业的四份核心报告', Icons.assignment,
                Colors.deepPurple, _finalMaterials),
            const SizedBox(height: 16),
            _buildSection(context, '考核制度说明', '考核方案、报告体系、大作业要求', Icons.menu_book,
                Colors.teal, references),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              Colors.indigo.withValues(alpha: 0.08),
              Colors.purple.withValues(alpha: 0.04),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book, size: 20, color: Colors.indigo[700]),
                const SizedBox(width: 8),
                Text('考核材料中心',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo[700])),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '提供四份过程报告 + 四份最终报告的撰写说明，以及考核方案与体系文档。点击任意材料查看完整 Markdown 内容，支持下载到本地。',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color accent,
    List<_AssessmentMaterial> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: 0.5), width: 3),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: accent)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...items.map((m) => _buildMaterialCard(context, m)),
      ],
    );
  }

  Widget _buildMaterialCard(BuildContext context, _AssessmentMaterial m) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LabMaterialPreviewPage(
                assetPath: m.assetPath,
                title: m.title,
                agentId: 'assessment',
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(m.icon, color: m.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: m.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(m.week,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: m.color,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.description,
                            size: 11, color: Colors.grey[400]),
                        const SizedBox(width: 2),
                        Text('Markdown',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[400])),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssessmentMaterial {
  final String title;
  final String assetPath;
  final String week;
  final IconData icon;
  final Color color;

  const _AssessmentMaterial({
    required this.title,
    required this.assetPath,
    required this.week,
    required this.icon,
    required this.color,
  });
}
