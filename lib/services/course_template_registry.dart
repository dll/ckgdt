import 'course_subgraph_service.dart';

/// Versioned templates used by one-click course generation.
///
/// A course package must be traceable to a stable template, then adapted by
/// syllabus and course profile. This keeps CKGDT, MAD, SEB, literature, sports
/// and other courses on the same platform contract while allowing different
/// graph, practice and evidence shapes.
class CourseTemplateRegistry {
  static const schemaVersion = '1.0.0';
  static const universalTemplateId = 'universal_smart_course';
  static const universalTemplateVersion = '1.0.0';

  static CourseTemplate resolve({
    Map<String, dynamic>? courseProfile,
    CourseProfile? profile,
  }) {
    final resolvedProfile =
        profile ?? _profileFromMap(courseProfile ?? const <String, dynamic>{});
    final overlay = _overlayForDiscipline(resolvedProfile.discipline);
    return CourseTemplate(
      id: universalTemplateId,
      name: '高校数智课程通用模板',
      version: universalTemplateVersion,
      schemaVersion: schemaVersion,
      profile: overlay.profile,
      profileTemplateId: overlay.templateId,
      profileTemplateName: overlay.templateName,
      profileTemplateVersion: overlay.templateVersion,
      discipline: resolvedProfile.discipline,
      courseMode: resolvedProfile.courseMode,
      practiceLabel: resolvedProfile.practiceLabel,
      modules: const [
        '大纲',
        '目标',
        '图谱',
        '理论',
        '视频',
        '课件',
        '实验',
        '作业',
        '测验',
        '考核',
        '达成',
        '问卷',
        '归档',
        '数字孪生',
        '推荐',
        '文档',
      ],
      requiredResources: const {
        '大纲': ['教学大纲', '教学进度', '课程目标'],
        '图谱': ['课程图谱', '领域子图谱', '评价达成图谱'],
        '教学': ['理论讲义', '视频脚本', '课件', '测验'],
        '学习': ['作业', '实践任务', '学习路径'],
        '评价': ['考核方案', '试卷分析', '课程满意度问卷', '达成评价'],
        '归档': ['期初', '期中', '期末', '结课'],
      },
      domainOverlay: overlay.toMap(),
      versionPolicy: const {
        'course_outline': '课程大纲必须版本化，达成计算绑定明确大纲版本。',
        'template_upgrade': '模板升级不得覆盖教师已审核资源，只新增版本并保留历史清单。',
        'lazy_generation': '一键生课先生成目录、清单和骨架，重资源首次使用时生成。',
      },
    );
  }

  static CourseProfile _profileFromMap(Map<String, dynamic> map) {
    return CourseProfile(
      discipline: map['discipline']?.toString() ?? '通用',
      courseMode: map['course_mode']?.toString() ?? '理论实践型',
      practiceLabel: map['practice_label']?.toString() ?? '实践任务',
      graphCategories: (map['graph_categories'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      evidenceTypes: (map['evidence_types'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      rubricDimensions: (map['rubric_dimensions'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  static _TemplateOverlay _overlayForDiscipline(String discipline) {
    switch (discipline) {
      case '工程':
        return const _TemplateOverlay(
          profile: 'engineering_experiment',
          templateId: 'profile_engineering_experiment',
          templateName: '工程实验课程画像模板',
          templateVersion: '1.0.0',
          graphFocus: ['技术体系图谱', '实践项目图谱', '工程能力图谱'],
          activityTypes: ['实验', '项目', '代码/制品评审'],
          evidenceTypes: ['实验报告', '代码仓库', '运行截图', '答辩记录'],
        );
      case '文学':
        return const _TemplateOverlay(
          profile: 'literature_reading',
          templateId: 'profile_literature_reading',
          templateName: '文学研读课程画像模板',
          templateVersion: '1.0.0',
          graphFocus: ['文本研读图谱', '主题流派图谱', '审美评价图谱'],
          activityTypes: ['文本细读', '研讨', '赏析论文'],
          evidenceTypes: ['文本批注', '读书报告', '课堂讨论', '赏析论文'],
        );
      case '体育':
        return const _TemplateOverlay(
          profile: 'sports_training',
          templateId: 'profile_sports_training',
          templateName: '体育训练课程画像模板',
          templateVersion: '1.0.0',
          graphFocus: ['技能训练图谱', '战术规则图谱', '体能评价图谱'],
          activityTypes: ['动作训练', '战术演练', '技能测试'],
          evidenceTypes: ['训练记录', '动作视频', '技能测试', '比赛观察'],
        );
      case '艺术':
        return const _TemplateOverlay(
          profile: 'art_creation',
          templateId: 'profile_art_creation',
          templateName: '艺术创作课程画像模板',
          templateVersion: '1.0.0',
          graphFocus: ['创作技法图谱', '作品展评图谱', '审美表达图谱'],
          activityTypes: ['创作', '展演', '作品评审'],
          evidenceTypes: ['作品图片', '创作过程', '作品集', '互评反馈'],
        );
      case '经管法':
        return const _TemplateOverlay(
          profile: 'case_analysis',
          templateId: 'profile_case_analysis',
          templateName: '经管法案例课程画像模板',
          templateVersion: '1.0.0',
          graphFocus: ['案例情境图谱', '决策论证图谱', '规则适用图谱'],
          activityTypes: ['案例分析', '辩论', '决策方案'],
          evidenceTypes: ['案例分析', '决策方案', '辩论记录', '调研数据'],
        );
      case '技能':
        return const _TemplateOverlay(
          profile: 'skill_simulation',
          templateId: 'profile_skill_simulation',
          templateName: '技能模拟课程画像模板',
          templateVersion: '1.0.0',
          graphFocus: ['技能规范图谱', '情境模拟图谱', '操作评价图谱'],
          activityTypes: ['技能演示', '情境模拟', '操作考核'],
          evidenceTypes: ['操作记录', '模拟视频', '技能清单', '反思报告'],
        );
      default:
        return const _TemplateOverlay(
          profile: 'general_smart_course',
          templateId: 'profile_general_smart_course',
          templateName: '通用数智课程画像模板',
          templateVersion: '1.0.0',
          graphFocus: ['课程图谱', '实践活动图谱', '评价达成图谱'],
          activityTypes: ['实践任务', '案例分析', '反思改进'],
          evidenceTypes: ['作业', '实践报告', '测验', '作品', '课堂表现'],
        );
    }
  }
}

class CourseTemplate {
  final String id;
  final String name;
  final String version;
  final String schemaVersion;
  final String profile;
  final String profileTemplateId;
  final String profileTemplateName;
  final String profileTemplateVersion;
  final String discipline;
  final String courseMode;
  final String practiceLabel;
  final List<String> modules;
  final Map<String, List<String>> requiredResources;
  final Map<String, dynamic> domainOverlay;
  final Map<String, String> versionPolicy;

  const CourseTemplate({
    required this.id,
    required this.name,
    required this.version,
    required this.schemaVersion,
    required this.profile,
    required this.profileTemplateId,
    required this.profileTemplateName,
    required this.profileTemplateVersion,
    required this.discipline,
    required this.courseMode,
    required this.practiceLabel,
    required this.modules,
    required this.requiredResources,
    required this.domainOverlay,
    required this.versionPolicy,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'version': version,
        'schema_version': schemaVersion,
        'profile': profile,
        'profile_template_id': profileTemplateId,
        'profile_template_name': profileTemplateName,
        'profile_template_version': profileTemplateVersion,
        'discipline': discipline,
        'course_mode': courseMode,
        'practice_label': practiceLabel,
        'modules': modules,
        'required_resources': requiredResources,
        'domain_overlay': domainOverlay,
        'version_policy': versionPolicy,
      };
}

class _TemplateOverlay {
  final String profile;
  final String templateId;
  final String templateName;
  final String templateVersion;
  final List<String> graphFocus;
  final List<String> activityTypes;
  final List<String> evidenceTypes;

  const _TemplateOverlay({
    required this.profile,
    required this.templateId,
    required this.templateName,
    required this.templateVersion,
    required this.graphFocus,
    required this.activityTypes,
    required this.evidenceTypes,
  });

  Map<String, dynamic> toMap() => {
        'profile': profile,
        'profile_template_id': templateId,
        'profile_template_name': templateName,
        'profile_template_version': templateVersion,
        'graph_focus': graphFocus,
        'activity_types': activityTypes,
        'evidence_types': evidenceTypes,
      };
}
