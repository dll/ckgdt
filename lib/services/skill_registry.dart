import 'dart:convert';
import '../data/models/skill_def_model.dart';
import '../core/error_handler.dart';

class SkillRegistry {
  SkillRegistry._();
  static final SkillRegistry _instance = SkillRegistry._();
  static SkillRegistry get instance => _instance;

  final Map<String, SkillDef> _skills = {};

  void register(SkillDef skill) {
    _skills[skill.id] = skill;
  }

  void registerAll(List<SkillDef> skills) {
    for (final s in skills) {
      _skills[s.id] = s;
    }
  }

  SkillDef? get(String id) => _skills[id];

  List<SkillDef> getAll() => _skills.values.toList();

  List<SkillDef> query(String keyword) {
    if (keyword.trim().isEmpty) return getAll();
    final lower = keyword.toLowerCase();
    return _skills.values.where((s) {
      return s.name.toLowerCase().contains(lower) ||
          s.description.toLowerCase().contains(lower) ||
          s.subtitle.toLowerCase().contains(lower) ||
          s.keywords.any((k) => k.toLowerCase().contains(lower)) ||
          s.features.any((f) => f.toLowerCase().contains(lower));
    }).toList();
  }

  SkillDef? bestMatch(String userMessage, {double threshold = 0.5}) {
    final lower = userMessage.toLowerCase();
    SkillDef? best;
    double bestScore = 0;
    for (final s in _skills.values) {
      double score = 0;
      for (final kw in s.keywords) {
        if (lower.contains(kw.toLowerCase())) { score = 0.6; break; }
      }
      for (final ex in s.examples) {
        final firstWord = ex.split(' ').first;
        if (firstWord.isNotEmpty && lower.contains(firstWord.toLowerCase())) {
          score = (score + 0.2).clamp(0.0, 0.9);
        }
      }
      if (s.name.isNotEmpty && lower.contains(s.name)) {
        score = (score + 0.3).clamp(0.0, 0.9);
      }
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return bestScore >= threshold ? best : null;
  }

  String exportAllToJson() {
    final data = {
      'formatVersion': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'totalSkills': _skills.length,
      'skills': _skills.values.map((s) => s.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  String exportSkillToJson(String id) {
    final skill = _skills[id];
    if (skill == null) return '{}';
    return skill.toJsonString();
  }

  int importFromJson(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return 0;

      if (data.containsKey('skills')) {
        final skillsList = data['skills'];
        if (skillsList is! List) return 0;
        int count = 0;
        for (final s in skillsList) {
          if (s is! Map) continue;
          try {
            final skill = SkillDef.fromJson(s.cast<String, dynamic>());
            if (!_skills.containsKey(skill.id)) {
              _skills[skill.id] = skill;
              count++;
            }
          } catch (_) {}
        }
        return count;
      }

      if (data.containsKey('id')) {
        try {
          final skill = SkillDef.fromJson(data.cast<String, dynamic>());
          if (!_skills.containsKey(skill.id)) {
            _skills[skill.id] = skill;
            return 1;
          }
        } catch (_) {}
      }

      return 0;
    } catch (e, st) {
      swallowDebug(e, tag: 'SkillRegistry.import', stack: st);
      return 0;
    }
  }

  void remove(String id) {
    _skills.remove(id);
  }

  void clear() {
    _skills.clear();
  }

  int get count => _skills.length;
}
