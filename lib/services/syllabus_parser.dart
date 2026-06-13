import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import '../data/models/syllabus_data.dart';

class SyllabusParser {
  SyllabusParser();

  Future<SyllabusData> parseFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return parseBytes(bytes);
  }

  SyllabusData parseBytes(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final docFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw Exception('Invalid DOCX: word/document.xml not found'),
    );
    final docXml = utf8.decode(docFile.content);
    final doc = xml.XmlDocument.parse(docXml);
    final paragraphs = _extractParagraphs(doc);
    return _buildSyllabus(paragraphs);
  }

  List<_Para> _extractParagraphs(xml.XmlDocument doc) {
    final paragraphs = <_Para>[];
    final body = doc.findAllElements('w:body').first;
    for (final p in body.findElements('w:p')) {
      final styleEl = p.findElements('w:pStyle').firstOrNull;
      final style = styleEl?.getAttribute('w:val') ?? '';
      final texts = p
          .findElements('w:r')
          .map((r) => r.findElements('w:t').map((t) => t.innerText).join())
          .join();
      final text = texts.trim();
      if (text.isNotEmpty) {
        paragraphs.add(_Para(text: text, style: style));
      }
    }
    return paragraphs;
  }

  String _norm(String t) {
    return t.replaceAll(RegExp(r'[\u3000\xA0]'), ' ').trim();
  }

  SyllabusData _buildSyllabus(List<_Para> paras) {
    String courseName = '';
    String? englishName;
    String? courseCode;
    int lectureHours = 0, labHours = 0;
    double credits = 0;
    String description = '';
    final chapters = <SyllabusChapter>[];
    final labs = <SyllabusLab>[];
    final objectives = <CourseObjective>[];
    final textbooks = <String>[];
    AssessmentStructure assessment = const AssessmentStructure();

    // State machine for parsing
    String section = '';
    int currentChapter = 0;
    String? chapterTitle;
    StringBuffer chapterContent = StringBuffer();
    StringBuffer chapterObjectives = StringBuffer();
    StringBuffer chapterKeyPoints = StringBuffer();
    StringBuffer chapterDiffPoints = StringBuffer();
    StringBuffer chapterIdeo = StringBuffer();
    String collectTarget = ''; // 'content', 'objectives', 'keyPoints', 'diffPoints', 'ideo'

    int currentLab = 0;
    String? labTitle;
    StringBuffer labContent = StringBuffer();
    StringBuffer labObjectives = StringBuffer();
    StringBuffer labEquipment = StringBuffer();
    StringBuffer labNotes = StringBuffer();
    String labCollectTarget = '';

    bool inLabSection = false;

    for (final para in paras) {
      var t = _norm(para.text);
      final tc = t.replaceAll(' ', ''); // collapsed for matching

      // === Course info header (first few lines) ===
      if (courseName.isEmpty && (tc.contains('教学大纲') || tc.contains('课程名称'))) {
        courseName = t.replaceAll(RegExp(r'[（(].*[）)]|教学大纲|课程名称'), '').trim();
        if (courseName.isEmpty) courseName = t;
        continue;
      }
      if (courseName.isEmpty && !t.startsWith('一、') && !t.startsWith('二、') && !t.startsWith('三、') && !t.startsWith('第')) {
        final m = RegExp(r'^(.+?)[（(]').firstMatch(t);
        if (m != null) courseName = m.group(1)!;
        continue;
      }
      if (tc.contains('英文名称')) {
        englishName = t.replaceAll(RegExp(r'英文名称[：:]\s*'), '');
        continue;
      }
      if (tc.contains('课程代码')) {
        courseCode = t.replaceAll(RegExp(r'课程代码[：:]\s*'), '');
        continue;
      }
      if (tc.replaceAll(' ', '').contains('总学时') || tc.replaceAll(' ', '').contains('总学分')) {
        if (tc.contains('学时') || tc.contains('学 时')) {
          final lm = RegExp(r'讲课[：:]\s*(\d+)\s*[,，]\s*实验(\d+)').firstMatch(tc.replaceAll(' ', ''));
          if (lm != null) {
            lectureHours = int.tryParse(lm.group(1)!) ?? 0;
            labHours = int.tryParse(lm.group(2)!) ?? 0;
          }
        }
        if (tc.contains('学分')) {
          final cm = RegExp(r'(\d+\.?\d*)').firstMatch(tc.replaceAll(' ', ''));
          credits = double.tryParse(cm?.group(1) ?? '') ?? 0;
        }
        continue;
      }
      if (t.startsWith('考核方式')) {
        continue;
      }

      // === Section headers ===
      if (!RegExp(r'^[一二三四五六七八九十]+[、.]').hasMatch(t)) {
        // Not a section header — nothing to switch
      } else if (tc.contains('课程简介') || tc.contains('课程描述')) {
        section = 'description';
        continue;
      } else if (tc.contains('课程目标') || tc.contains('教学目标') || tc.contains('毕业要求')) {
        section = 'objectives';
        continue;
      } else if (tc.contains('课程内容') || tc.contains('教学内容')) {
        inLabSection = false;
        section = 'content';
        continue;
      } else if (tc.contains('实验') || tc.contains('实践')) {
        inLabSection = true;
        section = 'lab';
        continue;
      } else if (tc.contains('考核') || tc.contains('成绩') || tc.contains('课程成绩') || tc.contains('成绩评定')) {
        section = 'assessment';
        continue;
      } else if (tc.contains('教材') || tc.contains('参考') || tc.contains('课程资源')) {
        section = 'textbook';
        continue;
      } else if (tc.contains('教学安排') || tc.contains('学时') || tc.contains('学分分配')) {
        // Skip scheduling sections
        continue;
      } else {
        // Catch-all: any unhandled numbered section header exits lab/content
        if (section == 'lab' || section == 'content') {
          section = 'other';
          continue;
        }
      }

      // === Collect based on section ===
      switch (section) {
        case 'description':
          description += t;
          break;

        case 'objectives':
          if (t.contains('课程目标') || t.contains('支撑')) break;
          if (t.contains('使') || t.contains('让') || t.contains('掌握') || t.contains('具备')) {
            objectives.add(CourseObjective(
              id: 'obj${objectives.length + 1}',
              description: t,
            ));
          }
          break;

        case 'content':
          if (inLabSection) break;
          final chMatch = RegExp(r'第\s*([一二三四五六七八九十\d])\s*章\s+(.+)').firstMatch(t);
          if (chMatch != null) {
            // Save previous chapter
            if (chapterTitle != null && currentChapter > 0) {
              chapters.add(SyllabusChapter(
                index: currentChapter,
                title: chapterTitle,
                content: chapterContent.toString().trim(),
                teachingObjectives: chapterObjectives.toString().trim(),
                keyPoints: chapterKeyPoints.toString().trim(),
                difficultPoints: chapterDiffPoints.toString().trim(),
                ideoElement: chapterIdeo.toString().trim(),
              ));
              chapterContent = StringBuffer();
              chapterObjectives = StringBuffer();
              chapterKeyPoints = StringBuffer();
              chapterDiffPoints = StringBuffer();
              chapterIdeo = StringBuffer();
            }
            currentChapter = _cnNum(chMatch.group(1)!);
            chapterTitle = chMatch.group(2)!.trim();
            collectTarget = 'content';
            continue;
          }
          if (chapterTitle == null) break;

          // Strip marker prefix, set target, fall through to collect
          if (t.contains('教学内容') || t.contains('教学内容：')) {
            collectTarget = 'content';
            t = t.replaceAll(RegExp(r'^.*?教学内容[：:]\s*'), '');
            if (t.isEmpty) break;
          } else if (t.contains('学习预期成果') || t.contains('学习成果') || t.contains('教学目标')) {
            collectTarget = 'objectives';
            t = t.replaceAll(RegExp(r'^.*?[学生]*学习[预期成果]*[：:]?\s*'), '');
          } else if (t.contains('教学重点') || t.contains('重点')) {
            if (t.contains('教学难点') || t.contains('难点')) {
              // line with both重点and难点— handle重点 portion only
              collectTarget = 'keyPoints';
            } else {
              collectTarget = 'keyPoints';
              t = t.replaceAll(RegExp(r'^.*?(教学重点|重点)[：:]\s*'), '');
            }
          } else if (t.contains('教学难点') || t.contains('难点')) {
            collectTarget = 'diffPoints';
            t = t.replaceAll(RegExp(r'^.*?(教学难点|难点)[：:]\s*'), '');
          } else if (t.contains('课程思政') || t.contains('思政') || t.contains('思政')) {
            collectTarget = 'ideo';
            t = t.replaceAll(RegExp(r'^.*?(课程思政[元素]?|思政)[：:]\s*'), '');
          }

          switch (collectTarget) {
            case 'content': chapterContent.write('$t\n'); break;
            case 'objectives': chapterObjectives.write('$t\n'); break;
            case 'keyPoints': chapterKeyPoints.write('$t\n'); break;
            case 'diffPoints': chapterDiffPoints.write('$t\n'); break;
            case 'ideo': chapterIdeo.write('$t\n'); break;
          }
          break;

        case 'lab':
          final labMatch = RegExp(r'实验\s*(项目|)[\s]*[一二三四五六七八九十\d]\s*[：:、]\s*(.+)').firstMatch(t);
          if (labMatch != null) {
            if (labTitle != null && currentLab > 0) {
              labs.add(SyllabusLab(
                index: currentLab,
                title: labTitle,
                content: labContent.toString().trim(),
                objectives: labObjectives.toString().trim(),
                equipment: labEquipment.toString().trim(),
                notes: labNotes.toString().trim(),
              ));
              labContent = StringBuffer();
              labObjectives = StringBuffer();
              labEquipment = StringBuffer();
              labNotes = StringBuffer();
            }
            currentLab++;
            labTitle = labMatch.group(2)!.trim();
            labCollectTarget = 'content';
            continue;
          }
          if (labTitle == null) break;

          final trimmed = t.trim();
          if (trimmed.startsWith('实验内容')) {
            labCollectTarget = 'content'; continue;
          }
          if (trimmed.startsWith('学生学习预期成果') ||
              trimmed.startsWith('预期成果') ||
              trimmed.startsWith('学习成果') ||
              trimmed.startsWith('实验目的') ||
              trimmed.startsWith('实验目标')) {
            labCollectTarget = 'objectives'; continue;
          }
          if (trimmed.startsWith('主要仪器设备') ||
              trimmed.startsWith('仪器设备')) {
            labCollectTarget = 'equipment'; continue;
          }
          if (trimmed.startsWith('注意事项') ||
              trimmed.startsWith('实验要求')) {
            labCollectTarget = 'notes'; continue;
          }

          switch (labCollectTarget) {
            case 'content': labContent.write('$t\n'); break;
            case 'objectives': labObjectives.write('$t\n'); break;
            case 'equipment': labEquipment.write('$t\n'); break;
            case 'notes': labNotes.write('$t\n'); break;
          }
          break;

        case 'assessment':
          final dailyM = RegExp(r'平时.*?(\d+)%').firstMatch(t);
          final labM = RegExp(r'实验.*?(\d+)%').firstMatch(t);
          final examM = RegExp(r'期末.*?(\d+)%|末考.*?(\d+)%').firstMatch(t);
          if (dailyM != null || labM != null || examM != null) {
            assessment = AssessmentStructure(
              dailyWeight: (dailyM != null ? int.parse(dailyM.group(1)!) : 20) / 100,
              labWeight: (labM != null ? int.parse(labM.group(1)!) : 30) / 100,
              examWeight: (examM != null ? int.parse(examM.group(1) ?? examM.group(2)!) : 50) / 100,
            );
          }
          break;

        case 'textbook':
          if (t.startsWith('（') || t.startsWith('(') || t.contains('制定人') || t.contains('审核人')) {
            // skip section sub-headers, metadata
          } else if (t.contains('[') || t.contains('］') || t.contains('M]')) {
            textbooks.add(t);
          } else if (t.contains('教材') || t.contains('参考')) {
            // skip header
          } else if (textbooks.isNotEmpty && (t.contains(RegExp(r'20\d{2}')) || t.contains('出版社'))) {
            textbooks.add(t);
          }
          break;
      }
    }

    // Save last chapter
    if (chapterTitle != null && currentChapter > 0) {
      chapters.add(SyllabusChapter(
        index: currentChapter,
        title: chapterTitle,
        content: chapterContent.toString().trim(),
        teachingObjectives: chapterObjectives.toString().trim(),
        keyPoints: chapterKeyPoints.toString().trim(),
        difficultPoints: chapterDiffPoints.toString().trim(),
        ideoElement: chapterIdeo.toString().trim(),
      ));
    }

    // Save last lab
    if (labTitle != null && currentLab > 0) {
      labs.add(SyllabusLab(
        index: currentLab,
        title: labTitle,
        content: labContent.toString().trim(),
        objectives: labObjectives.toString().trim(),
        equipment: labEquipment.toString().trim(),
        notes: labNotes.toString().trim(),
      ));
    }

    return SyllabusData(
      courseName: courseName,
      englishName: englishName,
      courseCode: courseCode,
      lectureHours: lectureHours,
      labHours: labHours,
      credits: credits,
      description: description,
      objectives: objectives,
      chapters: chapters,
      labs: labs,
      assessment: assessment,
      textbooks: textbooks,
    );
  }

  int _cnNum(String cn) {
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    };
    return map[cn] ?? int.tryParse(cn) ?? 0;
  }
}

class _Para {
  final String text;
  final String style;
  _Para({required this.text, this.style = ''});
}
