import '../data/local/user_dao.dart';
import '../data/models/user_model.dart';

class AuthService {
  final UserDao _userDao = UserDao();
  UserModel? _currentUser;

  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isTeacher => _currentUser?.isTeacher ?? false;

  Future<void> checkLoginStatus() async {
    _currentUser = await _userDao.getCurrentUser();
  }

  Future<bool> login(String userId, String password) async {
    final success = await _userDao.login(userId, password);
    if (success) {
      _currentUser = await _userDao.getUser(userId);
    }
    return success;
  }

  Future<void> logout() async {
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
}
