import 'dart:async';
import '../data/models/skill_def_model.dart';
import 'skill_registry.dart';

class SkillMatchResult {
  final SkillDef skill;
  final double confidence;
  final String matchedKeyword;

  const SkillMatchResult({
    required this.skill,
    required this.confidence,
    required this.matchedKeyword,
  });
}

class SkillMatchService {
  SkillMatchService({SkillRegistry? registry})
      : _registry = registry ?? SkillRegistry.instance;
  final SkillRegistry _registry;

  List<SkillMatchResult> matchAll(String userInput, {double threshold = 0.3}) {
    if (userInput.trim().isEmpty) return [];
    final lower = userInput.toLowerCase();
    final results = <SkillMatchResult>[];

    for (final skill in _registry.getAll()) {
      double score = 0;
      String matchedKeyword = '';

      for (final kw in skill.keywords) {
        if (lower.contains(kw.toLowerCase())) {
          final s = 0.6 + (0.4 * (kw.length / 6.0)).clamp(0.0, 0.4);
          if (s > score) {
            score = s;
            matchedKeyword = kw;
          }
        }
      }

      if (skill.name.isNotEmpty && lower.contains(skill.name)) {
        score = (score + 0.5).clamp(0.0, 1.0);
        if (matchedKeyword.isEmpty) matchedKeyword = skill.name;
      }

      for (final ex in skill.examples) {
        if (ex.isEmpty) continue;
        final exLower = ex.toLowerCase();
        final words = exLower.split(RegExp(r'[\s,，、/]+'));
        final anyWordMatch = words.any((w) => w.length > 1 && lower.contains(w));
        if (anyWordMatch || lower.contains(exLower)) {
          score = (score + 0.3).clamp(0.0, 1.0);
          if (matchedKeyword.isEmpty) {
            matchedKeyword = ex.length > 10 ? '${ex.substring(0, 10)}…' : ex;
          }
        }
      }

      if (score > 0) {
        results.add(SkillMatchResult(
          skill: skill,
          confidence: score.clamp(0.0, 1.0),
          matchedKeyword: matchedKeyword,
        ));
      }
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results.where((r) => r.confidence >= threshold).toList();
  }

  SkillMatchResult? bestMatch(String userInput, {double threshold = 0.5}) {
    final matches = matchAll(userInput, threshold: threshold);
    return matches.isNotEmpty ? matches.first : null;
  }

  Stream<List<SkillMatchResult>> watchInput(String input) async* {
    if (input.trim().length < 2) {
      yield [];
      return;
    }
    await Future.delayed(const Duration(milliseconds: 200));
    yield matchAll(input);
  }
}
