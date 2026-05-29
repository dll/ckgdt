# 移动应用开发实验报告

## 封面信息

| 项目 | 内容 |
|------|------|
| 实验名称 | 跨平台综合项目实战 |
| 实验编号 | d20301035106、d20301009206 |
| 学号 | __________________ |
| 姓名 | __________________ |
| 班级 | __________________ |
| 日期 | __________________ |
| 组别 | __________________ |
| 项目名称 | 智慧健康运动监测应用 |
| 负责技术栈 | Android / Flutter / React Native / Uniapp / MAUI / 微信小程序 |

## 实验目的

1. 掌握多技术栈开发能力
2. 体验Git团队协作流程
3. 学会AI辅助开发
4. 完成技术选型分析

## 实验环境

| 技术栈 | 开发工具 | 语言 | 主要依赖 |
|--------|----------|------|----------|
| Android | Android Studio | Kotlin | - |
| Flutter | Android Studio/VS Code | Dart | provider |
| React Native | VS Code | JavaScript | axios |
| Uniapp | HBuilderX | Vue | uni.request |
| MAUI | Visual Studio | C# | - |
| 微信小程序 | 微信开发者工具 | JavaScript | - |

## 第一部分：项目规划与需求分析

### 1. 项目选题
- [ ] 智慧健康（运动监测）
- [ ] 智慧家居（设备控制）
- [ ] 智慧校园（校园服务）

### 2. 功能需求

| 功能模块 | 具体需求 | 技术实现 |
|----------|----------|----------|
| 用户登录 | 学号密码登录 | 各平台实现 |
| 步数统计 | 加速度计数据采集 | 传感器API |
| 运动记录 | 历史数据展示 | 本地存储 |
| 数据同步 | 跨设备数据同步 | 网络请求 |

### 3. 团队分工

| 成员 | 技术栈 | 负责模块 |
|------|--------|----------|
| 成员1 | Android | 登录、计步 |
| 成员2 | Flutter | 登录、计步 |
| 成员3 | React Native | 登录、计步 |
| 成员4 | Uniapp | 登录、计步 |
| 成员5 | MAUI | 登录、计步 |
| 成员6 | 微信小程序 | 登录、计步 |

## 第二部分：Git团队协作

### 1. Git仓库创建
```bash
# 创建项目仓库
git init smart-health
cd smart-health

# 创建开发分支
git checkout -b develop

# 创建功能分支
git checkout -b feature/android
git checkout -b feature/flutter
git checkout -b feature/react-native
git checkout -b feature/uniapp
git checkout -b feature/maui
git checkout -b feature/wechat
```

### 2. .gitignore配置
```
# 各平台忽略文件
node_modules/
.gradle/
build/
*.apk
*.ipa
dist/
```

### 3. 代码提交规范
- 提交信息格式：`[功能模块] 具体修改内容`
- 定期拉取最新代码：`git pull origin develop`
- 提交前进行代码审查

## 第三部分：多端实现

### 1. Android开发

#### 1.1 核心代码
```kotlin
// MainActivity.kt - 计步器核心
class MainActivity : AppCompatActivity() {
    
    private lateinit var tvStepCount: TextView
    private var stepCount = 0
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        tvStepCount = findViewById(R.id.tv_step_count)
        
        // 模拟步数更新
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

### 2. Flutter开发

#### 2.1 核心代码
```dart
// main.dart
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

### 3. React Native开发

#### 3.1 核心代码
```jsx
// App.js
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

### 4. Uniapp开发

#### 4.1 核心代码
```vue
<!-- pages/index/index.vue -->
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

### 5. MAUI开发

#### 5.1 核心代码
```csharp
// MainPage.xaml.cs
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

### 6. 微信小程序开发

#### 6.1 核心代码
```javascript
// pages/index/index.js
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

```xml
<!-- pages/index/index.wxml -->
<view class="container">
  <text>智慧健康</text>
  <text>步数: {{steps}}</text>
</view>
```

## 第四部分：测试验证与打包部署

### 1. 测试用例

| 测试项 | 预期结果 | 实际结果 |
|--------|----------|----------|
| 应用启动 | 正常启动 | |
| 步数统计 | 实时更新 | |
| 页面切换 | 流畅无卡顿 | |
| 数据存储 | 数据持久化 | |

### 2. 打包部署

| 平台 | 打包命令 | 部署方式 |
|------|----------|----------|
| Android | `./gradlew assembleRelease` | APK安装 |
| Flutter | `flutter build apk --release` | APK安装 |
| React Native | `npx react-native build-android` | APK安装 |
| MAUI | `dotnet publish -f net8.0-android` | APK安装 |
| 微信小程序 | 上传体验版 | 二维码扫描 |

## 第五部分：技术选型对比报告

### 1. 开发效率对比

| 技术栈 | 开发用时 | 代码量 | 难度评分 |
|--------|----------|--------|----------|
| Android | | | |
| Flutter | | | |
| React Native | | | |
| Uniapp | | | |
| MAUI | | | |
| 微信小程序 | | | |

### 2. 性能对比

| 技术栈 | 启动速度 | 内存占用 | 流畅度 |
|--------|----------|----------|--------|
| Android | | | |
| Flutter | | | |
| React Native | | | |
| Uniapp | | | |
| MAUI | | | |
| 微信小程序 | | | |

### 3. 适用场景分析

| 技术栈 | 适用场景 | 优势 | 劣势 |
|--------|----------|------|------|
| Android | 原生应用开发 | 性能最佳 | 开发成本高 |
| Flutter | 跨平台开发 | 性能接近原生 | 学习成本中等 |
| React Native | 跨平台开发 | 生态成熟 | 性能略差 |
| Uniapp | 多端开发 | 开发效率高 | 性能一般 |
| MAUI | 跨平台开发 | .NET生态 | 生态相对薄弱 |
| 微信小程序 | 轻量级应用 | 用户基数大 | 功能受限 |

## 第六部分：项目总结报告

### 1. 项目概述
- 项目名称：智慧健康运动监测应用
- 开发目标：实现多平台运动数据监测
- 团队成员：6人

### 2. 开发过程
- 需求分析：确定功能需求和技术选型
- 技术选型：选择6个主流技术栈
- 开发实现：各成员独立开发
- 测试上线：功能测试和兼容性测试

### 3. 收获与体会
- 技术成长：掌握了多技术栈开发
- 团队协作：体验了Git团队协作流程
- AI工具使用：学会了使用AI辅助开发

### 4. 问题与改进
- 遇到的问题：
- 解决方案：
- 改进方向：

## 实验结果

### 验证结果

| 技术栈 | 应用运行 | 功能完整 | 性能表现 |
|--------|----------|----------|----------|
| Android | [ ] 成功 | [ ] 成功 | [ ] 良好 |
| Flutter | [ ] 成功 | [ ] 成功 | [ ] 良好 |
| React Native | [ ] 成功 | [ ] 成功 | [ ] 良好 |
| Uniapp | [ ] 成功 | [ ] 成功 | [ ] 良好 |
| MAUI | [ ] 成功 | [ ] 成功 | [ ] 良好 |
| 微信小程序 | [ ] 成功 | [ ] 成功 | [ ] 良好 |

### 截图记录

#### Android运行截图
![Android运行截图](路径)

#### Flutter运行截图
![Flutter运行截图](路径)

#### React Native运行截图
![React Native运行截图](路径)

#### Uniapp运行截图
![Uniapp运行截图](路径)

#### MAUI运行截图
![MAUI运行截图](路径)

#### 微信小程序运行截图
![微信小程序运行截图](路径)

## 考核指标

| 考核项 | 评分标准 | 得分 |
|--------|----------|------|
| 功能完整性 | 各技术栈应用功能完整 | 20分 |
| 代码质量 | 代码结构清晰，注释完整 | 15分 |
| 团队协作 | Git流程规范，协作良好 | 20分 |
| 多端实现 | 至少完成3个技术栈的开发 | 25分 |
| 技术对比 | 完成技术选型分析报告 | 10分 |
| 实验报告 | 报告结构完整，内容详实 | 10分 |

## 教师评价

| 项目 | 评价 |
|------|------|
| 实验完成情况 | |
| 技术掌握程度 | |
| 团队协作 | |
| 创新点 | |
| 综合评价 | |
| 成绩 | |

**教师签名：** ___________________
**日期：** ___________________