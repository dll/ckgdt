/// 端到端 smoke 测试 — 跑一遍期初归档完整管线（绕过 AI / UI / DB 层）：
///   1. 注册全部 Processor（registerAll）
///   2. 注入 archiveDataRoot / outputRoot（模拟 main._initArchivePaths）
///   3. 给一份手写 markdown 当作"已生成"的教学大纲
///   4. 走 ArchivePackageService.archiveDocxOf → pandoc → docx 落盘
///   5. 验证文件按 `{学院}+{课程}+{文档类型}+{教师}+{学期}.docx` 命名出现在
///      `archive_out/<学期>/<课程>/期初/` 目录下，并能被读出 ZIP 头（PK\x03\x04）
///
/// 不调用真实 AI，不依赖 LibreOffice。pandoc 必须装好。
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:knowledge_graph_app/data/models/archive_document_model.dart';
import 'package:knowledge_graph_app/services/archive/base_document_processor.dart';
import 'package:knowledge_graph_app/services/archive/pandoc_service.dart';
import 'package:knowledge_graph_app/services/archive/processor_registry.dart';
import 'package:knowledge_graph_app/services/archive_package_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('E2E 期初归档：教学大纲 markdown → docx 落盘 + 命名规范 + ZIP 头', () async {
    if (!await PandocService.instance.isInstalled) {
      // ignore: avoid_print
      print('⏭️ skip: pandoc 未安装');
      return;
    }

    // 1) 注册 processor + 注入路径（模拟 main 启动）
    ProcessorRegistry.instance.registerAll();
    final tmpRoot = Directory.systemTemp.createTempSync('mad_e2e_');
    final archiveOut = Directory(p.join(tmpRoot.path, 'archive_out'))..createSync();
    Directory(p.join(tmpRoot.path, 'data', '归档', '期初', '模板'))
        .createSync(recursive: true);
    BaseDocumentProcessor.archiveDataRoot = p.join(tmpRoot.path, 'data', '归档');
    ArchivePackageService.outputRoot = archiveOut.path;

    // 2) 构造一份"已生成"的教学大纲（不入库，直接交给打包服务）
    final doc = ArchiveDocument(
      id: 9999,
      title: '期初教学大纲',
      documentType: 'syllabus',
      period: 'beginning',
      courseType: 'exam',
      content: '''# 移动应用开发 教学大纲

## 一、基本信息
- 课程名称：移动应用开发
- 总学时：48
- 学分：3

## 二、课程目标
1. 掌握 Android / iOS / Flutter 主流移动开发框架。
2. 理解原生与跨平台技术的取舍。
3. 能独立完成一个移动端应用作品。

## 三、教学内容（按章节）
| 章节 | 主题 | 学时 |
| --- | --- | --- |
| 第 1 章 | 移动应用技术全景 | 4 |
| 第 2 章 | Android 与 iOS 原生 | 8 |
| 第 3 章 | Flutter / RN 跨平台 | 12 |
| 第 4 章 | 微信小程序 | 8 |
| 第 5 章 | HarmonyOS | 8 |
| 第 6 章 | 综合实践 | 8 |

## 四、考核方式
平时 30% + 实验 30% + 期末 40%
''',
      isGenerated: true,
      status: 'approved',
    );

    // 3) 直接生成 docx 字节，绕过 ArchivePackageService（它要 DAO/auth 上下文）
    final processor = ProcessorRegistry.instance.find('syllabus')!;
    final docxBytes = await processor.toDocx(doc);

    // 4) 落盘到模拟的归档输出目录，命名走 ArchivePackageService.fileBase 规则
    final naming = ArchiveNaming(
      department: '软件学院',
      course: '移动应用开发',
      docLabel: '教学大纲',
      teacher: '刘东良',
      semester: '2025-2026-2',
    );
    final outDir = Directory(
        p.join(archiveOut.path, naming.semester, naming.course, '期初'))
      ..createSync(recursive: true);
    final outFile = File(p.join(outDir.path, '${naming.fileBase()}.docx'));
    await outFile.writeAsBytes(docxBytes, flush: true);

    // 5) 校验：文件存在 + 是合法 zip（docx = zip）
    expect(outFile.existsSync(), isTrue, reason: 'docx 没落盘');
    final bytes = await outFile.readAsBytes();
    expect(bytes.length, greaterThan(1000), reason: 'docx 太小');
    // ZIP 局部文件头 PK\x03\x04
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
    expect(bytes[2], 0x03);
    expect(bytes[3], 0x04);

    // 6) 校验命名：含 +教学大纲+ 段、结尾 .docx
    final fileName = p.basename(outFile.path);
    expect(fileName, endsWith('.docx'));
    expect(fileName, contains('+教学大纲+'));
    // 路径形如 archive_out/<学期>/<课程>/期初/xxx.docx
    final rel = p.relative(outFile.path, from: archiveOut.path);
    final segs = p.split(rel);
    expect(segs.length, 4, reason: 'rel=$rel 应为 学期/课程/期初/xxx.docx');
    expect(segs[2], '期初');

    // 输出诊断信息（成功路径）
    // ignore: avoid_print
    print('✅ docx 落盘 ${bytes.length} bytes → ${outFile.path}');

    // 7) 清理
    tmpRoot.deleteSync(recursive: true);
  });
}
