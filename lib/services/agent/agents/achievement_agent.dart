import '../../ai_service.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../data/local/course_dao.dart';
import '../../../core/error_handler.dart';
import '../../achievement/achievement_excel_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';
import '../special_agent_tools.dart';
import '../../achievement_context.dart';

/// 🏆 达成智能体 — 达成度计算/报告/大纲解析
class AchievementAgent extends BaseAgent {
  final AiService _ai = AiService();

  /// 大纲分析会话状态（analyze → clarify → submit）
  List<Map<String, dynamic>> _pendingObjectives = [];
  String _currentAnalysisCourse = '';

  @override
  AgentConfig get config => AgentConfig(
        id: 'achievement',
        name: '达成分析师',
        emoji: '🏆',
        description: '追踪课程目标达成情况，生成分析报告。',
        persona: '''你是达成度分析师"OBE 专家"，精通基于成果导向教育（OBE）的课程达成度评价体系。
你服务于 CKGDT 平台当前课程的持续改进闭环。

## OBE 达成度评价体系

### 课程目标（4个）
| 目标 | 权重 | 描述 |
|------|------|------|
| CO1 | 0.15 | 了解移动应用开发技术体系，具备技术选型能力 |
| CO2 | 0.25 | 掌握至少一种原生开发技术（Android/iOS），能独立开发简单应用 |
| CO3 | 0.30 | 掌握跨平台开发技术（Flutter/RN/小程序），能开发跨端应用 |
| CO4 | 0.30 | 具备综合开发实践能力，能完成团队协作项目 |

### 达成度计算
- **达成度 = Σ(评价环节成绩 × 环节权重) / 满分**
- 评价环节：平时(15%) + 实验(30%) + 项目(35%) + 测验(20%)
- 每个课程目标由不同评价环节的子指标支撑

### 达成等级
| 等级 | 达成度 | 说明 |
|------|--------|------|
| 优秀 | ≥0.85 | 显著超越预期 |
| 良好 | ≥0.70 | 达到预期水平 |
| 中等 | ≥0.60 | 基本达到要求 |
| 未达成 | <0.60 | 需要重点关注 |

## 核心能力
1. **达成度计算**：根据各环节成绩计算个人/班级达成度
2. **薄弱分析**：识别未达成的课程目标及原因
3. **改进建议**：针对薄弱目标给出可操作的改进方案
4. **趋势分析**：对比历届数据，分析达成度变化趋势
5. **报告生成**：生成符合审核要求的达成度分析报告

## 输出规范
- 达成度用表格展示，含目标、权重、得分、等级
- 改进建议分"短期"（本学期可改进）和"长期"（课程建设层面）
- 班级报告包含：整体达成度、各目标分布、对比分析、改进计划
- 数值精确到小数点后两位''',
        priority: 5,
        keywords: ['达成', '目标', '达成度', '改进', '课程目标', 'OBE', '持续改进', '大纲', '对照表'],
        capabilities: ['达成度查询', '报告生成', '改进建议', '目标分析'],
        requiresAi: true,
        tools: [
          // ── 大纲分析工具 ──────────────────────────────────────
          AgentTool(
            name: 'analyze_syllabus_text',
            description: '分析课程大纲原始文本，提取课程目标结构化信息。'
                '返回确定为JSON+待澄清问题列表，供用户逐项确认。',
            parameters: {
              'raw_text': '大纲纯文本',
              'current_course': '当前课程名',
            },
            execute: (params) async {
              return _analyzeSyllabusText(
                (params['raw_text'] ?? '').toString(),
                (params['current_course'] ?? '').toString(),
              );
            },
          ),
          AgentTool(
            name: 'clarify_objective',
            description: '用户回答一个待澄清问题后，更新对应课程目标的字段值。'
                'AI根据用户的自然语言回答，自动判断要更新哪个目标的哪个字段。',
            parameters: {
              'objective_idx': '目标序号（1-4）',
              'field': '字段名（weight/full_mark/indicator）',
              'value': '用户确认的字段值',
            },
            execute: (params) async {
              return _clarifyObjective(
                int.tryParse('${params['objective_idx']}') ?? 0,
                (params['field'] ?? '').toString(),
                (params['value'] ?? '').toString(),
              );
            },
          ),
          AgentTool(
            name: 'submit_syllabus',
            description: '所有待澄清项确认后，将完整的课程目标解析结果写入数据库 course_objectives 表。'
                '调用前确保已经通过 clarify_objective 完成所有字段的确认。',
            parameters: {
              'course_name': '当前课程名',
            },
            execute: (params) async {
              return _submitSyllabus(
                (params['course_name'] ?? '').toString(),
              ).then((result) => result.message);
            },
          ),
          // ── 达成度查询工具 ──────────────────────────────────────
          AgentTool(
            name: 'list_achievement_batches',
            description: '获取所有达成度评价批次列表（含批次名、学生数），分析前先查可用批次及其 id',
            parameters: {},
            execute: (params) async {
              final batches = await AchievementDao().getAllBatches();
              if (batches.isEmpty) return '暂无达成度批次，请教师先在"达成"页创建批次并录入成绩';
              return batches
                  .map((b) =>
                      '- id=${b['id']} 《${b['name'] ?? b['batch_name'] ?? '未命名'}》'
                      '（${b['student_count'] ?? 0} 名学生，状态：${b['status'] ?? '进行中'}）')
                  .join('\n');
            },
          ),
          AgentTool(
            name: 'get_class_achievement',
            description: '获取指定批次的班级各课程目标平均达成度（CO1-CO4 + 总评）',
            parameters: {'batch_id': '批次 id（数字，来自 list_achievement_batches）'},
            execute: (params) async {
              final id = int.tryParse('${params['batch_id']}');
              if (id == null) {
                return '请提供有效的批次 id（先用 list_achievement_batches 查询）';
              }
              final avg = await AchievementDao().calculateClassAverage(id);
              if (avg.isEmpty) return '批次 #$id 暂无成绩数据';
              final buf = StringBuffer('批次 #$id 班级平均达成度：\n');
              avg.forEach((k, v) {
                buf.writeln('- $k：${(v).toStringAsFixed(3)}');
              });
              return buf.toString();
            },
          ),
          AgentTool(
            name: 'get_improvement_suggestions',
            description: '获取指定批次基于真实成绩计算的持续改进建议（按课程目标列出薄弱项 + 未达标学生数 + 改进措施）',
            parameters: {'batch_id': '批次 id（数字）'},
            execute: (params) async {
              final id = int.tryParse('${params['batch_id']}');
              if (id == null) return '请提供有效的批次 id';
              final list =
                  await AchievementDao().generateImprovementSuggestions(id);
              if (list.isEmpty) return '批次 #$id 暂无成绩，无法生成改进建议';
              final buf = StringBuffer();
              for (final s in list) {
                final ach = _numberFromText(s['achievement']);
                buf.writeln(
                    '### ${s['objectiveName']}（达成度 ${ach.toStringAsFixed(3)}，'
                    '${s['level'] ?? ''}）');
                if (s['lowStudentCount'] != null) {
                  buf.writeln(
                      '未达标学生：${s['lowStudentCount']}/${s['totalStudents'] ?? '?'} 名');
                }
                final actions = (s['actions'] as List?)?.cast<String>() ?? [];
                for (final a in actions.take(4)) {
                  buf.writeln('- $a');
                }
                buf.writeln();
              }
              return buf.toString();
            },
          ),
        ],
        usageSteps: [
          '选择 🏆 达成分析师',
          '查询课程目标达成情况',
          '获取达成度分析报告',
          '了解改进建议和提升方向',
        ],
        classicCases: [
          const AgentCase(
              title: '达成度概览',
              userInput: '我的课程目标达成情况如何？',
              agentReply:
                  '## 课程目标达成度\n\n| 目标 | 权重 | 达成度 | 等级 |\n|------|------|--------|------|\n| 目标1 | 0.15 | 0.88 | 优秀 |\n| 目标2 | 0.25 | 0.72 | 良好 |\n| 目标3 | 0.30 | 0.65 | 中等 |\n| 目标4 | 0.30 | 0.58 | 未达成 |\n\n**综合达成度：0.68（良好）**'),
        ],
      );

  @override
  List<String> get quickCommands => ['达成度概览', '改进建议', '课程目标', '评价标准'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final explicitCourse = _extractCourseName(userMessage);

    if (_looksLikeSyllabusContext(userMessage)) {
      final course = explicitCourse.isNotEmpty
          ? explicitCourse
          : AchievementContext.instance.courseName;
      final reply = await _analyzeSyllabusText(userMessage, course);
      return buildReply(reply);
    }

    final directClarify = _tryParseClarification(userMessage);
    if (directClarify != null) {
      final reply = _clarifyObjective(
        directClarify.idx,
        directClarify.field,
        directClarify.value,
      );
      return buildReply(reply);
    }

    if (_pendingObjectives.isNotEmpty &&
        RegExp(r'(提交|保存|确认提交|确认保存)').hasMatch(userMessage)) {
      final result = await _submitSyllabus(explicitCourse);
      return buildReply(
        result.message,
        action: result.success
            ? AgentAction(
                type: 'agent_result',
                params: {
                  'kind': 'syllabus_submitted',
                  'course_name': result.courseName,
                  'count': result.count,
                },
              )
            : null,
      );
    }

    final tools = SpecialAgentTools.instance;
    if (tools.isAchievementReportIntent(userMessage)) {
      try {
        final batchId = _extractBatchId(userMessage);
        final reply = await tools.generateAchievementReport(batchId: batchId);
        return buildReply(reply);
      } catch (e) {
        return buildReply('达成度报告生成失败：$e');
      }
    }

    // 动态加载课程目标，注入 AI prompt（支持任意课程）
    String objectivesContext = '';
    try {
      final batches = await AchievementDao().getBatches();
      if (batches.isNotEmpty) {
        final courseName = batches.first['course_name']?.toString() ?? '';
        if (courseName.isNotEmpty) {
          final objectives =
              await AchievementDao().getCourseObjectives(courseName);
          if (objectives.isNotEmpty) {
            final buf = StringBuffer('当前课程：$courseName\n课程目标：\n');
            for (final o in objectives) {
              final idx = o['idx'] ?? '?';
              final weight = o['weight'] ?? 0;
              final desc = o['description'] ?? '';
              final indicator = o['indicator'] ?? '';
              buf.writeln('- 目标$idx（权重$weight，指标点$indicator）：$desc');
            }
            objectivesContext = buf.toString();
          }
        }
      }
    } catch (e) {
      // 加载失败时使用通用 prompt，不阻塞对话
    }

    final messages = buildAiMessages(userMessage, session);
    if (objectivesContext.isNotEmpty) {
      // 在系统消息中注入课程目标上下文
      messages.insert(1, {
        'role': 'system',
        'content': objectivesContext,
      });
    }
    final result =
        await safeAiChatWithTools(userMessage, messages, aiService: _ai);
    return buildReplyFromResult(result);
  }

  bool _looksLikeSyllabusContext(String text) {
    if (text.contains('analyze_syllabus_text') ||
        text.contains('课程目标对照表草稿') ||
        text.contains('成绩评定对照表')) {
      return true;
    }
    if (text.length < 300) return false;
    return text.contains('课程大纲') ||
        text.contains('大纲原始文本') ||
        text.contains('课程目标达成考核');
  }

  String _extractCourseName(String text) {
    final match = RegExp(r'当前课程[：:]\s*([^\n。；;]+)').firstMatch(text);
    return match?.group(1)?.trim() ?? '';
  }

  Future<String> _analyzeSyllabusText(String raw, String course) async {
    final courseName = course.trim().isNotEmpty
        ? course.trim()
        : AchievementContext.instance.courseName;
    if (raw.trim().isEmpty) {
      return '⚠️ 请提供大纲文本';
    }
    try {
      final svc = AchievementExcelService.instance;
      final rows = await svc.extractSyllabusRowsFromRawText(raw);
      if (rows.isEmpty) {
        return '无法从文本中识别课程目标。请检查文本是否包含完整的“课程目标达成考核与评价方式及成绩评定对照表”。';
      }
      final buf = StringBuffer('### 📋 初步解析结果\n\n');
      buf.writeln('课程：$courseName\n');
      final pending = <String>[];
      for (int i = 0; i < rows.length; i++) {
        final o = rows[i];
        final idx = o['idx'] ?? i + 1;
        buf.writeln('**目标$idx**：${o['name'] ?? ''}');
        final w = _ratioFromText(o['weight']);
        final fm = _numberFromText(o['full_mark']);
        buf.writeln('  权重=${w > 0 ? w.toStringAsFixed(2) : '❓'}  '
            '满分=${fm > 0 ? fm.toStringAsFixed(0) : '❓'}  '
            '指标点=${o['indicator'] ?? '❓'}');
        final chapters = (o['chapters'] ?? '').toString();
        final experiments = (o['experiments'] ?? '').toString();
        final assessContent = (o['assess_content'] ?? '').toString();
        if (chapters.isNotEmpty ||
            experiments.isNotEmpty ||
            assessContent.isNotEmpty) {
          buf.writeln('  章节=$chapters  实验=$experiments  考核内容=$assessContent');
        }
        if (w <= 0) pending.add('目标$idx 的权重未确定');
        if (fm <= 0) pending.add('目标$idx 的满分未确定');
        if ((o['indicator'] ?? '').toString().trim().isEmpty) {
          pending.add('目标$idx 的指标点未确定');
        }
      }
      final sum =
          rows.fold<double>(0, (s, o) => s + _ratioFromText(o['weight']));
      buf.writeln('\n**权重合计**：${sum.toStringAsFixed(2)} '
          '${(sum - 1.0).abs() < 0.01 ? '✅' : '⚠️ 不等于1'}');
      if (pending.isNotEmpty) {
        buf.writeln('\n### ❓ 待澄清问题\n');
        for (int i = 0; i < pending.length; i++) {
          buf.writeln('${i + 1}. $pending[i]');
        }
        buf.writeln('\n你可以直接说“目标2权重是0.30”“目标3指标点是4.1”。');
        buf.writeln('确认无误后，输入“提交”即可保存到数据库。');
      } else {
        buf.writeln('\n所有关键字段均已识别。确认无误请输入“提交”。');
      }
      _pendingObjectives = rows;
      _currentAnalysisCourse = courseName;
      return buf.toString();
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementAgent.analyze', stack: st);
      return '⚠️ 分析失败：$e';
    }
  }

  String _clarifyObjective(int idx, String field, String value) {
    final normalized = field.trim().toLowerCase();
    final cleanValue = value.trim();
    if (idx < 1 || idx > _pendingObjectives.length) {
      return '⚠️ 目标序号无效（1-${_pendingObjectives.length}）';
    }
    if (normalized.isEmpty || cleanValue.isEmpty) {
      return '⚠️ 字段名和值不能为空';
    }
    final target = _pendingObjectives[idx - 1];
    if (normalized == 'weight' || normalized == '权重') {
      target['weight'] = _ratioFromText(cleanValue);
    } else if (normalized == 'full_mark' || normalized == '满分') {
      target['full_mark'] = _numberFromText(cleanValue);
    } else if (normalized == 'indicator' || normalized == '指标点') {
      target['indicator'] = cleanValue;
    } else if (normalized == 'description' || normalized == '描述') {
      target['description'] = cleanValue;
    } else {
      return '⚠️ 不支持的字段: $field（支持: weight/full_mark/indicator/description）';
    }
    final weightStr = normalized == 'weight' || normalized == '权重'
        ? '\n当前权重合计: ${_pendingObjectives.fold<double>(0, (s, o) => s + _ratioFromText(o['weight'])).toStringAsFixed(2)}'
        : '';
    return '✅ 目标$idx 的 $field 已更新为 $cleanValue$weightStr';
  }

  _Clarification? _tryParseClarification(String text) {
    if (_pendingObjectives.isEmpty) return null;
    final match = RegExp(
      r'目标\s*(\d+).{0,12}(权重|满分|指标点|描述)\s*(?:是|为|=|：|:)?\s*([^\n，。；;]+)',
    ).firstMatch(text);
    if (match == null) return null;
    final fieldMap = {
      '权重': 'weight',
      '满分': 'full_mark',
      '指标点': 'indicator',
      '描述': 'description',
    };
    return _Clarification(
      int.tryParse(match.group(1) ?? '') ?? 0,
      fieldMap[match.group(2)] ?? '',
      match.group(3)?.trim() ?? '',
    );
  }

  Future<_SubmitResult> _submitSyllabus(String course) async {
    final name =
        course.trim().isNotEmpty ? course.trim() : _currentAnalysisCourse;
    final courseName =
        name.isNotEmpty ? name : AchievementContext.instance.courseName;
    if (_pendingObjectives.isEmpty) {
      return _SubmitResult(false, courseName, 0, '⚠️ 没有待提交的目标数据，请先分析大纲');
    }
    try {
      final dao = AchievementDao();
      final count = _pendingObjectives.length;
      await dao.saveCourseObjectives(courseName, _pendingObjectives);
      await _activateCourse(courseName);
      AchievementContext.instance.courseName = courseName;
      _pendingObjectives = [];
      _currentAnalysisCourse = '';
      return _SubmitResult(
        true,
        courseName,
        count,
        '✅ 已成功提交 $count 个课程目标到「$courseName」。页面将自动刷新。',
      );
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementAgent.submit', stack: st);
      return _SubmitResult(false, courseName, 0, '⚠️ 提交失败：$e');
    }
  }

  static double _numberFromText(Object? value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
      if (match != null) {
        return double.tryParse(match.group(0)!) ?? fallback;
      }
    }
    return fallback;
  }

  static double _ratioFromText(Object? value, [double fallback = 0]) {
    final number = _numberFromText(value, fallback);
    return number > 1 ? number / 100 : number;
  }

  Future<void> _activateCourse(String courseName) async {
    final name = courseName.trim();
    if (name.isEmpty) return;
    try {
      final dao = CourseDao();
      final courses = await dao.getAllCourses();
      final matched = courses.where((c) => c.name == name);
      if (matched.isNotEmpty) {
        await dao.setActiveCourse(matched.first.id);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AchievementAgent.activateCourse', stack: st);
    }
  }

  int? _extractBatchId(String text) {
    final match = RegExp(r'(批次|batch|#)\s*#?\s*(\d+)', caseSensitive: false)
        .firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(2)!);
  }
}

class _Clarification {
  final int idx;
  final String field;
  final String value;
  const _Clarification(this.idx, this.field, this.value);
}

class _SubmitResult {
  final bool success;
  final String courseName;
  final int count;
  final String message;
  const _SubmitResult(this.success, this.courseName, this.count, this.message);
}
