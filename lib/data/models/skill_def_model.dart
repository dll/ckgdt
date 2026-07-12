import 'dart:convert';
import 'package:flutter/material.dart';

class SkillCase {
  final String title;
  final String userInput;
  final String resultSummary;

  const SkillCase({
    required this.title,
    required this.userInput,
    required this.resultSummary,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'userInput': userInput,
        'resultSummary': resultSummary,
      };

  factory SkillCase.fromJson(Map<String, dynamic> json) => SkillCase(
        title: json['title'] as String,
        userInput: json['userInput'] as String,
        resultSummary: json['resultSummary'] as String,
      );
}

class SkillDef {
  final String id;
  final String name;
  final String subtitle;
  final String iconName;
  final String colorHex;
  final String description;
  final List<String> features;
  final List<String> examples;
  final String systemPrompt;
  final List<String> usageSteps;
  final List<SkillCase> classicCases;
  final List<String> keywords;
  final int priority;

  const SkillDef({
    required this.id,
    required this.name,
    required this.subtitle,
    this.iconName = 'tips_and_updates',
    this.colorHex = 'FF667eea',
    required this.description,
    this.features = const [],
    this.examples = const [],
    required this.systemPrompt,
    this.usageSteps = const [],
    this.classicCases = const [],
    this.keywords = const [],
    this.priority = 5,
  });

  IconData get icon {
    switch (iconName) {
      case 'account_tree':
        return Icons.account_tree;
      case 'route':
        return Icons.route;
      case 'menu_book':
        return Icons.menu_book;
      case 'quiz':
        return Icons.quiz;
      case 'source':
        return Icons.source;
      case 'assessment':
        return Icons.assessment;
      case 'science':
        return Icons.science;
      case 'workspace_premium':
        return Icons.workspace_premium;
      case 'emoji_events':
        return Icons.emoji_events;
      case 'archive':
        return Icons.archive;
      case 'tips_and_updates':
        return Icons.tips_and_updates;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'psychology':
        return Icons.psychology;
      case 'build':
        return Icons.build;
      default:
        return Icons.tips_and_updates;
    }
  }

  Color get color {
    var hex = colorHex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final value = int.tryParse(hex, radix: 16) ?? 0xFF667eea;
    return Color(value);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'iconName': iconName,
        'colorHex': colorHex,
        'description': description,
        'features': features,
        'examples': examples,
        'systemPrompt': systemPrompt,
        'usageSteps': usageSteps,
        'classicCases': classicCases.map((c) => c.toJson()).toList(),
        'keywords': keywords,
        'priority': priority,
        'formatVersion': 1,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory SkillDef.fromJson(Map<String, dynamic> json) => SkillDef(
        id: json['id'] as String,
        name: json['name'] as String,
        subtitle: json['subtitle'] as String? ?? '',
        iconName: json['iconName'] as String? ?? 'tips_and_updates',
        colorHex: json['colorHex'] as String? ?? 'FF667eea',
        description: json['description'] as String? ?? '',
        features: (json['features'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        examples: (json['examples'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        systemPrompt: json['systemPrompt'] as String? ?? '',
        usageSteps: (json['usageSteps'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        classicCases: (json['classicCases'] as List<dynamic>?)
                ?.map((e) => SkillCase.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        keywords: (json['keywords'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        priority: json['priority'] as int? ?? 5,
      );

  factory SkillDef.fromJsonString(String json) =>
      SkillDef.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
