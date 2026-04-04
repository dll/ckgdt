# 实验学习指导图谱
*基于刘东良教师移动应用开发学生学习指导手册制定*

## 🔬 实验学习体系概览

### 🎯 实验学习目标
- **基础技能培养**：掌握移动应用开发的基本方法和工具
- **实践能力提升**：通过项目实战提升编程和解决问题的能力
- **创新思维培养**：培养创新意识和创新能力
- **团队协作能力**：通过团队项目培养协作精神

### 📊 实验体系结构
```
实验教学体系（24学时）
├── 基础技能实验（实验1-2）
│   ├── 实验一 开发环境搭建（2学时）
│   └── 实验二 原生应用开发（4学时）
│
├── 跨平台技术实验（实验3-4）
│   ├── 实验三 跨平台应用开发（4学时）
│   └── 实验四 微信小程序开发（4学时）
│
├── 多端与综合实验（实验5-6）
│   ├── 实验五 鸿蒙多端应用开发（4学时）
│   └── 实验六 跨平台综合项目实战（6学时）
```

## 🛠️ 实验一 开发环境搭建

### 实验目标与准备
```
实验目标体系
├── 技术目标
│   ├── 搭建完整的移动应用开发工具链
│   ├── 掌握AI编程工具的配置和使用
│   ├── 熟悉各平台开发环境和工具
│   └── 验证环境配置的正确性
│
├── 能力目标
│   ├── 培养独立解决环境问题的能力
│   ├── 建立系统性的工具使用思维
│   ├── 掌握AI辅助开发的基本方法
│   └── 形成良好的开发习惯
│
└── 素质目标
    ├── 培养严谨的工程思维
    ├── 建立持续学习的意识
    ├── 形成问题解决的方法论
    └── 提升技术文档阅读能力
```

### 环境搭建checklist
```bash
# Windows开发环境检查清单
✅ 系统要求检查
□ Windows 10 1903以上版本
□ 内存 16GB以上（推荐）
□ 硬盘空间 100GB以上可用
□ 网络连接稳定

✅ 基础工具安装
□ Git 2.40+
  git --version
□ Node.js 18.17.0+
  node --version && npm --version
□ Python 3.8+
  python --version
□ Java JDK 11+
  java -version

✅ Android开发环境
□ Android Studio 2023.3+
□ Android SDK API 28, 31, 33, 34
□ Android Build Tools 33.0.2+
□ AVD模拟器配置
  # 验证命令
  adb devices
  flutter doctor

✅ 跨平台工具
□ Flutter SDK 3.13.0+
  flutter --version
  flutter doctor
□ VS Code + Flutter插件
□ React Native CLI（可选）
  npx react-native --version

✅ AI编程工具
□ GitHub Copilot配置
□ CodeGeeX插件安装
□ AI工具权限和配置
□ 代码补全测试

✅ 辅助工具
□ Postman API测试
□ Git GUI工具
□ 设计工具（Figma等）
□ 数据库工具（可选）
```

### AI工具集成配置
```javascript
// GitHub Copilot配置示例
// .vscode/settings.json
{
  "github.copilot.enable": {
    "*": true,
    "yaml": false,
    "plaintext": false,
    "markdown": true
  },
  "github.copilot.inlineSuggest.enable": true,
  "github.copilot.advanced": {
    "listCount": 5,
    "inlineSuggestCount": 3
  }
}

// AI辅助代码示例
// 使用AI生成Flutter Widget
class AICourseCard extends StatelessWidget {
  final Course course;
  
  const AICourseCard({Key? key, required this.course}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // AI建议：使用Card组件创建美观的课程卡片
    return Card(
      elevation: 4,
      margin: EdgeInsets.all(8),
      child: InkWell(
        onTap: () {
          // AI建议：添加路由导航
          Navigator.pushNamed(context, '/course-detail', arguments: course);
        },
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.title,
                style: Theme.of(context).textTheme.headline6,
              ),
              SizedBox(height: 8),
              Text(
                course.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${course.duration} 分钟'),
                  Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 常见问题解决
```
环境问题诊断和解决
├── Android Studio问题
│   ├── Gradle构建失败
│   │   ├── 原因：网络问题、版本冲突
│   │   ├── 解决：配置镜像源、检查版本
│   │   └── 验证：./gradlew clean build
│   ├── 模拟器启动失败
│   │   ├── 原因：虚拟化未开启、内存不足
│   │   ├── 解决：开启VT-x、调整AVD配置
│   │   └── 验证：模拟器正常启动
│   └── SDK下载失败
│       ├── 原因：网络限制、代理问题
│       ├── 解决：科学上网、使用镜像
│       └── 验证：SDK Manager正常下载
│
├── Flutter问题
│   ├── Flutter Doctor检查失败
│   │   ├── Android toolchain问题
│   │   ├── iOS开发环境问题（Mac）
│   │   └── 编辑器插件问题
│   ├── 包依赖冲突
│   │   ├── 版本约束冲突
│   │   ├── 平台兼容性问题
│   │   └── 依赖传递冲突
│   └── 编译错误
│       ├── Dart语法错误
│       ├── 原生依赖问题
│       └── 资源文件问题
│
├── AI工具问题
│   ├── GitHub Copilot无法激活
│   │   ├── 账号权限问题
│   │   ├── 网络连接问题
│   │   └── 插件配置问题
│   ├── 代码建议不准确
│   │   ├── 上下文信息不足
│   │   ├── 编程语言识别错误
│   │   └── 模型训练数据局限
│   └── 性能影响问题
│       ├── IDE响应变慢
│       ├── 内存占用过高
│       └── 网络延迟影响
│
└── 网络和代理问题
    ├── GitHub访问问题
    │   ├── DNS解析问题
    │   ├── 网络封锁问题
    │   └── 代理配置问题
    ├── 包管理器下载慢
    │   ├── npm镜像配置
    │   ├── Maven镜像配置
    │   └── Flutter镜像配置
    └── 官方文档访问
        ├── Google服务访问
        ├── Apple开发者网站
        └── 技术社区访问
```

## 📱 实验二 原生应用开发

### 实验设计思路
```
项目设计理念
├── 主题选择：智慧校园登录应用
│   ├── 贴近学生生活场景
│   ├── 功能简单但完整
│   ├── 体现原生开发特色
│   └── 便于理解和扩展
│
├── 技术选型：Kotlin + Material Design
│   ├── 现代化Android开发语言
│   ├── Google推荐设计语言
│   ├── 丰富的UI组件库
│   └── 良好的开发体验
│
├── 架构模式：MVVM + Jetpack
│   ├── 清晰的代码结构
│   ├── 便于测试和维护
│   ├── 官方推荐架构
│   └── 现代Android开发标准
│
└── 学习重点
    ├── Activity生命周期管理
    ├── UI组件和布局使用
    ├── 数据传递和存储
    └── Material Design应用
```

### 核心功能实现
```kotlin
// MainActivity.kt - 主活动实现
class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private lateinit var viewModel: LoginViewModel
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        setupViewModel()
        setupViews()
        observeViewModel()
    }
    
    private fun setupViewModel() {
        viewModel = ViewModelProvider(this)[LoginViewModel::class.java]
    }
    
    private fun setupViews() {
        // Material Design 3组件配置
        with(binding) {
            // 用户名输入框配置
            usernameLayout.apply {
                hint = "请输入学号"
                endIconMode = TextInputLayout.END_ICON_CLEAR_TEXT
                setHelperTextEnabled(true)
                helperText = "请输入8位学号"
            }
            
            // 密码输入框配置
            passwordLayout.apply {
                hint = "请输入密码"
                endIconMode = TextInputLayout.END_ICON_PASSWORD_TOGGLE
                setHelperTextEnabled(true)
                helperText = "密码长度6-20位"
            }
            
            // 登录按钮配置
            loginButton.setOnClickListener {
                val username = usernameEditText.text.toString()
                val password = passwordEditText.text.toString()
                viewModel.login(username, password)
            }
            
            // 注册按钮配置
            registerButton.setOnClickListener {
                startActivity(Intent(this@MainActivity, RegisterActivity::class.java))
            }
        }
    }
    
    private fun observeViewModel() {
        // 观察登录状态
        viewModel.loginState.observe(this) { state ->
            when (state) {
                is LoginState.Loading -> {
                    binding.progressBar.isVisible = true
                    binding.loginButton.isEnabled = false
                }
                is LoginState.Success -> {
                    binding.progressBar.isVisible = false
                    // 跳转到主页面
                    startActivity(Intent(this, HomeActivity::class.java))
                    finish()
                }
                is LoginState.Error -> {
                    binding.progressBar.isVisible = false
                    binding.loginButton.isEnabled = true
                    showErrorDialog(state.message)
                }
            }
        }
        
        // 观察表单验证
        viewModel.formValid.observe(this) { isValid ->
            binding.loginButton.isEnabled = isValid
        }
    }
    
    private fun showErrorDialog(message: String) {
        MaterialAlertDialogBuilder(this)
            .setTitle("登录失败")
            .setMessage(message)
            .setPositiveButton("确定") { dialog, _ ->
                dialog.dismiss()
            }
            .show()
    }
}

// LoginViewModel.kt - 视图模型
class LoginViewModel : ViewModel() {
    private val _loginState = MutableLiveData<LoginState>()
    val loginState: LiveData<LoginState> = _loginState
    
    private val _formValid = MutableLiveData<Boolean>()
    val formValid: LiveData<Boolean> = _formValid
    
    fun login(username: String, password: String) {
        viewModelScope.launch {
            try {
                _loginState.value = LoginState.Loading
                
                // 表单验证
                if (!validateForm(username, password)) {
                    _loginState.value = LoginState.Error("请检查输入信息")
                    return@launch
                }
                
                // 模拟网络请求
                delay(2000)
                
                // 调用登录API
                val result = AuthRepository.login(username, password)
                if (result.isSuccess) {
                    // 保存用户信息
                    saveUserInfo(result.userInfo)
                    _loginState.value = LoginState.Success(result.userInfo)
                } else {
                    _loginState.value = LoginState.Error(result.message)
                }
            } catch (e: Exception) {
                _loginState.value = LoginState.Error("网络连接失败")
            }
        }
    }
    
    private fun validateForm(username: String, password: String): Boolean {
        val isUsernameValid = username.length == 8 && username.all { it.isDigit() }
        val isPasswordValid = password.length in 6..20
        
        val isValid = isUsernameValid && isPasswordValid
        _formValid.value = isValid
        return isValid
    }
    
    private suspend fun saveUserInfo(userInfo: UserInfo) {
        // 使用DataStore保存用户信息
        UserPreferences.saveUserInfo(userInfo)
    }
}

// UserInfo.kt - 数据模型
data class UserInfo(
    val studentId: String,
    val name: String,
    val college: String,
    val major: String,
    val grade: String,
    val avatar: String?
)

// LoginState.kt - 状态封装
sealed class LoginState {
    object Loading : LoginState()
    data class Success(val userInfo: UserInfo) : LoginState()
    data class Error(val message: String) : LoginState()
}
```

### 性能优化技巧
```kotlin
// 内存优化示例
class ImageUtils {
    companion object {
        fun loadImageOptimized(imageView: ImageView, url: String) {
            Glide.with(imageView.context)
                .load(url)
                .apply(
                    RequestOptions()
                        .placeholder(R.drawable.placeholder)
                        .error(R.drawable.error)
                        .diskCacheStrategy(DiskCacheStrategy.ALL)
                        .override(300, 300) // 限制图片尺寸
                )
                .into(imageView)
        }
    }
}

// 列表优化示例
class CourseAdapter : RecyclerView.Adapter<CourseAdapter.ViewHolder>() {
    private var courses: List<Course> = emptyList()
    
    // ViewHolder模式减少findViewById调用
    class ViewHolder(private val binding: ItemCourseBinding) : 
        RecyclerView.ViewHolder(binding.root) {
        
        fun bind(course: Course) {
            binding.apply {
                titleText.text = course.title
                descriptionText.text = course.description
                durationText.text = "${course.duration} 分钟"
                
                // 使用优化的图片加载
                ImageUtils.loadImageOptimized(courseImage, course.imageUrl)
                
                root.setOnClickListener {
                    // 处理点击事件
                    onCourseClick(course)
                }
            }
        }
    }
    
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemCourseBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return ViewHolder(binding)
    }
    
    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(courses[position])
    }
    
    override fun getItemCount() = courses.size
    
    fun updateCourses(newCourses: List<Course>) {
        val diffCallback = CourseDiffCallback(courses, newCourses)
        val diffResult = DiffUtil.calculateDiff(diffCallback)
        
        courses = newCourses
        diffResult.dispatchUpdatesTo(this)
    }
}

// DiffUtil优化列表更新
class CourseDiffCallback(
    private val oldList: List<Course>,
    private val newList: List<Course>
) : DiffUtil.Callback() {
    
    override fun getOldListSize() = oldList.size
    override fun getNewListSize() = newList.size
    
    override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
        return oldList[oldItemPosition].id == newList[newItemPosition].id
    }
    
    override fun areContentsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
        return oldList[oldItemPosition] == newList[newItemPosition]
    }
}
```

## 🦋 实验三 跨平台应用开发

### Flutter项目架构
```dart
// Flutter项目结构和架构设计
/*
lib/
├── main.dart                    # 应用入口
├── app/                        # 应用层
│   ├── app.dart               # App配置
│   └── routes.dart            # 路由配置
├── core/                      # 核心层
│   ├── constants/             # 常量定义
│   ├── utils/                 # 工具类
│   ├── services/              # 服务类
│   └── network/               # 网络层
├── data/                      # 数据层
│   ├── models/                # 数据模型
│   ├── repositories/          # 数据仓库
│   └── providers/             # 数据提供者
├── presentation/              # 表现层
│   ├── pages/                 # 页面
│   ├── widgets/               # 组件
│   ├── blocs/                 # 状态管理
│   └── themes/                # 主题配置
└── features/                  # 功能模块
    ├── auth/                  # 认证模块
    ├── courses/               # 课程模块
    └── profile/               # 个人模块
*/

// main.dart - 应用入口
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc()..add(AuthCheckRequested()),
        ),
        BlocProvider<CourseBloc>(
          create: (context) => CourseBloc(),
        ),
        BlocProvider<ThemeBloc>(
          create: (context) => ThemeBloc(),
        ),
      ],
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp(
            title: 'Smart Campus',
            theme: themeState.themeData,
            initialRoute: '/',
            routes: AppRoutes.routes,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
```

### 状态管理实践
```dart
// 使用Bloc模式进行状态管理
// course_bloc.dart
class CourseBloc extends Bloc<CourseEvent, CourseState> {
  final CourseRepository _courseRepository = CourseRepository();
  
  CourseBloc() : super(CourseInitial()) {
    on<CourseLoadRequested>(_onCourseLoadRequested);
    on<CourseRefreshRequested>(_onCourseRefreshRequested);
    on<CourseSearchRequested>(_onCourseSearchRequested);
  }
  
  Future<void> _onCourseLoadRequested(
    CourseLoadRequested event,
    Emitter<CourseState> emit,
  ) async {
    emit(CourseLoading());
    
    try {
      final courses = await _courseRepository.getCourses();
      emit(CourseLoaded(courses));
    } catch (error) {
      emit(CourseError(error.toString()));
    }
  }
  
  Future<void> _onCourseRefreshRequested(
    CourseRefreshRequested event,
    Emitter<CourseState> emit,
  ) async {
    try {
      final courses = await _courseRepository.getCourses(forceRefresh: true);
      emit(CourseLoaded(courses));
    } catch (error) {
      emit(CourseError(error.toString()));
    }
  }
  
  Future<void> _onCourseSearchRequested(
    CourseSearchRequested event,
    Emitter<CourseState> emit,
  ) async {
    emit(CourseLoading());
    
    try {
      final courses = await _courseRepository.searchCourses(event.query);
      emit(CourseLoaded(courses));
    } catch (error) {
      emit(CourseError(error.toString()));
    }
  }
}

// course_event.dart
abstract class CourseEvent extends Equatable {
  const CourseEvent();
  
  @override
  List<Object> get props => [];
}

class CourseLoadRequested extends CourseEvent {}

class CourseRefreshRequested extends CourseEvent {}

class CourseSearchRequested extends CourseEvent {
  final String query;
  
  const CourseSearchRequested(this.query);
  
  @override
  List<Object> get props => [query];
}

// course_state.dart
abstract class CourseState extends Equatable {
  const CourseState();
  
  @override
  List<Object> get props => [];
}

class CourseInitial extends CourseState {}

class CourseLoading extends CourseState {}

class CourseLoaded extends CourseState {
  final List<Course> courses;
  
  const CourseLoaded(this.courses);
  
  @override
  List<Object> get props => [courses];
}

class CourseError extends CourseState {
  final String message;
  
  const CourseError(this.message);
  
  @override
  List<Object> get props => [message];
}
```

### 性能优化实践
```dart
// 列表性能优化
class OptimizedCourseList extends StatelessWidget {
  final List<Course> courses;
  
  const OptimizedCourseList({Key? key, required this.courses}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // 提供itemExtent提高性能
      itemExtent: 120.0,
      // 缓存extent提高滚动性能
      cacheExtent: 500.0,
      itemCount: courses.length,
      itemBuilder: (context, index) {
        return CourseListItem(
          key: ValueKey(courses[index].id), // 提供stable key
          course: courses[index],
        );
      },
    );
  }
}

// 图片缓存优化
class OptimizedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  
  const OptimizedNetworkImage({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: Icon(Icons.error),
      ),
      // 内存缓存配置
      memCacheWidth: width?.toInt(),
      memCacheHeight: height?.toInt(),
      // 磁盘缓存配置
      cacheManager: CacheManager(
        Config(
          'customCacheKey',
          stalePeriod: Duration(days: 7),
          maxNrOfCacheObjects: 100,
        ),
      ),
    );
  }
}

// Widget重建优化
class SmartBuilder extends StatelessWidget {
  final Widget child;
  final bool condition;
  
  const SmartBuilder({
    Key? key,
    required this.child,
    required this.condition,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CourseBloc, CourseState>(
      // 只在特定条件下重建
      buildWhen: (previous, current) {
        return condition && previous.runtimeType != current.runtimeType;
      },
      builder: (context, state) {
        return child;
      },
    );
  }
}
```

## 🌐 实验四 微信小程序开发

### 跨端开发思维
```javascript
// Uniapp项目结构
/*
project/
├── pages/                     # 页面目录
│   ├── index/                # 首页
│   ├── courses/              # 课程页
│   └── profile/              # 个人页
├── components/               # 组件目录
├── static/                  # 静态资源
├── store/                   # Vuex状态管理
├── utils/                   # 工具类
├── api/                     # API接口
├── styles/                  # 样式文件
├── pages.json              # 页面配置
├── manifest.json           # 应用配置
└── App.vue                 # 应用入口
*/

// pages/courses/courses.vue - 课程列表页面
<template>
  <view class="courses-container">
    <!-- 搜索框 -->
    <view class="search-container">
      <uni-search-bar 
        :radius="100" 
        placeholder="搜索课程" 
        v-model="searchQuery"
        @confirm="onSearchConfirm"
        @input="onSearchInput"
      />
    </view>
    
    <!-- 课程分类 -->
    <view class="category-container">
      <uni-segmented-control 
        :current="currentCategory" 
        :values="categories" 
        @clickItem="onCategoryChange" 
        styleType="button"
      />
    </view>
    
    <!-- 课程列表 -->
    <view class="course-list">
      <uni-list>
        <uni-list-item 
          v-for="course in filteredCourses" 
          :key="course.id"
          :title="course.title"
          :note="course.description"
          :thumb="course.thumbnail"
          clickable
          @click="onCourseClick(course)"
        >
          <template v-slot:footer>
            <view class="course-meta">
              <text class="duration">{{ course.duration }}分钟</text>
              <text class="rating">⭐ {{ course.rating }}</text>
            </view>
          </template>
        </uni-list-item>
      </uni-list>
    </view>
    
    <!-- 加载更多 -->
    <uni-load-more 
      :status="loadMoreStatus" 
      @clickLoadMore="loadMoreCourses"
    />
  </view>
</template>

<script>
import { mapState, mapActions } from 'vuex'

export default {
  data() {
    return {
      searchQuery: '',
      currentCategory: 0,
      categories: ['全部', 'Android', 'iOS', 'Flutter', '小程序'],
      loadMoreStatus: 'more',
      searchTimeout: null
    }
  },
  
  computed: {
    ...mapState('courses', ['courses', 'loading']),
    
    filteredCourses() {
      let result = this.courses
      
      // 分类筛选
      if (this.currentCategory > 0) {
        const category = this.categories[this.currentCategory]
        result = result.filter(course => course.category === category)
      }
      
      // 搜索筛选
      if (this.searchQuery) {
        result = result.filter(course => 
          course.title.includes(this.searchQuery) ||
          course.description.includes(this.searchQuery)
        )
      }
      
      return result
    }
  },
  
  async onLoad() {
    await this.loadCourses()
  },
  
  async onPullDownRefresh() {
    await this.refreshCourses()
    uni.stopPullDownRefresh()
  },
  
  onReachBottom() {
    this.loadMoreCourses()
  },
  
  methods: {
    ...mapActions('courses', ['loadCourses', 'refreshCourses', 'searchCourses']),
    
    onSearchInput(value) {
      // 防抖搜索
      clearTimeout(this.searchTimeout)
      this.searchTimeout = setTimeout(() => {
        this.performSearch(value)
      }, 500)
    },
    
    onSearchConfirm(e) {
      this.performSearch(e.value)
    },
    
    async performSearch(query) {
      if (query.trim()) {
        await this.searchCourses(query)
      } else {
        await this.loadCourses()
      }
    },
    
    onCategoryChange(e) {
      this.currentCategory = e.currentIndex
    },
    
    onCourseClick(course) {
      uni.navigateTo({
        url: `/pages/course-detail/course-detail?id=${course.id}`
      })
    },
    
    async loadMoreCourses() {
      if (this.loadMoreStatus === 'loading') return
      
      this.loadMoreStatus = 'loading'
      
      try {
        const hasMore = await this.loadCourses({ loadMore: true })
        this.loadMoreStatus = hasMore ? 'more' : 'noMore'
      } catch (error) {
        this.loadMoreStatus = 'more'
        uni.showToast({
          title: '加载失败',
          icon: 'none'
        })
      }
    }
  }
}
</script>

<style scoped>
.courses-container {
  padding: 20rpx;
}

.search-container {
  margin-bottom: 20rpx;
}

.category-container {
  margin-bottom: 30rpx;
}

.course-list {
  margin-bottom: 20rpx;
}

.course-meta {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 24rpx;
  color: #666;
}
</style>
```

### 条件编译实践
```javascript
// 条件编译适配不同平台
// utils/platform.js
export const PlatformUtils = {
  // 获取平台信息
  getPlatform() {
    // #ifdef H5
    return 'h5'
    // #endif
    
    // #ifdef MP-WEIXIN
    return 'weixin'
    // #endif
    
    // #ifdef MP-ALIPAY
    return 'alipay'
    // #endif
    
    // #ifdef APP-PLUS
    return 'app'
    // #endif
  },
  
  // 平台特定API调用
  showToast(title, icon = 'none') {
    // #ifdef MP-WEIXIN
    wx.showToast({ title, icon })
    // #endif
    
    // #ifdef MP-ALIPAY
    my.showToast({ content: title, type: icon })
    // #endif
    
    // #ifdef H5
    // H5端使用自定义toast
    this.showH5Toast(title)
    // #endif
    
    // #ifdef APP-PLUS
    uni.showToast({ title, icon })
    // #endif
  },
  
  // 获取系统信息
  getSystemInfo() {
    return new Promise((resolve) => {
      // #ifdef MP-WEIXIN
      wx.getSystemInfo({
        success: resolve
      })
      // #endif
      
      // #ifdef H5
      resolve({
        platform: 'web',
        screenWidth: window.screen.width,
        screenHeight: window.screen.height
      })
      // #endif
    })
  }
}

// API接口适配
// api/request.js
class RequestAdapter {
  constructor() {
    this.baseURL = this.getBaseURL()
  }
  
  getBaseURL() {
    // #ifdef H5
    return 'https://api.example.com'
    // #endif
    
    // #ifdef MP-WEIXIN
    return 'https://mp-api.example.com'
    // #endif
    
    // #ifdef APP-PLUS
    return 'https://app-api.example.com'
    // #endif
  }
  
  request(options) {
    return new Promise((resolve, reject) => {
      // #ifdef MP-WEIXIN
      wx.request({
        url: this.baseURL + options.url,
        method: options.method || 'GET',
        data: options.data,
        header: {
          'Content-Type': 'application/json',
          ...options.header
        },
        success: (res) => {
          if (res.statusCode === 200) {
            resolve(res.data)
          } else {
            reject(new Error(`请求失败: ${res.statusCode}`))
          }
        },
        fail: reject
      })
      // #endif
      
      // #ifdef H5
      fetch(this.baseURL + options.url, {
        method: options.method || 'GET',
        headers: {
          'Content-Type': 'application/json',
          ...options.header
        },
        body: options.data ? JSON.stringify(options.data) : undefined
      }).then(response => {
        if (response.ok) {
          return response.json()
        }
        throw new Error(`请求失败: ${response.status}`)
      }).then(resolve).catch(reject)
      // #endif
    })
  }
}
```

## 🔬 实验学习方法指导

### 实验前准备策略
```
实验准备checklist
├── 技术准备
│   ├── 复习相关理论知识
│   ├── 确认开发环境就绪
│   ├── 准备必要的开发工具
│   └── 下载实验资料和模板
│
├── 时间规划
│   ├── 阅读实验指导书（30分钟）
│   ├── 环境检查和配置（30分钟）
│   ├── 核心功能开发（2小时）
│   └── 测试调试和文档（1小时）
│
├── 资源准备
│   ├── 官方文档和API参考
│   ├── 相关教程和视频资料
│   ├── 示例代码和项目模板
│   └── 问题解决资源库
│
└── 心理准备
    ├── 设定合理的学习目标
    ├── 准备应对技术挑战
    ├── 建立解决问题的信心
    └── 保持学习的耐心和毅力
```

### 实验中学习技巧
```
高效实验方法
├── 循序渐进策略
│   ├── 先理解需求和目标
│   ├── 分解复杂问题为简单任务
│   ├── 一步一步完成每个功能
│   └── 及时测试验证每个步骤
│
├── 问题解决方法
│   ├── 仔细阅读错误信息
│   ├── 使用调试工具分析问题
│   ├── 查阅官方文档和社区
│   └── 寻求同学和老师帮助
│
├── 代码质量管理
│   ├── 遵循编码规范和最佳实践
│   ├── 添加必要的注释和文档
│   ├── 进行代码重构和优化
│   └── 保持代码结构清晰整洁
│
└── 学习记录习惯
    ├── 记录重要的学习心得
    ├── 整理常见问题和解决方案
    ├── 保存有用的代码片段
    └── 总结实验经验和教训
```

### 实验后总结提升
```
实验总结方法
├── 技术总结
│   ├── 梳理掌握的新技术点
│   ├── 分析技术难点和解决方案
│   ├── 对比不同技术方案的优劣
│   └── 思考技术改进和优化方向
│
├── 能力评估
│   ├── 评估编程能力的提升
│   ├── 分析问题解决能力的进步
│   ├── 反思学习方法的有效性
│   └── 识别需要加强的技能领域
│
├── 经验提取
│   ├── 总结成功的开发经验
│   ├── 分析失败的原因和教训
│   ├── 提取可复用的解决方案
│   └── 形成个人的开发方法论
│
└── 持续改进
    ├── 制定下一阶段学习计划
    ├── 设定更高的技术目标
    ├── 寻找更多的实践机会
    └── 建立持续学习的习惯
```

---

**制定依据**：刘东良教师《移动应用开发学生学习指导手册》  
**适用对象**：移动应用开发课程学生  
**更新时间**：2025年8月  
**版本**：v2.0（基于学生学习指导手册制定）
