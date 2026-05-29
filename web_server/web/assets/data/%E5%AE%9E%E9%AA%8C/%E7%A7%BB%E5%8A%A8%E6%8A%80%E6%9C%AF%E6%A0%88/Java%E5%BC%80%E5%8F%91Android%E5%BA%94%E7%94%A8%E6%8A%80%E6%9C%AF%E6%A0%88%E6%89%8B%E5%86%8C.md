# Java开发Android应用技术栈手册

## 一、技术栈概述

### 1.1 核心技术
- **编程语言**：Java 17
- **开发框架**：Android SDK
- **构建工具**：Gradle
- **IDE**：Android Studio
- **版本要求**：Java 17+, Android 13+ API Level 33+

### 1.2 依赖管理
- **包管理**：Gradle
- **依赖仓库**：Maven Central, Google Maven
- **版本控制**：Git

### 1.3 测试框架
- **单元测试**：JUnit 5, Mockito
- **UI测试**：Espresso, UI Automator
- **集成测试**：AndroidX Test

## 二、环境搭建

### 2.1 开发环境配置
```groovy
// build.gradle (Module级别)
android {
    compileSdk 34
    defaultConfig {
        applicationId "com.example.app"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    buildFeatures {
        viewBinding true
        dataBinding true
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

### 2.2 依赖配置
```groovy
dependencies {
    // AndroidX核心库
    implementation 'androidx.core:core:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    implementation 'androidx.recyclerview:recyclerview:1.3.2'
    implementation 'androidx.cardview:cardview:1.0.0'
    implementation 'androidx.swiperefreshlayout:swiperefreshlayout:1.1.0'

    // Material Design
    implementation 'com.google.android.material:material:1.11.0'

    // Fragment与Navigation
    implementation 'androidx.fragment:fragment:1.6.2'
    implementation 'androidx.navigation:navigation-fragment:2.7.6'
    implementation 'androidx.navigation:navigation-ui:2.7.6'

    // 网络请求
    implementation 'com.squareup.retrofit2:retrofit:2.9.0'
    implementation 'com.squareup.retrofit2:converter-gson:2.9.0'
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
    implementation 'com.squareup.okhttp3:logging-interceptor:4.12.0'

    // JSON解析
    implementation 'com.google.code.gson:gson:2.10.1'

    // 图片加载
    implementation 'com.github.bumptech.glide:glide:4.16.0'
    annotationProcessor 'com.github.bumptech.glide:compiler:4.16.0'

    // ViewModel和LiveData
    implementation 'androidx.lifecycle:lifecycle-viewmodel:2.6.2'
    implementation 'androidx.lifecycle:lifecycle-livedata:2.6.2'
    implementation 'androidx.lifecycle:lifecycle-runtime:2.6.2'

    // Room数据库
    implementation 'androidx.room:room-runtime:2.6.1'
    annotationProcessor 'androidx.room:room-compiler:2.6.1'

    // 测试依赖
    testImplementation 'junit:junit:4.13.2'
    testImplementation 'org.mockito:mockito-core:5.8.0'
    androidTestImplementation 'androidx.test.ext:junit:1.1.5'
    androidTestImplementation 'androidx.test.espresso:espresso-core:3.5.1'
    androidTestImplementation 'androidx.test:runner:1.5.2'
    androidTestImplementation 'androidx.test:rules:1.5.0'
}
```

## 三、基础语法与特性

### 3.1 Java基础语法

#### 3.1.1 变量声明
```java
// 基本类型
int age = 25;
double salary = 8500.0;
boolean isActive = true;
char grade = 'A';

// 引用类型
String name = "张三";
String message = "Hello Java"; // 类型明确

// Java 10+ 局部变量类型推断
var count = 0;        // 推断为int
var list = new ArrayList<String>(); // 推断为ArrayList<String>

// final：不可变变量（类似Kotlin的val）
final String APP_NAME = "智慧校园";
final int MAX_RETRY = 3;
```

#### 3.1.2 函数定义
```java
// 基本方法
public String greet(String name) {
    return "你好，" + name;
}

// 方法重载（Java不支持默认参数，用重载替代）
public void createUser(String name) {
    createUser(name, 18);
}

public void createUser(String name, int age) {
    System.out.println("创建用户：" + name + "，年龄：" + age);
}

// 可变参数
public int sumAll(int... numbers) {
    int sum = 0;
    for (int num : numbers) {
        sum += num;
    }
    return sum;
}

// Lambda表达式（Java 8+）
BiFunction<Integer, Integer, Integer> add = (a, b) -> a + b;
int result = add.apply(3, 5);

// 方法引用
List<String> names = Arrays.asList("张三", "李四", "王五");
names.forEach(System.out::println);
```

#### 3.1.3 数据类（Record，Java 16+）
```java
// Java Record自动生成equals()、hashCode()、toString()等方法
public record User(int id, String name, String email, int age) {}

// 使用Record
User user = new User(1, "李四", "lisi@example.com", 30);
System.out.println(user.name()); // 输出：李四

// 传统JavaBean写法（兼容旧版本）
public class Student {
    private int id;
    private String name;
    private String email;
    private int age;

    public Student(int id, String name, String email, int age) {
        this.id = id;
        this.name = name;
        this.email = email;
        this.age = age;
    }

    // Getter方法
    public int getId() { return id; }
    public String getName() { return name; }
    public String getEmail() { return email; }
    public int getAge() { return age; }

    // Setter方法
    public void setName(String name) { this.name = name; }
    public void setEmail(String email) { this.email = email; }
    public void setAge(int age) { this.age = age; }

    @Override
    public String toString() {
        return "Student{id=" + id + ", name='" + name + "'}";
    }
}
```

#### 3.1.4 空安全处理
```java
// Java没有内建空安全，需要手动处理

// Optional类（Java 8+）
Optional<String> name = Optional.ofNullable(getUserName());
int length = name.map(String::length).orElse(0);

// Optional的orElse替代Kotlin的Elvis操作符
String displayName = name.orElse("匿名用户");

// Optional的ifPresent替代Kotlin的let
name.ifPresent(n -> {
    System.out.println("名字长度：" + n.length());
});

// @Nullable和@NonNull注解（AndroidX）
public void setUser(@Nullable String name, @NonNull String email) {
    if (name != null) {
        // 安全使用name
        System.out.println("用户名：" + name);
    }
}

// Objects.requireNonNull检查
String validName = Objects.requireNonNull(name.orElse(null), "名字不能为空");
```

### 3.2 Java高级特性

#### 3.2.1 集合操作与Stream API
```java
// 创建集合
List<Integer> numbers = List.of(1, 2, 3, 4, 5);
Map<String, Integer> scores = Map.of("张三", 95, "李四", 88, "王五", 72);

// Stream API：map转换
List<Integer> doubled = numbers.stream()
        .map(n -> n * 2)
        .collect(Collectors.toList()); // [2, 4, 6, 8, 10]

// Stream API：filter过滤
List<Integer> evenNumbers = numbers.stream()
        .filter(n -> n % 2 == 0)
        .collect(Collectors.toList()); // [2, 4]

// Stream API：reduce聚合
int sum = numbers.stream()
        .reduce(0, Integer::sum); // 15

// 链式操作
String result = scores.entrySet().stream()
        .filter(e -> e.getValue() >= 80)
        .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
        .map(e -> e.getKey() + ":" + e.getValue())
        .collect(Collectors.joining(", ")); // "张三:95, 李四:88"
```

#### 3.2.2 接口与函数式编程
```java
// 函数式接口
@FunctionalInterface
public interface DataCallback<T> {
    void onResult(T data);
}

// 使用Lambda实现回调
public void loadData(DataCallback<List<User>> callback) {
    ExecutorService executor = Executors.newSingleThreadExecutor();
    executor.execute(() -> {
        List<User> users = fetchUsersFromNetwork();
        callback.onResult(users);
    });
}

// 调用
loadData(users -> {
    runOnUiThread(() -> {
        adapter.updateData(users);
    });
});
```

#### 3.2.3 Java并发（替代Kotlin协程）
```java
// ExecutorService线程池
ExecutorService executor = Executors.newFixedThreadPool(4);

// 提交异步任务
Future<List<User>> future = executor.submit(() -> {
    return api.getUsers();  // 在后台线程执行
});

// CompletableFuture链式异步（Java 8+）
CompletableFuture.supplyAsync(() -> {
    // 在后台线程执行网络请求
    return api.getUsers();
}, executor).thenAcceptAsync(users -> {
    // 切换到主线程更新UI
    runOnUiThread(() -> updateUI(users));
}).exceptionally(throwable -> {
    Log.e("TAG", "加载失败", throwable);
    return null;
});

// 多任务并行
CompletableFuture<List<User>> usersFuture = CompletableFuture.supplyAsync(() -> api.getUsers());
CompletableFuture<List<Course>> coursesFuture = CompletableFuture.supplyAsync(() -> api.getCourses());

CompletableFuture.allOf(usersFuture, coursesFuture).thenRun(() -> {
    List<User> users = usersFuture.join();
    List<Course> courses = coursesFuture.join();
    runOnUiThread(() -> displayData(users, courses));
});
```

## 四、Android UI开发

### 4.1 XML布局基础

#### 4.1.1 常用布局
```xml
<!-- activity_main.xml -->
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="16dp">

    <!-- 标题文本 -->
    <TextView
        android:id="@+id/tvTitle"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="智慧校园"
        android:textSize="24sp"
        android:textStyle="bold"
        android:textColor="@color/primary"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintStart_toStartOf="parent" />

    <!-- 搜索框 -->
    <com.google.android.material.textfield.TextInputLayout
        android:id="@+id/tilSearch"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        style="@style/Widget.MaterialComponents.TextInputLayout.OutlinedBox"
        app:startIconDrawable="@drawable/ic_search"
        app:layout_constraintTop_toBottomOf="@id/tvTitle"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent">

        <com.google.android.material.textfield.TextInputEditText
            android:id="@+id/etSearch"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="搜索课程或学生..." />
    </com.google.android.material.textfield.TextInputLayout>

    <!-- 列表 -->
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/rvContent"
        android:layout_width="0dp"
        android:layout_height="0dp"
        android:layout_marginTop="16dp"
        app:layoutManager="androidx.recyclerview.widget.LinearLayoutManager"
        app:layout_constraintTop_toBottomOf="@id/tilSearch"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent" />

</androidx.constraintlayout.widget.ConstraintLayout>
```

#### 4.1.2 列表项布局
```xml
<!-- item_student.xml -->
<?xml version="1.0" encoding="utf-8"?>
<com.google.android.material.card.MaterialCardView
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_margin="4dp"
    app:cardElevation="4dp"
    app:cardCornerRadius="12dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:padding="16dp"
        android:gravity="center_vertical">

        <!-- 头像 -->
        <ImageView
            android:id="@+id/ivAvatar"
            android:layout_width="56dp"
            android:layout_height="56dp"
            android:scaleType="centerCrop"
            android:src="@drawable/ic_person" />

        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="16dp"
            android:orientation="vertical">

            <TextView
                android:id="@+id/tvName"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:textSize="16sp"
                android:textStyle="bold" />

            <TextView
                android:id="@+id/tvEmail"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:textSize="14sp"
                android:textColor="@android:color/darker_gray"
                android:layout_marginTop="4dp" />
        </LinearLayout>

        <!-- 状态标签 -->
        <TextView
            android:id="@+id/tvStatus"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:paddingHorizontal="12dp"
            android:paddingVertical="4dp"
            android:textSize="12sp"
            android:textColor="@android:color/white"
            android:background="@drawable/bg_status_badge" />
    </LinearLayout>
</com.google.android.material.card.MaterialCardView>
```

### 4.2 ViewBinding与Activity

#### 4.2.1 Activity中使用ViewBinding
```java
public class MainActivity extends AppCompatActivity {
    private ActivityMainBinding binding;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        setupViews();
        setupRecyclerView();
    }

    private void setupViews() {
        // 直接通过binding访问视图，无需findViewById
        binding.tvTitle.setText("智慧校园管理系统");

        binding.etSearch.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                filterStudents(s.toString());
            }

            @Override
            public void afterTextChanged(Editable s) {}
        });
    }

    private void setupRecyclerView() {
        StudentAdapter adapter = new StudentAdapter(this::onStudentClick);
        binding.rvContent.setLayoutManager(new LinearLayoutManager(this));
        binding.rvContent.setAdapter(adapter);
    }

    private void onStudentClick(Student student) {
        Intent intent = new Intent(this, StudentDetailActivity.class);
        intent.putExtra("student_id", student.getId());
        startActivity(intent);
    }

    private void filterStudents(String query) {
        // 过滤学生列表
    }
}
```

### 4.3 RecyclerView适配器

#### 4.3.1 标准Adapter实现
```java
public class StudentAdapter extends RecyclerView.Adapter<StudentAdapter.ViewHolder> {
    private List<Student> students = new ArrayList<>();
    private final Consumer<Student> onItemClick;

    public StudentAdapter(Consumer<Student> onItemClick) {
        this.onItemClick = onItemClick;
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        ItemStudentBinding binding = ItemStudentBinding.inflate(
                LayoutInflater.from(parent.getContext()), parent, false);
        return new ViewHolder(binding);
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
        Student student = students.get(position);
        holder.bind(student);
    }

    @Override
    public int getItemCount() {
        return students.size();
    }

    public void updateData(List<Student> newStudents) {
        DiffUtil.DiffResult diffResult = DiffUtil.calculateDiff(
                new StudentDiffCallback(students, newStudents));
        students = new ArrayList<>(newStudents);
        diffResult.dispatchUpdatesTo(this);
    }

    class ViewHolder extends RecyclerView.ViewHolder {
        private final ItemStudentBinding binding;

        ViewHolder(ItemStudentBinding binding) {
            super(binding.getRoot());
            this.binding = binding;
        }

        void bind(Student student) {
            binding.tvName.setText(student.getName());
            binding.tvEmail.setText(student.getEmail());
            binding.tvStatus.setText(student.isActive() ? "在读" : "休学");

            // Glide加载头像
            Glide.with(binding.ivAvatar.getContext())
                    .load(student.getAvatarUrl())
                    .placeholder(R.drawable.ic_person)
                    .circleCrop()
                    .into(binding.ivAvatar);

            binding.getRoot().setOnClickListener(v -> onItemClick.accept(student));
        }
    }

    // DiffUtil提升列表更新性能
    static class StudentDiffCallback extends DiffUtil.Callback {
        private final List<Student> oldList;
        private final List<Student> newList;

        StudentDiffCallback(List<Student> oldList, List<Student> newList) {
            this.oldList = oldList;
            this.newList = newList;
        }

        @Override
        public int getOldListSize() { return oldList.size(); }

        @Override
        public int getNewListSize() { return newList.size(); }

        @Override
        public boolean areItemsTheSame(int oldPos, int newPos) {
            return oldList.get(oldPos).getId() == newList.get(newPos).getId();
        }

        @Override
        public boolean areContentsTheSame(int oldPos, int newPos) {
            return oldList.get(oldPos).equals(newList.get(newPos));
        }
    }
}
```

### 4.4 Fragment与导航

#### 4.4.1 Fragment实现
```java
public class CourseListFragment extends Fragment {
    private FragmentCourseListBinding binding;
    private CourseViewModel viewModel;

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater,
                             ViewGroup container, Bundle savedInstanceState) {
        binding = FragmentCourseListBinding.inflate(inflater, container, false);
        return binding.getRoot();
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);
        viewModel = new ViewModelProvider(this).get(CourseViewModel.class);

        setupRecyclerView();
        observeData();
        viewModel.loadCourses();
    }

    private void setupRecyclerView() {
        CourseAdapter adapter = new CourseAdapter(course -> {
            // 使用Navigation组件跳转
            Bundle args = new Bundle();
            args.putInt("courseId", course.getId());
            NavHostFragment.findNavController(this)
                    .navigate(R.id.action_courseList_to_courseDetail, args);
        });
        binding.rvCourses.setLayoutManager(new LinearLayoutManager(requireContext()));
        binding.rvCourses.setAdapter(adapter);
    }

    private void observeData() {
        viewModel.getCourses().observe(getViewLifecycleOwner(), courses -> {
            ((CourseAdapter) binding.rvCourses.getAdapter()).updateData(courses);
        });

        viewModel.getIsLoading().observe(getViewLifecycleOwner(), isLoading -> {
            binding.progressBar.setVisibility(isLoading ? View.VISIBLE : View.GONE);
        });
    }

    @Override
    public void onDestroyView() {
        super.onDestroyView();
        binding = null; // 防止内存泄漏
    }
}
```

#### 4.4.2 Navigation导航图
```xml
<!-- res/navigation/nav_graph.xml -->
<?xml version="1.0" encoding="utf-8"?>
<navigation xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:id="@+id/nav_graph"
    app:startDestination="@id/homeFragment">

    <fragment
        android:id="@+id/homeFragment"
        android:name="com.example.app.ui.HomeFragment"
        android:label="首页">
        <action
            android:id="@+id/action_home_to_courseList"
            app:destination="@id/courseListFragment" />
    </fragment>

    <fragment
        android:id="@+id/courseListFragment"
        android:name="com.example.app.ui.CourseListFragment"
        android:label="课程列表">
        <action
            android:id="@+id/action_courseList_to_courseDetail"
            app:destination="@id/courseDetailFragment" />
    </fragment>

    <fragment
        android:id="@+id/courseDetailFragment"
        android:name="com.example.app.ui.CourseDetailFragment"
        android:label="课程详情">
        <argument
            android:name="courseId"
            app:argType="integer" />
    </fragment>
</navigation>
```

### 4.5 Material Design组件

#### 4.5.1 底部导航栏
```xml
<!-- activity_main.xml 底部导航 -->
<com.google.android.material.bottomnavigation.BottomNavigationView
    android:id="@+id/bottomNav"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    app:menu="@menu/bottom_nav_menu"
    app:layout_constraintBottom_toBottomOf="parent" />
```

```xml
<!-- res/menu/bottom_nav_menu.xml -->
<menu xmlns:android="http://schemas.android.com/apk/res/android">
    <item
        android:id="@+id/nav_home"
        android:icon="@drawable/ic_home"
        android:title="首页" />
    <item
        android:id="@+id/nav_courses"
        android:icon="@drawable/ic_book"
        android:title="课程" />
    <item
        android:id="@+id/nav_lab"
        android:icon="@drawable/ic_lab"
        android:title="实验" />
    <item
        android:id="@+id/nav_profile"
        android:icon="@drawable/ic_person"
        android:title="我的" />
</menu>
```

```java
// 在Activity中设置底部导航
private void setupBottomNavigation() {
    NavController navController = Navigation.findNavController(this, R.id.nav_host_fragment);
    NavigationUI.setupWithNavController(binding.bottomNav, navController);

    binding.bottomNav.setOnItemSelectedListener(item -> {
        int id = item.getItemId();
        if (id == R.id.nav_home) {
            navController.navigate(R.id.homeFragment);
        } else if (id == R.id.nav_courses) {
            navController.navigate(R.id.courseListFragment);
        } else if (id == R.id.nav_lab) {
            navController.navigate(R.id.labFragment);
        } else if (id == R.id.nav_profile) {
            navController.navigate(R.id.profileFragment);
        }
        return true;
    });
}
```

#### 4.5.2 Material对话框与Snackbar
```java
// Material对话框
private void showDeleteConfirmDialog(Student student) {
    new MaterialAlertDialogBuilder(this)
            .setTitle("确认删除")
            .setMessage("是否确认删除学生 " + student.getName() + " 的记录？")
            .setIcon(R.drawable.ic_warning)
            .setPositiveButton("删除", (dialog, which) -> {
                viewModel.deleteStudent(student);
            })
            .setNegativeButton("取消", null)
            .show();
}

// Snackbar提示
private void showUndoSnackbar(Student student) {
    Snackbar.make(binding.getRoot(), "已删除 " + student.getName(), Snackbar.LENGTH_LONG)
            .setAction("撤销", v -> {
                viewModel.restoreStudent(student);
            })
            .setActionTextColor(getColor(R.color.primary))
            .show();
}
```

## 五、MVP/MVVM架构实战

### 5.1 MVVM架构

#### 5.1.1 ViewModel实现
```java
public class StudentViewModel extends ViewModel {
    // LiveData用于UI观察数据变化
    private final MutableLiveData<List<Student>> students = new MutableLiveData<>();
    private final MutableLiveData<Boolean> isLoading = new MutableLiveData<>(false);
    private final MutableLiveData<String> errorMessage = new MutableLiveData<>();

    private final StudentRepository repository;
    private final ExecutorService executor = Executors.newFixedThreadPool(2);

    public StudentViewModel() {
        repository = StudentRepository.getInstance();
    }

    // 对外暴露不可变的LiveData
    public LiveData<List<Student>> getStudents() { return students; }
    public LiveData<Boolean> getIsLoading() { return isLoading; }
    public LiveData<String> getErrorMessage() { return errorMessage; }

    public void loadStudents() {
        isLoading.setValue(true);

        CompletableFuture.supplyAsync(() -> {
            return repository.getAllStudents();
        }, executor).thenAccept(result -> {
            students.postValue(result);
            isLoading.postValue(false);
        }).exceptionally(throwable -> {
            errorMessage.postValue("加载学生列表失败：" + throwable.getMessage());
            isLoading.postValue(false);
            return null;
        });
    }

    public void addStudent(Student student) {
        CompletableFuture.runAsync(() -> {
            repository.insertStudent(student);
        }, executor).thenRun(() -> {
            loadStudents(); // 重新加载列表
        });
    }

    public void deleteStudent(Student student) {
        CompletableFuture.runAsync(() -> {
            repository.deleteStudent(student);
        }, executor).thenRun(() -> {
            loadStudents();
        });
    }

    @Override
    protected void onCleared() {
        super.onCleared();
        executor.shutdown();
    }
}
```

#### 5.1.2 Repository模式
```java
public class StudentRepository {
    private static volatile StudentRepository instance;
    private final StudentApi api;
    private final StudentDao dao;

    private StudentRepository(StudentApi api, StudentDao dao) {
        this.api = api;
        this.dao = dao;
    }

    public static StudentRepository getInstance() {
        if (instance == null) {
            synchronized (StudentRepository.class) {
                if (instance == null) {
                    instance = new StudentRepository(
                            RetrofitClient.getInstance().create(StudentApi.class),
                            AppDatabase.getInstance().studentDao()
                    );
                }
            }
        }
        return instance;
    }

    public List<Student> getAllStudents() {
        try {
            // 优先从网络获取
            Response<List<Student>> response = api.getStudents().execute();
            if (response.isSuccessful() && response.body() != null) {
                List<Student> students = response.body();
                // 缓存到本地数据库
                dao.insertAll(students);
                return students;
            }
        } catch (IOException e) {
            Log.w("StudentRepo", "网络请求失败，使用本地缓存", e);
        }
        // 网络失败时从本地数据库读取
        return dao.getAllStudents();
    }

    public void insertStudent(Student student) {
        dao.insert(student);
        // 异步同步到服务器
        try {
            api.addStudent(student).execute();
        } catch (IOException e) {
            Log.w("StudentRepo", "同步失败", e);
        }
    }

    public void deleteStudent(Student student) {
        dao.delete(student);
    }
}
```

### 5.2 MVP架构

#### 5.2.1 Contract定义
```java
// 契约接口，定义View和Presenter的职责
public interface CourseContract {

    interface View {
        void showCourses(List<Course> courses);
        void showLoading();
        void hideLoading();
        void showError(String message);
        void navigateToCourseDetail(int courseId);
    }

    interface Presenter {
        void loadCourses();
        void onCourseClick(Course course);
        void onDestroy();
    }
}
```

#### 5.2.2 Presenter实现
```java
public class CoursePresenter implements CourseContract.Presenter {
    private CourseContract.View view;
    private final CourseRepository repository;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    public CoursePresenter(CourseContract.View view) {
        this.view = view;
        this.repository = CourseRepository.getInstance();
    }

    @Override
    public void loadCourses() {
        if (view == null) return;
        view.showLoading();

        CompletableFuture.supplyAsync(() -> {
            return repository.getAllCourses();
        }, executor).thenAccept(courses -> {
            if (view != null) {
                // 切换到主线程
                new Handler(Looper.getMainLooper()).post(() -> {
                    view.hideLoading();
                    view.showCourses(courses);
                });
            }
        }).exceptionally(throwable -> {
            if (view != null) {
                new Handler(Looper.getMainLooper()).post(() -> {
                    view.hideLoading();
                    view.showError("加载课程失败：" + throwable.getMessage());
                });
            }
            return null;
        });
    }

    @Override
    public void onCourseClick(Course course) {
        if (view != null) {
            view.navigateToCourseDetail(course.getId());
        }
    }

    @Override
    public void onDestroy() {
        view = null;
        executor.shutdown();
    }
}
```

#### 5.2.3 View层实现
```java
public class CourseActivity extends AppCompatActivity implements CourseContract.View {
    private ActivityCourseBinding binding;
    private CoursePresenter presenter;
    private CourseAdapter adapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityCourseBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        presenter = new CoursePresenter(this);
        adapter = new CourseAdapter(course -> presenter.onCourseClick(course));
        binding.rvCourses.setLayoutManager(new LinearLayoutManager(this));
        binding.rvCourses.setAdapter(adapter);

        presenter.loadCourses();
    }

    @Override
    public void showCourses(List<Course> courses) {
        adapter.updateData(courses);
    }

    @Override
    public void showLoading() {
        binding.progressBar.setVisibility(View.VISIBLE);
    }

    @Override
    public void hideLoading() {
        binding.progressBar.setVisibility(View.GONE);
    }

    @Override
    public void showError(String message) {
        Snackbar.make(binding.getRoot(), message, Snackbar.LENGTH_LONG).show();
    }

    @Override
    public void navigateToCourseDetail(int courseId) {
        Intent intent = new Intent(this, CourseDetailActivity.class);
        intent.putExtra("course_id", courseId);
        startActivity(intent);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        presenter.onDestroy();
    }
}
```

### 5.3 网络请求

#### 5.3.1 Retrofit配置
```java
public interface StudentApi {
    @GET("students")
    Call<List<Student>> getStudents();

    @GET("students/{id}")
    Call<Student> getStudent(@Path("id") int studentId);

    @POST("students")
    Call<Student> addStudent(@Body Student student);

    @PUT("students/{id}")
    Call<Student> updateStudent(@Path("id") int studentId, @Body Student student);

    @DELETE("students/{id}")
    Call<Void> deleteStudent(@Path("id") int studentId);
}

public class RetrofitClient {
    private static final String BASE_URL = "https://api.example.com/";
    private static volatile Retrofit instance;

    public static Retrofit getInstance() {
        if (instance == null) {
            synchronized (RetrofitClient.class) {
                if (instance == null) {
                    // 日志拦截器（调试用）
                    HttpLoggingInterceptor loggingInterceptor = new HttpLoggingInterceptor();
                    loggingInterceptor.setLevel(HttpLoggingInterceptor.Level.BODY);

                    OkHttpClient client = new OkHttpClient.Builder()
                            .connectTimeout(30, TimeUnit.SECONDS)
                            .readTimeout(30, TimeUnit.SECONDS)
                            .writeTimeout(30, TimeUnit.SECONDS)
                            .addInterceptor(loggingInterceptor)
                            .addInterceptor(chain -> {
                                // 添加公共请求头
                                Request request = chain.request().newBuilder()
                                        .addHeader("Content-Type", "application/json")
                                        .addHeader("Accept", "application/json")
                                        .build();
                                return chain.proceed(request);
                            })
                            .build();

                    instance = new Retrofit.Builder()
                            .baseUrl(BASE_URL)
                            .client(client)
                            .addConverterFactory(GsonConverterFactory.create())
                            .build();
                }
            }
        }
        return instance;
    }
}
```

#### 5.3.2 数据解析（Gson）
```java
// Gson数据类
public class Student {
    @SerializedName("id")
    private int id;

    @SerializedName("name")
    private String name;

    @SerializedName("email")
    private String email;

    @SerializedName("age")
    private int age;

    @SerializedName("avatar_url")
    private String avatarUrl;

    @SerializedName("is_active")
    private boolean isActive;

    // 构造方法
    public Student(int id, String name, String email, int age) {
        this.id = id;
        this.name = name;
        this.email = email;
        this.age = age;
    }

    // Getter和Setter
    public int getId() { return id; }
    public String getName() { return name; }
    public String getEmail() { return email; }
    public int getAge() { return age; }
    public String getAvatarUrl() { return avatarUrl; }
    public boolean isActive() { return isActive; }
}
```

### 5.4 Room数据库

#### 5.4.1 实体定义
```java
@Entity(tableName = "students")
public class StudentEntity {
    @PrimaryKey(autoGenerate = true)
    private int id;

    @ColumnInfo(name = "name")
    private String name;

    @ColumnInfo(name = "email")
    private String email;

    @ColumnInfo(name = "age")
    private int age;

    @ColumnInfo(name = "created_at")
    private long createdAt;

    // 构造方法、Getter、Setter省略
}
```

#### 5.4.2 DAO接口
```java
@Dao
public interface StudentDao {
    @Query("SELECT * FROM students ORDER BY name ASC")
    List<StudentEntity> getAllStudents();

    @Query("SELECT * FROM students WHERE id = :studentId")
    StudentEntity getStudentById(int studentId);

    @Query("SELECT * FROM students WHERE name LIKE '%' || :query || '%'")
    List<StudentEntity> searchStudents(String query);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    void insertAll(List<StudentEntity> students);

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    long insert(StudentEntity student);

    @Update
    void update(StudentEntity student);

    @Delete
    void delete(StudentEntity student);

    @Query("DELETE FROM students")
    void deleteAll();
}
```

#### 5.4.3 数据库配置
```java
@Database(entities = {StudentEntity.class, CourseEntity.class}, version = 1, exportSchema = false)
public abstract class AppDatabase extends RoomDatabase {
    private static volatile AppDatabase instance;

    public abstract StudentDao studentDao();
    public abstract CourseDao courseDao();

    public static AppDatabase getInstance(Context context) {
        if (instance == null) {
            synchronized (AppDatabase.class) {
                if (instance == null) {
                    instance = Room.databaseBuilder(
                            context.getApplicationContext(),
                            AppDatabase.class,
                            "smart_campus.db"
                    )
                    .addMigrations(MIGRATION_1_2)
                    .fallbackToDestructiveMigration()
                    .build();
                }
            }
        }
        return instance;
    }

    // 数据库版本迁移
    static final Migration MIGRATION_1_2 = new Migration(1, 2) {
        @Override
        public void migrate(@NonNull SupportSQLiteDatabase database) {
            database.execSQL("ALTER TABLE students ADD COLUMN phone TEXT DEFAULT ''");
        }
    };
}
```

## 六、项目实战案例

### 6.1 项目：智慧校园管理系统

#### 6.1.1 项目概述
开发一个面向高校师生的智慧校园管理应用，包含课程管理、成绩查询、课表展示、校园通知、实验室预约等功能，采用Java + XML布局 + MVVM架构。

#### 6.1.2 核心功能实现

**课表展示功能**
```xml
<!-- fragment_schedule.xml -->
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">

    <!-- 周选择器 -->
    <com.google.android.material.tabs.TabLayout
        android:id="@+id/tabWeekdays"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        app:tabMode="fixed"
        app:tabGravity="fill" />

    <!-- 课表网格 -->
    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/rvSchedule"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:padding="8dp" />
</LinearLayout>
```

```java
public class ScheduleFragment extends Fragment {
    private FragmentScheduleBinding binding;
    private ScheduleViewModel viewModel;
    private ScheduleAdapter adapter;

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater,
                             ViewGroup container, Bundle savedInstanceState) {
        binding = FragmentScheduleBinding.inflate(inflater, container, false);
        return binding.getRoot();
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);
        viewModel = new ViewModelProvider(this).get(ScheduleViewModel.class);

        setupWeekTabs();
        setupScheduleGrid();
        observeData();
        viewModel.loadSchedule(1); // 加载第一周课表
    }

    private void setupWeekTabs() {
        String[] weekdays = {"周一", "周二", "周三", "周四", "周五", "周六", "周日"};
        for (String day : weekdays) {
            binding.tabWeekdays.addTab(binding.tabWeekdays.newTab().setText(day));
        }
        binding.tabWeekdays.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override
            public void onTabSelected(TabLayout.Tab tab) {
                viewModel.filterByDay(tab.getPosition());
            }
            @Override public void onTabUnselected(TabLayout.Tab tab) {}
            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });
    }

    private void setupScheduleGrid() {
        adapter = new ScheduleAdapter(course -> {
            showCourseDetailDialog(course);
        });
        binding.rvSchedule.setLayoutManager(new GridLayoutManager(requireContext(), 1));
        binding.rvSchedule.setAdapter(adapter);
    }

    private void observeData() {
        viewModel.getScheduleItems().observe(getViewLifecycleOwner(), items -> {
            adapter.updateData(items);
        });
    }

    private void showCourseDetailDialog(ScheduleItem item) {
        new MaterialAlertDialogBuilder(requireContext())
                .setTitle(item.getCourseName())
                .setMessage("教师：" + item.getTeacher()
                        + "\n教室：" + item.getClassroom()
                        + "\n时间：第" + item.getStartPeriod() + "-" + item.getEndPeriod() + "节")
                .setPositiveButton("确定", null)
                .show();
    }
}
```

**成绩查询功能**
```java
public class GradeViewModel extends ViewModel {
    private final MutableLiveData<List<GradeItem>> grades = new MutableLiveData<>();
    private final MutableLiveData<GradeSummary> summary = new MutableLiveData<>();
    private final GradeRepository repository = GradeRepository.getInstance();
    private final ExecutorService executor = Executors.newFixedThreadPool(2);

    public LiveData<List<GradeItem>> getGrades() { return grades; }
    public LiveData<GradeSummary> getSummary() { return summary; }

    public void loadGrades(String semester) {
        CompletableFuture.supplyAsync(() -> {
            return repository.getGradesBySemester(semester);
        }, executor).thenAccept(gradeList -> {
            grades.postValue(gradeList);
            // 计算汇总信息
            summary.postValue(calculateSummary(gradeList));
        });
    }

    private GradeSummary calculateSummary(List<GradeItem> gradeList) {
        double totalCredits = 0;
        double totalPoints = 0;

        for (GradeItem grade : gradeList) {
            totalCredits += grade.getCredits();
            totalPoints += grade.getCredits() * grade.getGradePoint();
        }

        double gpa = totalCredits > 0 ? totalPoints / totalCredits : 0;
        int passCount = (int) gradeList.stream()
                .filter(g -> g.getScore() >= 60)
                .count();

        return new GradeSummary(gpa, totalCredits, passCount, gradeList.size());
    }
}

// 成绩汇总数据
public class GradeSummary {
    private final double gpa;
    private final double totalCredits;
    private final int passCount;
    private final int totalCount;

    public GradeSummary(double gpa, double totalCredits, int passCount, int totalCount) {
        this.gpa = gpa;
        this.totalCredits = totalCredits;
        this.passCount = passCount;
        this.totalCount = totalCount;
    }

    public double getGpa() { return gpa; }
    public double getTotalCredits() { return totalCredits; }
    public double getPassRate() {
        return totalCount > 0 ? (double) passCount / totalCount * 100 : 0;
    }
}
```

**校园通知功能**
```java
public class NotificationFragment extends Fragment {
    private FragmentNotificationBinding binding;
    private NotificationViewModel viewModel;

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);
        viewModel = new ViewModelProvider(this).get(NotificationViewModel.class);

        setupSwipeRefresh();
        setupNotificationList();
        observeData();
    }

    private void setupSwipeRefresh() {
        binding.swipeRefresh.setColorSchemeColors(
                getResources().getColor(R.color.primary, null));
        binding.swipeRefresh.setOnRefreshListener(() -> {
            viewModel.refreshNotifications();
        });
    }

    private void setupNotificationList() {
        NotificationAdapter adapter = new NotificationAdapter(notification -> {
            // 标记为已读
            viewModel.markAsRead(notification.getId());
            // 跳转到详情页
            Intent intent = new Intent(requireContext(), NotificationDetailActivity.class);
            intent.putExtra("notification_id", notification.getId());
            startActivity(intent);
        });

        binding.rvNotifications.setLayoutManager(new LinearLayoutManager(requireContext()));
        binding.rvNotifications.setAdapter(adapter);

        // 添加分割线
        binding.rvNotifications.addItemDecoration(
                new DividerItemDecoration(requireContext(), DividerItemDecoration.VERTICAL));
    }

    private void observeData() {
        viewModel.getNotifications().observe(getViewLifecycleOwner(), notifications -> {
            ((NotificationAdapter) binding.rvNotifications.getAdapter())
                    .updateData(notifications);
            binding.swipeRefresh.setRefreshing(false);
        });
    }
}
```

#### 6.1.3 AI功能集成

**AI学习助手**
```java
public class AiAssistantActivity extends AppCompatActivity {
    private ActivityAiAssistantBinding binding;
    private ChatAdapter chatAdapter;
    private final List<ChatMessage> messages = new ArrayList<>();
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        binding = ActivityAiAssistantBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        setupChatList();
        setupInputArea();

        // 添加欢迎消息
        addMessage(new ChatMessage("assistant", "你好！我是智慧校园AI助手，请问有什么可以帮你的？"));
    }

    private void setupChatList() {
        chatAdapter = new ChatAdapter(messages);
        binding.rvChat.setLayoutManager(new LinearLayoutManager(this));
        binding.rvChat.setAdapter(chatAdapter);
    }

    private void setupInputArea() {
        binding.btnSend.setOnClickListener(v -> {
            String userInput = binding.etInput.getText().toString().trim();
            if (!userInput.isEmpty()) {
                sendMessage(userInput);
                binding.etInput.setText("");
            }
        });
    }

    private void sendMessage(String content) {
        // 显示用户消息
        addMessage(new ChatMessage("user", content));
        // 显示加载状态
        binding.progressBar.setVisibility(View.VISIBLE);

        CompletableFuture.supplyAsync(() -> {
            return AiService.getInstance().chat(content);
        }, executor).thenAccept(response -> {
            runOnUiThread(() -> {
                binding.progressBar.setVisibility(View.GONE);
                addMessage(new ChatMessage("assistant", response));
            });
        }).exceptionally(throwable -> {
            runOnUiThread(() -> {
                binding.progressBar.setVisibility(View.GONE);
                addMessage(new ChatMessage("assistant", "抱歉，我暂时无法回答，请稍后再试。"));
            });
            return null;
        });
    }

    private void addMessage(ChatMessage message) {
        messages.add(message);
        chatAdapter.notifyItemInserted(messages.size() - 1);
        binding.rvChat.scrollToPosition(messages.size() - 1);
    }
}

// AI服务封装
public class AiService {
    private static volatile AiService instance;
    private final OkHttpClient client;
    private static final String API_URL = "https://api.deepseek.com/v1/chat/completions";

    private AiService() {
        client = new OkHttpClient.Builder()
                .connectTimeout(60, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .build();
    }

    public static AiService getInstance() {
        if (instance == null) {
            synchronized (AiService.class) {
                if (instance == null) {
                    instance = new AiService();
                }
            }
        }
        return instance;
    }

    public String chat(String userMessage) throws IOException {
        JsonObject message = new JsonObject();
        message.addProperty("role", "user");
        message.addProperty("content", userMessage);

        JsonArray messagesArray = new JsonArray();
        messagesArray.add(message);

        JsonObject requestBody = new JsonObject();
        requestBody.addProperty("model", "deepseek-chat");
        requestBody.add("messages", messagesArray);

        Request request = new Request.Builder()
                .url(API_URL)
                .addHeader("Authorization", "Bearer " + getApiKey())
                .post(RequestBody.create(
                        requestBody.toString(),
                        MediaType.parse("application/json")))
                .build();

        try (Response response = client.newCall(request).execute()) {
            if (response.isSuccessful() && response.body() != null) {
                JsonObject json = JsonParser.parseString(response.body().string()).getAsJsonObject();
                return json.getAsJsonArray("choices")
                        .get(0).getAsJsonObject()
                        .getAsJsonObject("message")
                        .get("content").getAsString();
            }
            return "请求失败：" + response.code();
        }
    }

    private String getApiKey() {
        // 从安全配置中获取API Key
        return BuildConfig.AI_API_KEY;
    }
}
```

## 七、测试与调试

### 7.1 单元测试（JUnit + Mockito）

```java
@RunWith(MockitoJUnitRunner.class)
public class StudentViewModelTest {

    @Rule
    public InstantTaskExecutorRule instantTaskExecutorRule = new InstantTaskExecutorRule();

    @Mock
    private StudentRepository mockRepository;

    private StudentViewModel viewModel;

    @Before
    public void setup() {
        viewModel = new StudentViewModel(mockRepository);
    }

    @Test
    public void loadStudents_success_updatesLiveData() throws Exception {
        // Given - 准备测试数据
        List<Student> expectedStudents = Arrays.asList(
                new Student(1, "张三", "zhangsan@example.com", 20),
                new Student(2, "李四", "lisi@example.com", 21)
        );
        when(mockRepository.getAllStudents()).thenReturn(expectedStudents);

        // When - 执行被测方法
        viewModel.loadStudents();

        // 等待异步任务完成
        Thread.sleep(500);

        // Then - 验证结果
        List<Student> actualStudents = viewModel.getStudents().getValue();
        assertNotNull(actualStudents);
        assertEquals(2, actualStudents.size());
        assertEquals("张三", actualStudents.get(0).getName());
    }

    @Test
    public void loadStudents_failure_setsErrorMessage() throws Exception {
        // Given
        when(mockRepository.getAllStudents()).thenThrow(new RuntimeException("网络异常"));

        // When
        viewModel.loadStudents();
        Thread.sleep(500);

        // Then
        String error = viewModel.getErrorMessage().getValue();
        assertNotNull(error);
        assertTrue(error.contains("网络异常"));
    }

    @Test
    public void addStudent_callsRepository() {
        // Given
        Student newStudent = new Student(0, "王五", "wangwu@example.com", 22);

        // When
        viewModel.addStudent(newStudent);

        // Then
        verify(mockRepository, timeout(1000)).insertStudent(newStudent);
    }
}
```

### 7.2 数据库测试

```java
@RunWith(AndroidJUnit4.class)
public class StudentDaoTest {
    private AppDatabase database;
    private StudentDao studentDao;

    @Before
    public void createDb() {
        Context context = ApplicationProvider.getApplicationContext();
        database = Room.inMemoryDatabaseBuilder(context, AppDatabase.class)
                .allowMainThreadQueries()
                .build();
        studentDao = database.studentDao();
    }

    @After
    public void closeDb() {
        database.close();
    }

    @Test
    public void insertAndReadStudent() {
        // Given
        StudentEntity student = new StudentEntity(0, "张三", "zhangsan@test.com", 20);

        // When
        studentDao.insert(student);
        List<StudentEntity> allStudents = studentDao.getAllStudents();

        // Then
        assertEquals(1, allStudents.size());
        assertEquals("张三", allStudents.get(0).getName());
    }

    @Test
    public void searchStudents_returnsMatchingResults() {
        // Given
        studentDao.insert(new StudentEntity(0, "张三", "a@test.com", 20));
        studentDao.insert(new StudentEntity(0, "张小明", "b@test.com", 21));
        studentDao.insert(new StudentEntity(0, "李四", "c@test.com", 22));

        // When
        List<StudentEntity> results = studentDao.searchStudents("张");

        // Then
        assertEquals(2, results.size());
    }

    @Test
    public void deleteStudent_removesFromDatabase() {
        // Given
        StudentEntity student = new StudentEntity(1, "测试", "test@test.com", 20);
        studentDao.insert(student);

        // When
        studentDao.delete(student);

        // Then
        List<StudentEntity> remaining = studentDao.getAllStudents();
        assertEquals(0, remaining.size());
    }
}
```

### 7.3 UI测试（Espresso）

```java
@RunWith(AndroidJUnit4.class)
public class MainActivityTest {

    @Rule
    public ActivityScenarioRule<MainActivity> activityRule =
            new ActivityScenarioRule<>(MainActivity.class);

    @Test
    public void titleIsDisplayed() {
        // 验证标题文本可见
        onView(withId(R.id.tvTitle))
                .check(matches(isDisplayed()))
                .check(matches(withText("智慧校园管理系统")));
    }

    @Test
    public void searchInput_filtersStudentList() {
        // 在搜索框输入文字
        onView(withId(R.id.etSearch))
                .perform(typeText("张"), closeSoftKeyboard());

        // 验证列表已过滤（至少有一个匹配项）
        onView(withId(R.id.rvContent))
                .check(matches(hasMinimumChildCount(1)));
    }

    @Test
    public void clickStudent_opensDetailActivity() {
        // 点击列表中的第一个学生
        onView(withId(R.id.rvContent))
                .perform(RecyclerViewActions.actionOnItemAtPosition(0, click()));

        // 验证跳转到了详情页
        onView(withId(R.id.tvStudentName))
                .check(matches(isDisplayed()));
    }

    @Test
    public void bottomNavigation_switchesTabs() {
        // 点击"课程"Tab
        onView(withId(R.id.nav_courses))
                .perform(click());

        // 验证课程列表可见
        onView(withId(R.id.rvCourses))
                .check(matches(isDisplayed()));

        // 点击"实验"Tab
        onView(withId(R.id.nav_lab))
                .perform(click());

        // 验证实验页面可见
        onView(withId(R.id.tvLabTitle))
                .check(matches(isDisplayed()));
    }
}
```

### 7.4 调试技巧

```java
// 1. 日志调试（使用TAG规范）
public class DebugUtils {
    private static final String TAG = "SmartCampus";

    public static void logDebug(String message) {
        if (BuildConfig.DEBUG) {
            Log.d(TAG, message);
        }
    }

    public static void logError(String message, Throwable throwable) {
        Log.e(TAG, message, throwable);
    }
}

// 2. StrictMode检测主线程违规
public class MyApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        if (BuildConfig.DEBUG) {
            StrictMode.setThreadPolicy(new StrictMode.ThreadPolicy.Builder()
                    .detectDiskReads()
                    .detectDiskWrites()
                    .detectNetwork()
                    .penaltyLog()
                    .build());
            StrictMode.setVmPolicy(new StrictMode.VmPolicy.Builder()
                    .detectLeakedSqlLiteObjects()
                    .detectLeakedClosableObjects()
                    .penaltyLog()
                    .build());
        }
    }
}

// 3. 自定义异常处理器
public class CrashHandler implements Thread.UncaughtExceptionHandler {
    private static final CrashHandler INSTANCE = new CrashHandler();
    private Thread.UncaughtExceptionHandler defaultHandler;

    public static CrashHandler getInstance() { return INSTANCE; }

    public void init() {
        defaultHandler = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler(this);
    }

    @Override
    public void uncaughtException(@NonNull Thread thread, @NonNull Throwable throwable) {
        // 保存崩溃日志到本地文件
        saveCrashLog(throwable);
        // 交给系统默认处理器
        if (defaultHandler != null) {
            defaultHandler.uncaughtException(thread, throwable);
        }
    }

    private void saveCrashLog(Throwable throwable) {
        StringWriter sw = new StringWriter();
        throwable.printStackTrace(new PrintWriter(sw));
        String crashLog = sw.toString();
        // 写入文件或上传到服务器
        Log.e("CrashHandler", crashLog);
    }
}
```

## 八、性能优化

### 8.1 内存优化

```java
// 1. Bitmap内存优化
public class ImageUtils {
    /**
     * 按需加载缩放后的Bitmap，避免OOM
     */
    public static Bitmap decodeSampledBitmap(String filePath, int reqWidth, int reqHeight) {
        // 第一次解码只获取尺寸
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(filePath, options);

        // 计算缩放比例
        options.inSampleSize = calculateInSampleSize(options, reqWidth, reqHeight);

        // 第二次解码实际加载
        options.inJustDecodeBounds = false;
        return BitmapFactory.decodeFile(filePath, options);
    }

    private static int calculateInSampleSize(BitmapFactory.Options options,
                                              int reqWidth, int reqHeight) {
        int height = options.outHeight;
        int width = options.outWidth;
        int inSampleSize = 1;

        if (height > reqHeight || width > reqWidth) {
            int halfHeight = height / 2;
            int halfWidth = width / 2;
            while ((halfHeight / inSampleSize) >= reqHeight
                    && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2;
            }
        }
        return inSampleSize;
    }
}

// 2. 使用LruCache缓存
public class MemoryCache {
    private final LruCache<String, Bitmap> cache;

    public MemoryCache() {
        int maxMemory = (int) (Runtime.getRuntime().maxMemory() / 1024);
        int cacheSize = maxMemory / 8; // 使用最大内存的1/8
        cache = new LruCache<String, Bitmap>(cacheSize) {
            @Override
            protected int sizeOf(String key, Bitmap bitmap) {
                return bitmap.getByteCount() / 1024;
            }
        };
    }

    public void put(String key, Bitmap bitmap) { cache.put(key, bitmap); }
    public Bitmap get(String key) { return cache.get(key); }
    public void clear() { cache.evictAll(); }
}

// 3. 避免内存泄漏：使用WeakReference
public class SafeHandler extends Handler {
    private final WeakReference<Activity> activityRef;

    public SafeHandler(Activity activity) {
        super(Looper.getMainLooper());
        this.activityRef = new WeakReference<>(activity);
    }

    @Override
    public void handleMessage(@NonNull Message msg) {
        Activity activity = activityRef.get();
        if (activity != null && !activity.isFinishing()) {
            // 安全地处理消息
        }
    }
}
```

### 8.2 启动优化

```java
// Application初始化优化
public class MyApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();

        // 必要的同步初始化
        initEssentialComponents();

        // 延迟初始化非必要组件
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            initDeferredComponents();
        }, 1000);

        // 后台线程初始化
        ExecutorService executor = Executors.newSingleThreadExecutor();
        executor.execute(this::initBackgroundComponents);
    }

    private void initEssentialComponents() {
        // 数据库初始化
        AppDatabase.getInstance(this);
        // 崩溃处理
        CrashHandler.getInstance().init();
    }

    private void initDeferredComponents() {
        // 统计SDK、推送SDK等非首屏必要组件
        Log.d("App", "延迟组件初始化完成");
    }

    private void initBackgroundComponents() {
        // 预加载数据
        AppDatabase.getInstance(this).studentDao().getAllStudents();
    }
}
```

### 8.3 列表性能优化

```java
// RecyclerView性能优化
private void optimizeRecyclerView() {
    // 1. 设置固定大小（如果item高度固定）
    binding.rvContent.setHasFixedSize(true);

    // 2. 设置预加载项数量
    binding.rvContent.setItemViewCacheSize(20);

    // 3. 使用DiffUtil替代notifyDataSetChanged
    // 参见5.3节StudentAdapter中的DiffUtil实现

    // 4. 禁用嵌套滚动
    binding.rvContent.setNestedScrollingEnabled(false);

    // 5. 添加滚动监听器实现分页加载
    binding.rvContent.addOnScrollListener(new RecyclerView.OnScrollListener() {
        @Override
        public void onScrolled(@NonNull RecyclerView recyclerView, int dx, int dy) {
            super.onScrolled(recyclerView, dx, dy);
            LinearLayoutManager layoutManager =
                    (LinearLayoutManager) recyclerView.getLayoutManager();
            if (layoutManager != null) {
                int totalItemCount = layoutManager.getItemCount();
                int lastVisible = layoutManager.findLastVisibleItemPosition();
                if (lastVisible >= totalItemCount - 5) {
                    viewModel.loadMoreStudents(); // 触发加载下一页
                }
            }
        }
    });
}
```

### 8.4 网络优化

```java
// OkHttp缓存配置
private OkHttpClient createOptimizedClient(Context context) {
    // 磁盘缓存：10MB
    File cacheDir = new File(context.getCacheDir(), "http_cache");
    Cache cache = new Cache(cacheDir, 10 * 1024 * 1024);

    return new OkHttpClient.Builder()
            .cache(cache)
            .addInterceptor(chain -> {
                Request request = chain.request();
                // 无网络时使用缓存
                if (!isNetworkAvailable(context)) {
                    request = request.newBuilder()
                            .cacheControl(CacheControl.FORCE_CACHE)
                            .build();
                }
                return chain.proceed(request);
            })
            .addNetworkInterceptor(chain -> {
                Response response = chain.proceed(chain.request());
                // 有网络时缓存5分钟
                return response.newBuilder()
                        .header("Cache-Control", "public, max-age=300")
                        .build();
            })
            .connectionPool(new ConnectionPool(5, 5, TimeUnit.MINUTES))
            .build();
}

private boolean isNetworkAvailable(Context context) {
    ConnectivityManager cm = (ConnectivityManager)
            context.getSystemService(Context.CONNECTIVITY_SERVICE);
    NetworkCapabilities capabilities = cm.getNetworkCapabilities(cm.getActiveNetwork());
    return capabilities != null
            && capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);
}
```

## 九、发布与部署

### 9.1 签名配置

```groovy
// build.gradle
android {
    signingConfigs {
        release {
            storeFile file("keystore.jks")
            storePassword "your_store_password"
            keyAlias "your_key_alias"
            keyPassword "your_key_password"
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }

        debug {
            applicationIdSuffix ".debug"
            versionNameSuffix "-debug"
            debuggable true
        }
    }
}
```

### 9.2 ProGuard混淆规则

```proguard
# proguard-rules.pro

# 保留Gson序列化类
-keep class com.example.app.data.model.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# 保留Retrofit接口
-keep,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}

# 保留Room实体
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Glide
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
    <init>(...);
}
```

### 9.3 多渠道打包

```groovy
android {
    flavorDimensions "channel"

    productFlavors {
        huawei {
            dimension "channel"
            applicationIdSuffix ".huawei"
            buildConfigField "String", "CHANNEL", "\"huawei\""
            manifestPlaceholders = [CHANNEL_VALUE: "huawei"]
        }
        xiaomi {
            dimension "channel"
            applicationIdSuffix ".xiaomi"
            buildConfigField "String", "CHANNEL", "\"xiaomi\""
            manifestPlaceholders = [CHANNEL_VALUE: "xiaomi"]
        }
        oppo {
            dimension "channel"
            applicationIdSuffix ".oppo"
            buildConfigField "String", "CHANNEL", "\"oppo\""
            manifestPlaceholders = [CHANNEL_VALUE: "oppo"]
        }
    }
}
```

### 9.4 CI/CD构建脚本

```groovy
// 版本号自动管理
android {
    defaultConfig {
        // 基于Git提交数自动递增versionCode
        versionCode getGitCommitCount()
        versionName "1.0.${getGitCommitCount()}"
    }
}

static int getGitCommitCount() {
    try {
        def process = "git rev-list --count HEAD".execute()
        return process.text.trim().toInteger()
    } catch (Exception e) {
        return 1
    }
}

// APK输出重命名
android {
    applicationVariants.all { variant ->
        variant.outputs.all { output ->
            def fileName = "SmartCampus_${variant.versionName}_${variant.flavorName}_${variant.buildType.name}.apk"
            outputFileName = fileName
        }
    }
}
```

## 十、常见问题与解决方案

### 10.1 内存泄漏
**问题**：Activity或Fragment销毁后，内部类（Handler、AsyncTask、匿名回调）仍持有外部引用导致内存泄漏

**解决方案**：
```java
// 错误示例：匿名内部类持有Activity引用
public class BadActivity extends AppCompatActivity {
    private final Handler handler = new Handler() {
        @Override
        public void handleMessage(Message msg) {
            // 这里隐式持有BadActivity的引用，会导致泄漏
            updateUI();
        }
    };
}

// 正确示例：使用静态内部类 + WeakReference
public class GoodActivity extends AppCompatActivity {
    private final SafeHandler handler = new SafeHandler(this);

    private static class SafeHandler extends Handler {
        private final WeakReference<GoodActivity> activityRef;

        SafeHandler(GoodActivity activity) {
            super(Looper.getMainLooper());
            activityRef = new WeakReference<>(activity);
        }

        @Override
        public void handleMessage(@NonNull Message msg) {
            GoodActivity activity = activityRef.get();
            if (activity != null && !activity.isFinishing()) {
                activity.updateUI();
            }
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        handler.removeCallbacksAndMessages(null); // 清除所有消息
    }
}
```

### 10.2 ANR问题
**问题**：主线程执行耗时操作（网络请求、数据库读写、大文件IO）导致应用无响应

**解决方案**：
```java
// 使用CompletableFuture在后台线程执行耗时操作
public void loadData() {
    ExecutorService executor = Executors.newSingleThreadExecutor();
    Handler mainHandler = new Handler(Looper.getMainLooper());

    CompletableFuture.supplyAsync(() -> {
        // 在IO线程执行网络请求
        return api.fetchData();
    }, executor).thenAccept(data -> {
        // 切换到主线程更新UI
        mainHandler.post(() -> updateUI(data));
    }).exceptionally(throwable -> {
        mainHandler.post(() -> showError(throwable.getMessage()));
        return null;
    });
}
```

### 10.3 Fragment生命周期问题
**问题**：Fragment的View被销毁后仍通过binding访问视图导致崩溃

**解决方案**：
```java
public class SafeFragment extends Fragment {
    private FragmentSafeBinding binding;

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater,
                             ViewGroup container, Bundle savedInstanceState) {
        binding = FragmentSafeBinding.inflate(inflater, container, false);
        return binding.getRoot();
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);
        // 使用getViewLifecycleOwner()观察LiveData，而不是this
        viewModel.getData().observe(getViewLifecycleOwner(), data -> {
            // 只在View存活时更新UI
            if (binding != null) {
                binding.tvData.setText(data.toString());
            }
        });
    }

    @Override
    public void onDestroyView() {
        super.onDestroyView();
        binding = null; // 必须置空，防止泄漏
    }
}
```

### 10.4 RecyclerView点击事件错位
**问题**：列表快速滚动时，点击事件对应到错误的数据项

**解决方案**：
```java
// 在ViewHolder的bind方法中设置点击事件，使用getBindingAdapterPosition()
class ViewHolder extends RecyclerView.ViewHolder {
    ViewHolder(ItemBinding binding) {
        super(binding.getRoot());
    }

    void bind(DataItem item) {
        // 正确：直接使用传入的item对象
        binding.getRoot().setOnClickListener(v -> {
            int pos = getBindingAdapterPosition();
            if (pos != RecyclerView.NO_POSITION) {
                onItemClick.accept(dataList.get(pos));
            }
        });
    }
}
```

### 10.5 多线程并发问题
**问题**：多个线程同时修改共享数据导致数据不一致

**解决方案**：
```java
// 使用线程安全的集合和同步机制
public class ThreadSafeCache<K, V> {
    private final ConcurrentHashMap<K, V> cache = new ConcurrentHashMap<>();

    public V get(K key) {
        return cache.get(key);
    }

    public void put(K key, V value) {
        cache.put(key, value);
    }

    // 使用AtomicInteger保证原子操作
    private final AtomicInteger requestCount = new AtomicInteger(0);

    public int incrementAndGetCount() {
        return requestCount.incrementAndGet();
    }
}
```

## 十一、学习资源

### 11.1 官方文档
- Java官方文档：https://docs.oracle.com/en/java/
- Android开发者指南：https://developer.android.com/guide
- Material Design组件：https://material.io/components
- AndroidX库参考：https://developer.android.com/jetpack/androidx

### 11.2 推荐书籍
- 《Java核心技术（卷I/卷II）》
- 《Effective Java（第3版）》
- 《Android开发艺术探索》
- 《Android编程权威指南》
- 《Head First设计模式》

### 11.3 在线课程
- Google Android Developers Training
- Oracle Java官方教程
- 菜鸟教程 Java/Android 系列
- 慕课网 Android开发实战课程

### 11.4 开发工具
- Android Studio：官方集成开发环境
- Android Profiler：性能分析（CPU/内存/网络）
- Layout Inspector：布局层级检查
- LeakCanary：内存泄漏检测
- Stetho：网络请求和数据库调试

## 十二、实验项目要求

### 12.1 基础要求
1. 使用Java 17语言开发
2. 采用MVVM或MVP架构
3. 使用XML布局 + ViewBinding构建UI
4. 集成Retrofit进行网络请求
5. 实现数据持久化（Room数据库或SharedPreferences）
6. 添加单元测试和UI测试
7. 使用Material Design组件，保持界面风格统一

### 12.2 进阶要求
1. 实现RecyclerView多类型列表和DiffUtil高效刷新
2. 集成AI功能（智能问答、文本分析等）
3. 优化应用性能（启动速度、内存使用、列表流畅度）
4. 实现深色模式支持（DayNight主题）
5. 使用Navigation组件实现页面导航
6. 实现下拉刷新和上拉加载更多
7. 添加网络状态监测和离线缓存

### 12.3 提交要求
1. 完整的项目源代码（Git仓库）
2. 详细的README文档（项目说明、运行方式、技术选型）
3. APK安装包（Debug和Release版本）
4. 测试报告（单元测试覆盖率、UI测试截图）
5. 技术文档和架构设计图
6. 演示视频（3-5分钟，展示核心功能）
