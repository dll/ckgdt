import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../data/local/database_helper.dart';
import '../data/local/graph_dao.dart';
import '../data/local/quiz_dao.dart';

class DataLoadingService {
  static final DataLoadingService instance = DataLoadingService._();
  factory DataLoadingService() => instance;
  DataLoadingService._();

  final GraphDao _graphDao = GraphDao();
  final QuizDao _quizDao = QuizDao();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _dbHelper.database;
    await _loadResourceFiles();
    _isInitialized = true;
  }

  Future<void> _loadResourceFiles() async {
    try {
      final db = await _dbHelper.database;
      
      final existingFiles = await db.query('resource_files');
      if (existingFiles.isNotEmpty) return;

      final dataPath = 'data';
      final List<Map<String, dynamic>> resources = [];

      // Load from assets
      try {
        final assetManifest = await rootBundle.loadString('AssetManifest.json');
        
        // Videos
        final videoFiles = [
          {'chapter': '第一章 移动应用开发技术体系1', 'name': '第一章 移动应用开发技术体系1.mp4'},
          {'chapter': '第一章 移动应用开发技术体系2', 'name': '第一章 移动应用开发技术体系2.mp4'},
          {'chapter': '第二章 原生开发基础1', 'name': '第二章 原生开发基础1.mp4'},
          {'chapter': '第二章 原生开发基础2', 'name': '第二章 原生开发基础2.mp4'},
          {'chapter': '第三章 混合开发技术1', 'name': '第三章 混合开发技术1.mp4'},
          {'chapter': '第三章 混合开发技术2', 'name': '第三章 混合开发技术2.mp4'},
          {'chapter': '第三章 混合开发技术3', 'name': '第三章 混合开发技术3.mp4'},
          {'chapter': '第四章 小程序开发1', 'name': '第四章 小程序开发1.mp4'},
          {'chapter': '第四章 小程序开发2', 'name': '第四章 小程序开发2.mp4'},
          {'chapter': '第五章 华为多端应用开发1', 'name': '第五章 华为多端应用开发1.mp4'},
          {'chapter': '第五章 华为多端应用开发2', 'name': '第五章 华为多端应用开发2.mp4'},
          {'chapter': '第五章 华为多端应用开发3', 'name': '第五章 华为多端应用开发3.mp4'},
          {'chapter': '第六章 综合开发实践1', 'name': '第六章 综合开发实践1.mp4'},
          {'chapter': '第六章 综合开发实践2', 'name': '第六章 综合开发实践2.mp4'},
          {'chapter': '第六章 综合开发实践3', 'name': '第六章 综合开发实践3.mp4'},
        ];

        for (final video in videoFiles) {
          resources.add({
            'file_name': video['name'],
            'file_path': 'assets/data/视频/${video['name']}',
            'file_type': 'video',
            'chapter': video['chapter'],
            'description': '${video['chapter']} 视频教程',
          });
        }

        // PDFs
        final pdfFiles = [
          '第一章 移动应用开发技术体系1.pdf',
          '第一章 移动应用开发技术体系2.pdf',
          '第二章 原生开发基础1.pdf',
          '第二章 原生开发基础2.pdf',
          '第三章 混合开发技术1.pdf',
          '第三章 混合开发技术2.pdf',
          '第三章 混合开发技术3.pdf',
          '第四章 小程序开发1.pdf',
          '第四章 小程序开发2.pdf',
          '第五章 华为多端应用开发1.pdf',
          '第五章 华为多端应用开发2.pdf',
          '第五章 华为多端应用开发3.pdf',
          '第六章 综合开发实践1.pdf',
          '第六章 综合开发实践2.pdf',
          '第六章 综合开发实践3.pdf',
        ];

        for (final pdf in pdfFiles) {
          final chapter = pdf.replaceAll('.pdf', '');
          resources.add({
            'file_name': pdf,
            'file_path': 'assets/data/课件/清言智谱/$pdf',
            'file_type': 'pdf',
            'chapter': chapter,
            'description': '$chapter 课件',
          });
        }

        // PPTs
        final pptFiles = [
          '第一章 移动应用开发技术体系1.pptx',
          '第一章 移动应用开发技术体系2.pptx',
          '第二章 原生开发基础1.pptx',
          '第二章 原生开发基础2.pptx',
          '第三章 混合开发技术1.pptx',
          '第三章 混合开发技术2.pptx',
          '第三章 混合开发技术3.pptx',
          '第四章 小程序开发1.pptx',
          '第四章 小程序开发2.pptx',
          '第五章 华为多端应用开发1.pptx',
          '第五章 华为多端应用开发2.pptx',
          '第五章 华为多端应用开发3.pptx',
          '第六章 综合开发实践1.pptx',
          '第六章 综合开发实践2.pptx',
          '第六章 综合开发实践3.pptx',
        ];

        for (final ppt in pptFiles) {
          final chapter = ppt.replaceAll('.pptx', '');
          resources.add({
            'file_name': ppt,
            'file_path': 'assets/data/课件/秒出PPT/$ppt',
            'file_type': 'ppt',
            'chapter': chapter,
            'description': '$chapter 课件',
          });
        }

        // Insert into database
        for (final resource in resources) {
          await db.insert('resource_files', resource);
        }
      } catch (e) {
        // Assets not available, use empty list
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<List<Map<String, dynamic>>> getVideos() async {
    final db = await _dbHelper.database;
    final videos = await db.query(
      'resource_files',
      where: 'file_type = ?',
      whereArgs: ['video'],
      orderBy: 'chapter',
    );
    return videos;
  }

  Future<List<Map<String, dynamic>>> getDocuments({String? type}) async {
    final db = await _dbHelper.database;
    if (type != null) {
      return await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: [type],
        orderBy: 'chapter',
      );
    }
    return await db.query(
      'resource_files',
      where: 'file_type IN (?, ?)',
      whereArgs: ['pdf', 'ppt'],
      orderBy: 'file_type, chapter',
    );
  }

  Future<List<String>> getChapters() async {
    return await _quizDao.getChapters();
  }
}
