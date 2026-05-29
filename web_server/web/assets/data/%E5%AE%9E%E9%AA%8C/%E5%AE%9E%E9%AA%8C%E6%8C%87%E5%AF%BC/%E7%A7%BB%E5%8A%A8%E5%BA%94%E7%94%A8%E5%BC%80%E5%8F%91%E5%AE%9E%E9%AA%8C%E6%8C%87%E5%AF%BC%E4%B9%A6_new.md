# 移动应用开发实验指导书（新版）

![alt text](mobile_app_development_timeline-1.png)

## 移动应用开发实验课程概述

本实验指导书涵盖移动应用开发课程的六个核心实验，涵盖从环境搭建到综合项目实战的全流程。每个实验都包含详细的操作步骤、AI辅助开发技巧和难重点指导，帮助学生全面掌握主流移动应用开发技术。

---

## 实验一：移动应用开发环境搭建

### 一、实验项目基本信息

| 项目 | 内容 |
|------|------|
| **实验编号** | d20301035101、d20301009201 |
| **学时分配** | 2学时 |
| **实验类型** | 验证型 |
| **每组人数** | 6人（组内分工协作） |
| **对应课程目标** | 课程目标1：掌握移动应用开发环境配置 |

### 二、实验任务与案例

**核心任务**：搭建完整的移动应用开发工具链，根据组内分工完成对应平台环境配置，使用AI辅助生成实验项目模板代码，验证各平台开发环境可用性。

**实战案例**：组内6名成员分别负责一个技术栈，创建并运行"智慧校园"主题的实验项目，掌握从环境搭建到项目部署的完整流程，并输出环境配置文档。

### 三、开发工具清单

| 序号 | 开发工具 | 主要用途 | 验证项目 |
|------|----------|----------|----------|
| 1 | Android Studio | Android原生开发 | Kotlin HelloWorld |
| 2 | Flutter SDK | 跨平台开发 | Dart HelloWorld |
| 3 | 微信开发者工具 | 小程序开发 | 微信小程序HelloWorld |
| 4 | DevEco Studio | 鸿蒙应用开发 | HarmonyOS HelloWorld |
| 5 | HBuilderX | Uniapp开发 | Vue HelloWorld |
| 6 | Visual Studio | MAUI开发 | C# HelloWorld |

### 四、环境依赖要求

#### 1. Android开发环境
- JDK 17+
- Android Studio 2024.1+
- Android SDK 34+

#### 2. Flutter开发环境
- Flutter 3.19+
- Dart 3.3+

#### 3. 鸿蒙开发环境
- DevEco Studio 5.0+
- HarmonyOS SDK 5.0+

#### 4. Uniapp开发环境
- HBuilderX 4.0+
- Node.js 18+

#### 5. MAUI开发环境
- Visual Studio 2022
- .NET 8.0

#### 6. 微信小程序开发环境
- 微信开发者工具

### 五、实验步骤详解

#### 第一课时：环境准备与工具安装

##### 1.1 Android Studio环境搭建（AI辅助）

**步骤1：下载与安装**
1. 访问官网：https://developer.android.com/studio
2. 下载Windows/macOS版本
3. 运行安装程序，勾选：Android Studio、Android SDK、Android Virtual Device
4. 完成安装

**AI辅助技巧**：
- 使用TRAE询问："Android Studio安装后首次配置建议"
- 使用TRAE生成HelloWorld代码模板

**步骤2：创建项目**
1. 启动Android Studio
2. 创建Empty Activity项目
3. 使用AI辅助生成HelloWorld代码

##### 1.2 Flutter环境搭建（AI辅助）

**步骤1：下载Flutter SDK**
1. 访问：https://flutter.dev/docs/get-started/install
2. 下载对应系统版本
3. 解压到指定目录（如：D:\flutter）
4. 添加到系统PATH环境变量

**AI辅助技巧**：
- 使用TRAE询问："Flutter环境变量配置Windows步骤"
- 使用TRAE生成Dart HelloWorld代码

#### 第二课时：多平台环境配置与验证

##### 2.1 各平台环境搭建

**鸿蒙开发环境**：
- 访问：https://developer.harmonyos.com/
- 下载DevEco Studio并安装
- 创建Empty Ability项目

**Uniapp开发环境**：
- 访问：https://www.dcloud.io/hbuilderx.html
- 下载HBuilderX并安装
- 新建uni-app项目

**MAUI开发环境**：
- 安装Visual Studio 2022
- 勾选".NET MAUI" workload
- 新建.NET MAUI项目

**微信小程序开发环境**：
- 访问：https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html
- 下载并安装
- 扫码登录

##### 2.2 测试验证

**编译运行验证**：
1. 在各自模拟器上运行HelloWorld
2. 记录运行结果
3. 汇总常见问题并讨论解决方案

### 六、难重点指导

#### 重点
- JDK环境变量配置
- Android SDK安装与配置
- Flutter doctor命令使用

#### 难点
- **模拟器启动失败**：解决方法——启用Intel VT-x虚拟化技术
- **Flutter doctor检测失败**：解决方法——使用TRAE生成解决方案
- **网络问题导致SDK下载失败**：解决方法——配置国内镜像源

#### AI解决技巧
1. 遇到安装问题，使用TRAE搜索解决方案
2. 配置问题可询问："Flutter环境配置常见问题及解决"
3. 代码生成使用自然语言描述需求

### 七、成功标准

- [ ] 6个开发工具成功安装并启动
- [ ] 6个HelloWorld项目成功创建
- [ ] 所有项目成功编译运行
- [ ] 模拟器/真机调试正常
- [ ] 环境配置文档完整

### 八、评价标准（100分）

| 评分项 | 分值 | 评价标准 |
|--------|------|----------|
| 环境完整性 | 40分 | 6种开发工具均成功搭建，无遗漏；工具版本符合要求 |
| 项目运行效果 | 30分 | 所有HelloWorld项目正常显示，界面无错误；模拟器运行稳定 |
| 问题记录 | 20分 | 记录问题真实具体，解决方案有效；体现独立排查问题的能力 |
| 步骤规范性 | 10分 | 操作流程符合工具官方指南，配置参数设置合理 |

---

## 实验二：原生应用开发

### 一、实验项目基本信息

| 项目 | 内容 |
|------|------|
| **实验编号** | d20301035102、d20301009202 |
| **学时分配** | 4学时 |
| **实验类型** | 验证型 |
| **每组人数** | 6人（组内分工协作） |
| **对应课程目标** | 课程目标1：掌握原生应用开发基础 |

### 二、实验任务与案例

**核心任务**：使用Kotlin实现Android登录页面（EditText输入验证、Activity跳转与数据传递），使用SwiftUI实现iOS登录页面，组内成员选择不同平台实现同一功能，完成后进行技术对比分享。

**实战案例**：开发"智慧校园"登录模块，学生在登录页面输入学号和密码，系统验证成功后跳转到个人中心页面，显示个性化的欢迎信息和用户资料。

### 三、开发任务清单

| 任务阶段 | 主要内容 | 关键技术点 |
|----------|----------|------------|
| Android登录 | Kotlin + Activity跳转 | EditText、Intent、Bundle |
| iOS登录 | SwiftUI + ViewController | @State、Navigation |
| 组内对比 | 技术分享 | 平台差异分析 |

### 四、实验步骤详解

#### 第一课时：Android登录页面设计

##### 1.1 需求分析

**功能需求**：
- 用户名输入（学号）
- 密码输入
- 登录按钮
- 输入验证（不能为空、长度限制）

**界面需求**：
- Material Design风格
- 输入框占位提示
- 密码隐藏显示

##### 1.2 Android项目创建

**创建项目**：
1. 打开Android Studio
2. 创建Empty Activity项目
3. 选择Kotlin语言
4. 最低SDK：API 24

##### 1.3 AI辅助编码

**使用TRAE生成代码**：
- 描述需求："Kotlin登录页面，EditText输入验证，Activity跳转"
- AI生成代码片段
- 手动完善业务逻辑

**登录页面布局代码**：
```kotlin
// activity_login.xml
// 使用TRAE生成的代码框架
class LoginActivity : AppCompatActivity() {
    
    private lateinit var etUsername: EditText
    private lateinit var etPassword: EditText
    private lateinit var btnLogin: Button
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)
        
        etUsername = findViewById(R.id.et_username)
        etPassword = findViewById(R.id.et_password)
        btnLogin = findViewById(R.id.btn_login)
        
        btnLogin.setOnClickListener {
            val username = etUsername.text.toString()
            val password = etPassword.text.toString()
            
            if (validateInput(username, password)) {
                login(username, password)
            }
        }
    }
    
    private fun validateInput(username: String, password: String): Boolean {
        if (username.isEmpty()) {
            etUsername.error = "学号不能为空"
            return false
        }
        if (password.isEmpty()) {
            etPassword.error = "密码不能为空"
            return false
        }
        return true
    }
    
    private fun login(username: String, password: String) {
        // 模拟登录验证
        if (username == "admin" && password == "123456") {
            val intent = Intent(this, HomeActivity::class.java)
            intent.putExtra("username", username)
            startActivity(intent)
        } else {
            Toast.makeText(this, "用户名或密码错误", Toast.LENGTH_SHORT).show()
        }
    }
}
```

##### 1.4 创建个人中心页面

**HomeActivity接收数据**：
```kotlin
class HomeActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_home)
        
        val username = intent.getStringExtra("username")
        val tvWelcome = findViewById<TextView>(R.id.tv_welcome)
        tvWelcome.text = "欢迎 $username"
    }
}
```

#### 第二课时：iOS登录与平台对比

##### 2.1 iOS登录实现（演示/模拟器）

**创建SwiftUI项目**：
1. 打开Xcode
2. 创建SwiftUI项目
3. 命名为NativeLogin

**AI辅助生成SwiftUI代码**：
- 使用TRAE描述需求："SwiftUI登录页面，Navigation导航"
- 生成代码片段

**SwiftUI登录页面代码**：
```swift
struct ContentView: View {
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoginSuccess: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("请输入学号", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                SecureField("请输入密码", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("登录") {
                    if validateInput() {
                        isLoginSuccess = true
                    }
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                
                NavigationLink(destination: HomeView(username: username), isActive: $isLoginSuccess) {
                    EmptyView()
                }
            }
            .padding()
            .navigationTitle("智慧校园登录")
        }
    }
    
    func validateInput() -> Bool {
        return !username.isEmpty && !password.isEmpty
    }
}
```

##### 2.2 平台差异对比

| 对比项 | Android | iOS |
|--------|---------|-----|
| 开发语言 | Kotlin | Swift |
| UI框架 | XML/Compose | SwiftUI |
| 页面跳转 | Intent | NavigationLink |
| 数据传递 | Intent.putExtra | @Binding |

### 五、难重点指导

#### 重点
- Kotlin语言基础
- Activity生命周期
- Intent数据传递

#### 难点
- **Bundle数据接收**：使用getStringExtra方法，注意空值处理
- **输入验证逻辑**：边界条件检查（空值、长度）
- **页面跳转动画**：默认动画效果自定义

#### AI解决技巧
1. 代码生成：描述具体需求让TRAE生成
2. 错误排查：将错误信息粘贴给TRAE获取解决方案
3. 代码优化：询问"更优雅的Kotlin代码写法"

### 六、成功标准

- [ ] Android登录页面功能完整
- [ ] iOS登录页面功能完整
- [ ] Activity跳转与数据传递正常
- [ ] 输入验证逻辑正确
- [ ] 平台差异对比报告完成

### 七、评价标准（100分）

| 评分项 | 分值 | 评价标准 |
|--------|------|----------|
| 界面布局 | 20分 | 控件对齐规范，提示清晰，交互友好；布局参数设置合理 |
| 跳转功能 | 30分 | 点击按钮成功跳转至首页，无崩溃或异常 |
| 数据传递 | 30分 | 用户名准确传递到首页并显示，个性化信息正确 |
| 异常处理 | 20分 | 对空输入有提示（Toast），程序健壮性良好 |

---

## 实验三：跨平台应用开发

### 一、实验项目基本信息

| 项目 | 内容 |
|------|------|
| **实验编号** | d20301035103、d20301009203 |
| **学时分配** | 4学时 |
| **实验类型** | 验证型 |
| **每组人数** | 6人（组内分工协作） |
| **对应课程目标** | 课程目标2：掌握跨平台应用开发 |

### 二、实验任务与案例

**核心任务**：开发业务数据列表页（RESTful API网络数据请求 + JSON解析 + 下拉刷新），组内成员分别使用Flutter、React Native、Uniapp、MAUI等不同框架实现同一功能需求。扩展案例：集成设备传感器（GPS定位，加速度计）。

**实战案例**：开发"智慧校园"新闻列表模块，从RESTful API获取新闻数据，解析JSON并展示列表，实现下拉刷新功能，体验跨平台框架的开发差异。

### 三、开发任务清单

| 任务阶段 | 主要内容 | 关键技术点 |
|----------|----------|------------|
| Flutter列表 | Dart + Provider | HTTP请求、JSON解析、下拉刷新 |
| React Native列表 | JSX + Hooks | Axios、FlatList、下拉刷新 |
| Uniapp列表 | Vue + Pinia | uni.request、下拉刷新 |
| MAUI列表 | C# + MVVM | HttpClient、数据绑定 |

### 四、实验步骤详解

#### 第一课时：Flutter与React Native开发

##### 1.1 需求分析

**定义数据模型**：
```json
{
  "code": 200,
  "data": {
    "items": [
      {
        "id": 1,
        "title": "智慧校园更新通知",
        "content": "系统升级通知...",
        "author": "管理员",
        "time": "2024-01-01 10:00:00"
      }
    ]
  }
}
```

##### 1.2 Flutter列表开发

**项目创建与依赖**：
```bash
flutter create news_list
cd news_list
```

**pubspec.yaml依赖**：
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  provider: ^6.1.0
```

**AI辅助生成Flutter代码**：
- 描述需求："Flutter新闻列表页，下拉刷新，Provider状态管理"
- 使用TRAE生成代码

**Flutter新闻列表实现**：
```dart
class News {
  final int id;
  final String title;
  final String content;
  final String author;
  final String time;
  
  News({required this.id, required this.title, required this.content, 
        required this.author, required this.time});
  
  factory News.fromJson(Map<String, dynamic> json) {
    return News(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      author: json['author'],
      time: json['time'],
    );
  }
}

class NewsProvider extends ChangeNotifier {
  List<News> _newsList = [];
  List<News> get newsList => _newsList;
  
  Future<void> fetchNews() async {
    final response = await http.get(
      Uri.parse('https://api.example.com/news')
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['data']['items'] as List;
      _newsList = items.map((item) => News.fromJson(item)).toList();
      notifyListeners();
    }
  }
}

class NewsListPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('智慧校园新闻')),
      body: Consumer<NewsProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: () => provider.fetchNews(),
            child: ListView.builder(
              itemCount: provider.newsList.length,
              itemBuilder: (context, index) {
                final news = provider.newsList[index];
                return ListTile(
                  title: Text(news.title),
                  subtitle: Text(news.author),
                  trailing: Text(news.time),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
```

##### 1.3 React Native列表开发

**项目创建与依赖**：
```bash
npx react-native-init NewsList
cd NewsList
npm install axios @react-native-community/refresh-control
```

**React Native新闻列表实现**：
```jsx
const App = () => {
  const [news, setNews] = useState([]);
  const [refreshing, setRefreshing] = useState(false);

  const fetchNews = async () => {
    try {
      const response = await axios.get('https://api.example.com/news');
      setNews(response.data.data.items);
    } catch (error) {
      console.error(error);
    }
  };

  useEffect(() => {
    fetchNews();
  }, []);

  const onRefresh = async () => {
    setRefreshing(true);
    await fetchNews();
    setRefreshing(false);
  };

  const renderItem = ({ item }) => (
    <View style={styles.item}>
      <Text style={styles.title}>{item.title}</Text>
      <Text>{item.author} - {item.time}</Text>
    </View>
  );

  return (
    <FlatList
      data={news}
      keyExtractor={item => item.id.toString()}
      renderItem={renderItem}
      refreshControl={
        <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
      }
    />
  );
};
```

#### 第二课时：Uniapp、MAUI与传感器集成

##### 2.1 Uniapp列表开发

**Uniapp新闻列表实现**：
```javascript
// pages/index/index.vue
<template>
  <view class="content">
    <view class="news-item" v-for="item in newsList" :key="item.id">
      <text class="title">{{item.title}}</text>
      <text class="info">{{item.author}} - {{item.time}}</text>
    </view>
  </view>
</template>

<script>
export default {
  data() {
    return {
      newsList: []
    }
  },
  onLoad() {
    this.fetchNews();
  },
  onPullDownRefresh() {
    this.fetchNews().then(() => {
      uni.stopPullDownRefresh();
    });
  },
  methods: {
    async fetchNews() {
      const res = await uni.request({
        url: 'https://api.example.com/news'
      });
      if (res.data.code === 200) {
        this.newsList = res.data.data.items;
      }
    }
  }
}
</script>
```

##### 2.2 MAUI列表开发

**MAUI新闻列表实现**：
```csharp
public partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    private ObservableCollection<NewsItem> _newsList = new();
    
    public async Task FetchNewsAsync()
    {
        using var client = new HttpClient();
        var response = await client.GetAsync("https://api.example.com/news");
        var json = await response.Content.ReadAsStringAsync();
        var data = JsonSerializer.Deserialize<NewsResponse>(json);
        
        NewsList = new ObservableCollection<NewsItem>(data.Data.Items);
    }
}
```

##### 2.3 传感器集成扩展

**GPS定位实现（Flutter示例）**：
```dart
import 'package:geolocator/geolocator.dart';

Future<void> getLocation() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return;
  
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  
  Position position = await Geolocator.getCurrentPosition();
  print('位置: ${position.latitude}, ${position.longitude}');
}
```

**加速度计实现（Flutter示例）**：
```dart
import 'package:sensors_plus/sensors_plus.dart';

accelerometerEvents.listen((AccelerometerEvent event) {
  print('X: ${event.x}, Y: ${event.y}, Z: ${event.z}');
});
```

### 五、难重点指导

#### 重点
- HTTP网络请求
- JSON数据解析
- 下拉刷新实现

#### 难点
- **跨域问题**：API服务器配置CORS或使用代理
- **状态管理**：Provider/Redux/Pinia选择
- **平台差异**：各框架API差异处理

#### AI解决技巧
1. 依赖配置问题：询问具体框架的依赖配置方法
2. 代码报错：将错误信息给TRAE分析
3. 性能优化：询问"Flutter性能优化建议"

### 六、成功标准

- [ ] 各框架列表页功能完整
- [ ] RESTful API数据请求正常
- [ ] JSON数据解析正确
- [ ] 下拉刷新功能正常
- [ ] 框架对比报告完成

### 七、框架对比报告模板

| 对比项 | Flutter | React Native | Uniapp | MAUI |
|--------|---------|---------------|--------|------|
| 开发语言 | Dart | JavaScript | Vue | C# |
| 性能 | ★★★★★ | ★★★★☆ | ★★★☆☆ | ★★★★☆ |
| 学习成本 | 中等 | 低 | 低 | 中等 |

### 八、评价标准（100分）

| 评分项 | 分值 | 评价标准 |
|--------|------|----------|
| 列表展示 | 25分 | 数据正确渲染，标题和摘要完整显示；布局美观，item间距合理 |
| 网络请求 | 30分 | 成功获取并解析API数据，无请求错误；数据模型转换正确 |
| 刷新功能 | 30分 | 下拉刷新触发重新请求，数据更新正常；刷新动画流畅 |
| 状态处理 | 15分 | 加载中显示进度指示器，失败状态有友好提示 |

---

## 实验四：微信小程序开发

### 一、实验项目基本信息

| 项目 | 内容 |
|------|------|
| **实验编号** | d20301035104、d20301009204 |
| **学时分配** | 4学时 |
| **实验类型** | 验证型 |
| **每组人数** | 6人（组内分工协作） |
| **对应课程目标** | 课程目标2：掌握小程序开发 |

### 二、实验任务与案例

**核心任务**：借助AI编程工具辅助开发通知小程序（列表 + 详情页路由 + 本地存储），体验AI工具在代码生成与调试中的作用，完成一个可预览的"智慧校园通知"小程序。

**实战案例**：开发"智慧校园通知"小程序，展示校园通知列表，点击进入详情页，支持已读状态本地存储，体验小程序完整开发流程。

### 三、开发任务清单

| 任务阶段 | 主要内容 | 关键技术点 |
|----------|----------|------------|
| 通知列表 | 列表展示 | WXML、wx:for |
| 详情页 | 内容展示 | 页面路由、参数传递 |
| 本地存储 | 数据持久化 | wx.setStorage |
| AI辅助 | 代码生成 | TRAE使用 |

### 四、实验步骤详解

#### 第一课时：小程序基础与列表开发

##### 1.1 需求分析

**页面流程图**：
```
首页(通知列表) → 详情页(通知详情)
     ↓
   本地存储(已读状态)
```

**通知数据结构**：
```javascript
{
  id: 1,
  title: "关于期末考试安排的通知",
  content: "详细内容...",
  author: "教务处",
  time: "2024-01-01",
  isRead: false
}
```

##### 1.2 创建小程序项目

1. 打开微信开发者工具
2. 新建小程序项目
3. 填写AppID（如无则使用测试号）
4. 选择JavaScript模板

##### 1.3 AI辅助编码

**使用TRAE生成列表页代码**：
- 描述需求："微信小程序通知列表页面，WXML列表渲染，点击跳转详情页"
- AI生成代码片段

**通知列表页面实现**：
```html
<!-- pages/index/index.wxml -->
<view class="container">
  <view class="news-list">
    <view 
      class="news-item {{item.isRead ? 'read' : ''}}"
      wx:for="{{newsList}}"
      wx:key="id"
      bindtap="goToDetail"
      data-id="{{item.id}}"
    >
      <view class="title">{{item.title}}</view>
      <view class="info">
        <text>{{item.author}}</text>
        <text>{{item.time}}</text>
      </view>
    </view>
  </view>
</view>
```

```css
/* pages/index/index.wxss */
.news-item {
  padding: 16px;
  border-bottom: 1px solid #eee;
  background: #fff;
}
.news-item.read {
  opacity: 0.6;
}
.title {
  font-size: 16px;
  font-weight: bold;
  margin-bottom: 8px;
}
.info {
  font-size: 12px;
  color: #999;
  display: flex;
  justify-content: space-between;
}
```

```javascript
// pages/index/index.js
Page({
  data: {
    newsList: []
  },
  
  onLoad() {
    this.loadNews();
  },
  
  onPullDownRefresh() {
    this.loadNews().then(() => {
      wx.stopPullDownRefresh();
    });
  },
  
  loadNews() {
    const newsList = [
      { id: 1, title: "关于期末考试安排的通知", content: "详细内容...", author: "教务处", time: "2024-01-01", isRead: false },
      { id: 2, title: "图书馆开放时间调整", content: "详细内容...", author: "图书馆", time: "2024-01-02", isRead: false },
      { id: 3, title: "校园网络维护通知", content: "详细内容...", author: "信息中心", time: "2024-01-03", isRead: false }
    ];
    
    const readIds = wx.getStorageSync('readIds') || [];
    newsList.forEach(news => {
      news.isRead = readIds.includes(news.id);
    });
    
    this.setData({ newsList });
  },
  
  goToDetail(e) {
    const id = e.currentTarget.dataset.id;
    wx.navigateTo({
      url: `/pages/detail/detail?id=${id}`
    });
  }
});
```

#### 第二课时：详情页、存储与发布

##### 2.1 详情页开发

**AI辅助生成详情页**：
- 描述需求："微信小程序通知详情页，接收参数显示内容"

**详情页实现**：
```html
<!-- pages/detail/detail.wxml -->
<view class="container">
  <view class="title">{{news.title}}</view>
  <view class="info">
    <text>发布部门：{{news.author}}</text>
    <text>发布时间：{{news.time}}</text>
  </view>
  <view class="content">{{news.content}}</view>
</view>
```

```javascript
// pages/detail/detail.js
Page({
  data: {
    news: {}
  },
  
  onLoad(options) {
    const id = parseInt(options.id);
    this.loadDetail(id);
  },
  
  loadDetail(id) {
    const allNews = [
      { id: 1, title: "关于期末考试安排的通知", content: "本次期末考试安排如下...", author: "教务处", time: "2024-01-01" },
      { id: 2, title: "图书馆开放时间调整", content: "图书馆开放时间调整...", author: "图书馆", time: "2024-01-02" },
      { id: 3, title: "校园网络维护通知", content: "网络维护通知...", author: "信息中心", time: "2024-01-03" }
    ];
    
    const news = allNews.find(n => n.id === id);
    this.setData({ news });
    
    this.markAsRead(id);
  },
  
  markAsRead(id) {
    let readIds = wx.getStorageSync('readIds') || [];
    if (!readIds.includes(id)) {
      readIds.push(id);
      wx.setStorageSync('readIds', readIds);
    }
  }
});
```

##### 2.2 本地存储

**已读状态存储**：
```javascript
// 保存已读ID
wx.setStorageSync('readIds', [1, 2, 3]);

// 读取已读ID
const readIds = wx.getStorageSync('readIds');

// 检查是否已读
const isRead = readIds.includes(newsId);
```

##### 2.3 测试验证与发布

**真机预览**：
1. 编译项目
2. 扫描二维码预览
3. 测试各项功能

**体验版发布**：
1. 点击上传
2. 填写版本信息
3. 获取体验版二维码

### 五、难重点指导

#### 重点
- WXML模板语法
- wx:for列表渲染
- wx.navigateTo路由跳转

#### 难点
- **本地存储异步**：注意同步/异步API区别
- **页面间数据传递**：URL参数解析
- **下拉刷新配置**：json配置文件启用

#### AI解决技巧
1. 代码生成：描述页面需求让TRAE生成WXML/WXSS/JS
2. 调试技巧：询问"微信小程序调试技巧"
3. 性能优化：询问"小程序性能优化建议"

### 六、成功标准

- [ ] 通知列表页面功能完整
- [ ] 详情页跳转正常
- [ ] 数据本地存储功能正常
- [ ] AI辅助开发体验良好
- [ ] 小程序可预览

### 七、评价标准（100分）

| 评分项 | 分值 | 评价标准 |
|--------|------|----------|
| 功能实现 | 30分 | 列表渲染正确，路由跳转流畅；数据传递准确无误 |
| AI工具应用 | 30分 | 有效使用TRAE生成数据或代码；有明确的AI辅助痕迹和优化记录 |
| 代码质量 | 20分 | 代码结构清晰，命名规范；无语法错误和性能隐患 |
| 用户体验 | 20分 | 页面布局合理，返回逻辑符合用户预期；交互反馈自然 |

---

## 实验五：鸿蒙多端应用开发

### 一、实验项目基本信息

| 项目 | 内容 |
|------|------|
| **实验编号** | d20301035105、d20301009205 |
| **学时分配** | 4学时 |
| **实验类型** | 验证型 |
| **每组人数** | 6人（组内分工协作） |
| **对应课程目标** | 课程目标3：掌握鸿蒙多端开发 |

### 二、实验任务与案例

**核心任务**：使用DevEco Studio开发天气应用，实现手机/平板界面自适应布局；通过模拟器演示分布式数据同步原理。扩展案例：调用设备传感器（光线传感器、陀螺仪）实现简单的物联网数据采集与展示场景。

**实战案例**：开发"智慧天气"应用，展示当前天气信息，在手机和平板上自适应显示，集成传感器展示环境数据，体验鸿蒙多端统一开发能力。

### 三、开发任务清单

| 任务阶段 | 主要内容 | 关键技术点 |
|----------|----------|------------|
| 天气应用 | ArkUI开发 | @State、数据绑定 |
| 多端适配 | 响应式布局 | 断点系统、媒体查询 |
| 传感器 | 光线/陀螺仪 | 传感器API调用 |
| 分布式 | 数据同步 | 分布式能力演示 |

### 四、实验步骤详解

#### 第一课时：天气应用开发与多端适配

##### 1.1 需求分析

**功能需求**：
- 天气展示：城市名称、温度、天气状况、空气质量
- 多端适配：手机竖屏布局、平板横屏布局
- 传感器需求：光线传感器（自动亮度）、陀螺仪（动态效果）

##### 1.2 创建鸿蒙项目

1. 打开DevEco Studio
2. 新建Empty Ability项目
3. 选择ArkTS语言
4. 命名为WeatherApp

##### 1.3 AI辅助编码

**使用TRAE生成天气页面代码**：
- 描述需求："ArkTS天气应用页面，声明式UI，城市温度展示"
- AI生成代码片段

**天气首页实现**：
```typescript
@Entry
@Component
struct Index {
  @State cityName: string = '合肥';
  @State temperature: number = 22;
  @State weather: string = '晴';
  @State aqi: number = 45;
  
  build() {
    Column() {
      Text(this.cityName)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 50 })
      
      Text(this.weather === '晴' ? '☀️' : '⛅')
        .fontSize(80)
        .margin({ top: 20 })
      
      Text(`${this.temperature}°C`)
        .fontSize(60)
        .fontWeight(FontWeight.Lighter)
        .margin({ top: 20 })
      
      Text(this.weather)
        .fontSize(20)
        .margin({ top: 10 })
      
      Row() {
        Text('空气质量: ')
        Text(`${this.aqi} - 优`)
          .fontColor(this.aqi <= 50 ? '#00ff00' : '#ff9900')
      }
      .margin({ top: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f5f5f5')
  }
}
```

##### 1.4 多端适配布局

**响应式布局实现**：
```typescript
@State currentBreakpoint: string = 'md';

aboutToAppear() {
  let windowWidth = window.getWindow().getWindowProperties().windowWidth;
  
  if (windowWidth < 600) {
    this.currentBreakpoint = 'sm'; // 手机
  } else if (windowWidth < 840) {
    this.currentBreakpoint = 'md'; // 平板竖屏
  } else {
    this.currentBreakpoint = 'lg'; // 平板横屏
  }
}

build() {
  if (this.currentBreakpoint === 'sm') {
    Column() {
      this.phoneLayout()
    }
  } else {
    Row() {
      this.tabletLayout()
    }
  }
}

@Builder phoneLayout() {
  Column() {
    Text(this.cityName).fontSize(24)
    Text(`${this.temperature}°C`).fontSize(60)
  }
}

@Builder tabletLayout() {
  Column() {
    Text(this.cityName).fontSize(32)
    Text(`${this.temperature}°C`).fontSize(80)
  }
  .width('40%')
}
```

#### 第二课时：传感器集成与分布式能力

##### 2.1 光线传感器开发

```typescript
import sensor from '@ohos.sensor';

@State lightIntensity: number = 0;

aboutToAppear() {
  sensor.on(sensor.SensorType.SENSOR_TYPE_ID_LIGHT, (data) => {
    this.lightIntensity = data.light;
  });
}

aboutToDisappear() {
  sensor.off(sensor.SensorType.SENSOR_TYPE_ID_LIGHT);
}

Text(`环境光线: ${this.lightIntensity} lux`)
  .fontSize(16)
  .margin({ top: 10 })
```

##### 2.2 陀螺仪传感器开发

```typescript
@State rotateX: number = 0;
@State rotateY: number = 0;
@State rotateZ: number = 0;

aboutToAppear() {
  sensor.on(sensor.SensorType.SENSOR_TYPE_ID_GYROSCOPE, (data) => {
    this.rotateX = data.x;
    this.rotateY = data.y;
    this.rotateZ = data.z;
  });
}

Row() {
  Column() { Text(`X轴: ${this.rotateX.toFixed(2)}`) }
  Column() { Text(`Y轴: ${this.rotateY.toFixed(2)}`) }
  Column() { Text(`Z轴: ${this.rotateZ.toFixed(2)}`) }
}
.spacing(20)
```

##### 2.3 分布式数据同步

```typescript
import distributedData from '@ohos.data.distributedData';

const KVManager = distributedData.createKVManager({
  bundleName: 'com.example.weather',
  kvStoreType: distributedData.KVStoreType.SINGLE_VERSION
});

async function saveData(key: string, value: string) {
  const kvStore = await KVManager.getKVStore('weatherStore');
  await kvStore.put(key, value);
}

async function getData(key: string) {
  const kvStore = await KVManager.getKVStore('weatherStore');
  return await kvStore.get(key);
}
```

### 五、难重点指导

#### 重点
- ArkUI声明式开发
- @State状态管理
- 响应式布局断点系统

#### 难点
- **传感器权限申请**：config.json配置
- **分布式数据同步**：需要同一华为账号
- **多端适配测试**：需要多设备模拟器

#### AI解决技巧
1. 代码生成：描述ArkUI需求让TRAE生成
2. 传感器问题：询问"鸿蒙传感器API使用"
3. 分布式开发：询问"分布式数据管理配置"

### 六、成功标准

- [ ] 天气应用功能完整
- [ ] 手机/平板界面自适应
- [ ] 传感器数据正常采集
- [ ] 多端适配效果良好
- [ ] 技术分析报告完成

### 七、技术分析报告模板

```markdown
# 多端适配与硬件集成技术分析报告

## 1. 多端适配分析
- 手机布局特点
- 平板布局特点
- 断点系统实现

## 2. 传感器集成分析
- 光线传感器应用场景
- 陀螺仪应用场景
- 数据采集准确性

## 3. 分布式能力分析
- 分布式数据管理原理
- 跨设备同步实现

## 4. 技术选型建议
```

### 八、评价标准（100分）

| 评分项 | 分值 | 评价标准 |
|--------|------|----------|
| 多端适配 | 30分 | 手机与平板布局差异合理；响应式切换准确 |
| 数据同步 | 30分 | 跨设备数据实时同步，无延迟或错误；分布式存储逻辑正确 |
| 代码设计 | 20分 | 数据模型清晰，布局结构合理；代码可维护性高 |
| 团队协作 | 20分 | 分工明确，任务衔接顺畅；成果完整无遗漏 |

---

## 实验六：跨平台综合项目实战

### 一、实验项目基本信息

| 项目 | 内容 |
|------|------|
| **实验编号** | d20301035106、d20301009206 |
| **学时分配** | 6学时 |
| **实验类型** | 综合型 |
| **每组人数** | 6人（团队协作） |
| **对应课程目标** | 课程目标1、2、3、4：综合应用 |

### 二、实验任务与案例

**核心任务**：团队开发某业务应用（建议选题涉及传感器或硬件交互场景，如运动健康、智能家居控制等），每人负责一个技术栈（Android/Flutter/React Native/Uniapp/MAUI/微信小程序），使用Git进行版本控制与协作，借助AI编程工具辅助代码生成与调试。

**实战案例**：团队开发"智慧健康"运动监测应用，支持步数统计（加速度计）、心率监测（模拟）、运动记录、数据同步。每人负责一个技术栈实现，组内进行技术分享与对比分析。

### 三、开发任务清单

| 任务阶段 | 主要内容 | 关键技术点 |
|----------|----------|------------|
| 项目规划 | 需求分析、技术选型 | 团队协作、方案设计 |
| 多人开发 | 分工协作、Git管理 | 分支管理、代码合并 |
| 多端实现 | 6个技术栈开发 | Android/iOS/Flutter/RN/Uniapp/MAUI |
| 测试上线 | 功能测试、跨端测试 | 测试用例、问题修复 |
| 报告撰写 | 技术总结、选型分析 | 技术对比，分析报告 |

### 四、实验步骤详解

#### 第一课时：项目规划与需求分析

##### 1.1 确定项目选题

**可选项目**：
- 智慧健康（运动监测）
- 智慧家居（设备控制）
- 智慧校园（校园服务）

**确定功能需求**：
- 用户登录
- 数据展示
- 传感器数据采集
- 本地存储

##### 1.2 技术选型方案

```
团队分工（6人）：
- 成员1：Android原生开发（Kotlin）
- 成员2：Flutter开发（Dart）
- 成员3：React Native开发（JavaScript）
- 成员4：Uniapp开发（Vue）
- 成员5：MAUI开发（C#）
- 成员6：微信小程序开发
```

##### 1.3 编写需求文档

```markdown
# 智慧健康应用需求文档

## 1. 功能需求
- 用户登录
- 步数统计展示
- 运动记录列表
- 数据本地存储

## 2. 技术要求
- 各技术栈独立实现
- Git协作开发
- AI辅助编码
```

#### 第二课时：Git协作与开发环境准备

##### 2.1 Git团队协作配置

**创建Git仓库**：
```bash
git init smart-health
cd smart-health

git checkout -b develop

git checkout -b feature/android
git checkout -b feature/flutter
git checkout -b feature/react-native
git checkout -b feature/uniapp
git checkout -b feature/maui
git checkout -b feature/wechat
```

**编写.gitignore**：
```
node_modules/
.gradle/
build/
*.apk
*.ipa
dist/
```

##### 2.2 项目初始化

**各技术栈项目创建**：
```bash
# Android
android-studio -> SmartHealth

# Flutter
flutter create smart_health_flutter

# React Native
npx react-native-init SmartHealthRN

# Uniapp
HBuilderX -> 新建uni-app

# MAUI
Visual Studio -> 新建MAUI项目

# 微信小程序
微信开发者工具 -> 新建项目
```

#### 第三四课时：多端开发实现

##### 3.1 Android开发

```kotlin
class MainActivity : AppCompatActivity() {
    private lateinit var tvStepCount: TextView
    private var stepCount = 0
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        tvStepCount = findViewById(R.id.tv_step_count)
        
        Timer().schedule(object : TimerTask() {
            override fun run() {
                runOnUiThread {
                    stepCount += Math.random() * 10
                    tvStepCount.text = "步数: ${stepCount.toInt()}"
                }
            }
        }, 0, 1000)
    }
}
```

##### 3.2 Flutter开发

```dart
class StepCounter extends ChangeNotifier {
  int _steps = 0;
  int get steps => _steps;
  
  void increment() {
    _steps++;
    notifyListeners();
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('智慧健康')),
      body: Consumer<StepCounter>(
        builder: (context, counter, child) {
          return Center(
            child: Text('步数: ${counter.steps}'),
          );
        },
      ),
    );
  }
}
```

##### 3.3 React Native开发

```jsx
const App = () => {
  const [steps, setSteps] = useState(0);
  
  useEffect(() => {
    const interval = setInterval(() => {
      setSteps(s => s + Math.floor(Math.random() * 10));
    }, 1000);
    return () => clearInterval(interval);
  }, []);
  
  return (
    <View style={styles.container}>
      <Text style={styles.text}>步数: {steps}</Text>
    </View>
  );
};
```

##### 3.4 Uniapp开发

```vue
<template>
  <view class="container">
    <text class="title">智慧健康</text>
    <text class="steps">步数: {{steps}}</text>
  </view>
</template>

<script>
export default {
  data() {
    return { steps: 0 }
  },
  onLoad() {
    setInterval(() => {
      this.steps += Math.floor(Math.random() * 10);
    }, 1000);
  }
}
</script>
```

##### 3.5 MAUI开发

```csharp
public partial class MainPage : ContentPage
{
    public MainPage()
    {
        InitializeComponent();
        
        Device.StartTimer(TimeSpan.FromSeconds(1), () =>
        {
            Steps += Random.Shared.Next(10);
            return true;
        });
    }
    
    public static readonly BindableProperty StepsProperty = 
        BindableProperty.Create(nameof(Steps), typeof(int), typeof(MainPage), 0);
    
    public int Steps
    {
        get => (int)GetValue(StepsProperty);
        set => SetValue(StepsProperty, value);
    }
}
```

##### 3.6 微信小程序开发

```javascript
Page({
  data: {
    steps: 0
  },
  
  onLoad() {
    setInterval(() => {
      this.setData({
        steps: this.data.steps + Math.floor(Math.random() * 10)
      });
    }, 1000);
  }
});
```

#### 第五课时：测试验证与打包部署

##### 4.1 测试验证

**测试用例**：
```markdown
## 功能测试
- [ ] 应用启动正常
- [ ] 步数统计显示
- [ ] 数据更新正常
- [ ] 页面切换流畅

## 兼容性测试
- [ ] 各平台运行正常
- [ ] 界面显示正确
- [ ] 性能表现良好
```

##### 4.2 打包部署

```bash
# Android
./gradlew assembleRelease

# Flutter
flutter build apk --release

# React Native
npx react-native build-android

# MAUI
dotnet publish -f net8.0-android
```

#### 第六课时：技术选型对比报告

##### 5.1 技术选型对比报告模板

```markdown
# 技术选型对比报告

## 1. 各技术栈开发效率对比
| 技术栈 | 开发用时 | 代码量 | 难度评分 |
|--------|----------|--------|----------|
| Android | X小时 | Y行 | Z分 |
| Flutter | X小时 | Y行 | Z分 |
| React Native | X小时 | Y行 | Z分 |
| Uniapp | X小时 | Y行 | Z分 |
| MAUI | X小时 | Y行 | Z分 |
| 微信小程序 | X小时 | Y行 | Z分 |

## 2. 性能对比
- 启动速度
- 内存占用
- 流畅度

## 3. 适用场景分析

## 4. 技术选型建议
```

##### 5.2 项目总结报告模板

```markdown
# 项目总结报告

## 1. 项目概述
- 项目名称
- 开发目标
- 团队成员

## 2. 开发过程
- 需求分析
- 技术选型
- 开发实现
- 测试上线

## 3. 收获与体会
- 技术成长
- 团队协作
- AI工具使用

## 4. 问题与改进
- 遇到的问题
- 解决方案
- 改进方向
```

### 五、难重点指导

#### 重点
- Git团队协作流程
- 多端功能实现
- 技术选型分析

#### 难点
- **分支冲突解决**：使用git merge/rebase处理
- **API接口统一**：制定统一的API规范
- **测试覆盖完整**：各平台测试用例编写

#### AI解决技巧
1. Git问题：询问"Git冲突解决方法"
2. 代码问题：描述错误让TRAE分析
3. 报告撰写：询问"技术报告结构建议"

### 六、成功标准

- [ ] 6个技术栈应用均可运行
- [ ] Git团队协作流程规范
- [ ] AI辅助开发流程体验良好
- [ ] 技术选型对比报告完整
- [ ] 项目总结报告完成

### 七、评价标准（100分）

| 评分项 | 分值 | 评价标准 |
|--------|------|----------|
| 功能完整性 | 25分 | 3个模块功能均实现，无关键缺失；交互逻辑正确 |
| 多端一致性 | 20分 | 不同版本功能和数据同步；用户体验统一，风格一致 |
| AI工具应用 | 15分 | 有效使用TRAE提高开发效率；有具体应用案例和效果分析 |
| 技术报告 | 20分 | 选型理由充分，框架对比客观；结论具有参考价值 |
| 团队协作 | 20分 | 分工明确，文档完整；项目管理规范，开发过程记录详细 |

---

## 实验课程总结

### 移动应用开发技术栈汇总

| 技术方向 | 代表框架/工具 | 适用场景 |
|----------|---------------|----------|
| Android原生 | Kotlin + Android Studio | 高性能应用、游戏 |
| iOS原生 | Swift + Xcode | 高性能应用、AR/VR |
| 跨平台框架 | Flutter | 统一UI、高性能 |
| 跨平台框架 | React Native | Web开发者转型 |
| 多端开发 | Uniapp | 快速开发、小程序 |
| 跨平台框架 | MAUI | .NET开发者 |
| 轻量应用 | 微信小程序 | 快速上线、流量入口 |
| 国产系统 | 鸿蒙HarmonyOS | 多端统一、物联网 |

### AI辅助开发技巧汇总

1. **代码生成**：使用自然语言描述需求，AI生成基础代码框架
2. **错误诊断**：将错误信息粘贴给AI，获取解决方案
3. **性能优化**：询问特定框架的性能优化建议
4. **文档生成**：让AI辅助生成注释和文档
5. **代码审查**：使用AI进行代码质量检查

### 课程考核评价体系

| 实验 | 考核内容 | 权重 |
|------|----------|------|
| 实验一 | 环境搭建完成度 | 10% |
| 实验二 | 原生开发功能 | 15% |
| 实验三 | 跨平台开发能力 | 15% |
| 实验四 | 小程序开发 | 15% |
| 实验五 | 鸿蒙多端开发 | 15% |
| 实验六 | 综合项目实战 | 30% |

---

**文档版本**：V2.0

**编制日期**：2026年2月

**编制单位**：计算机与信息工程学院

**编制人**：刘东良
