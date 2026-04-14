import 'dart:async';
import '../data/local/user_dao.dart';
import '../data/models/user_model.dart';
import 'sync_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final UserDao _userDao = UserDao();
  final SyncService _syncService = SyncService();
  UserModel? _currentUser;
  Timer? _heartbeatTimer;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isTeacher => _currentUser?.isTeacher ?? false;

  Future<void> checkLoginStatus() async {
    _currentUser = await _userDao.getCurrentUser();
    if (_currentUser != null) {
      startHeartbeat();
      _startSyncIfEnabled();
    }
  }

  Future<bool> login(String userId, String password) async {
    final success = await _userDao.login(userId, password);
    if (success) {
      _currentUser = await _userDao.getUser(userId);
      startHeartbeat();
      _startSyncIfEnabled();
    }
    return success;
  }

  Future<void> logout() async {
    stopHeartbeat();
    _syncService.stopAutoSync();
    await _userDao.logout();
    _currentUser = null;
  }

  Future<List<UserModel>> getStudents() async {
    return await _userDao.getStudents();
  }

  Future<bool> createStudent(UserModel student) async {
    return await _userDao.createUser(student);
  }

  Future<bool> updateStudent(UserModel student) async {
    return await _userDao.updateUser(student);
  }

  Future<bool> deleteStudent(String userId) async {
    return await _userDao.deleteUser(userId);
  }

  String? getCurrentUserId() {
    return _currentUser?.userId;
  }

  // ── 心跳机制 ──────────────────────────────────────────────────────────

  /// 启动心跳定时器，每 2 分钟更新 last_active
  void startHeartbeat() {
    stopHeartbeat();
    _updateHeartbeat(); // 立即更新一次
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _updateHeartbeat(),
    );
  }

  /// 停止心跳定时器
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _updateHeartbeat() async {
    final userId = _currentUser?.userId;
    if (userId != null) {
      await _userDao.updateLastActive(userId);
    }
  }

  // ── 数据同步 ──────────────────────────────────────────────────────────

  /// 启动自动同步（如果已启用）
  Future<void> _startSyncIfEnabled() async {
    final userId = _currentUser?.userId;
    final role = _currentUser?.role;
    if (userId != null && role != null) {
      await _syncService.startAutoSync(userId: userId, role: role);
    }
  }

  /// 手动重启同步定时器（配置变更后调用）
  Future<void> restartSync() async {
    _syncService.stopAutoSync();
    await _startSyncIfEnabled();
  }
}
