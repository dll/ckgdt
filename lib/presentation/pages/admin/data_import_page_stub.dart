/// Stub 实现 — Web 平台（不支持文件操作）
import 'package:file_picker/file_picker.dart';

Future<String?> saveStringToFile(String content, String prefix) async {
  return null;
}

Future<Map<String, dynamic>> importStudentsFromFile(String filePath) async {
  return {'success': false, 'message': 'Web 平台暂不支持此操作'};
}

Future<String?> readFileAsString(String filePath) async {
  return null;
}

Future<Map<String, dynamic>> uploadResourceFiles(
    List<PlatformFile> files, String fileType) async {
  return {'success': false, 'message': 'Web 平台暂不支持上传文件'};
}
