# 实验二：原生应用开发

## 实验项目基本信息

- **实验编号**：d20301035102、d20301009202
- **学时分配**：4学时
- **实验类型**：验证型
- **每组人数**：6人
- **对应课程目标**：课程目标1

## 🎯 核心步骤列表

### 📋 实验概览
1. **需求分析阶段**：编写登录功能需求文档（输入验证规则、页面跳转逻辑）
2. **AI辅助编码阶段**：使用TRAE生成登录页面骨架代码并完善业务逻辑
3. **测试验证阶段**：编写输入验证测试用例，验证边界条件
4. **部署运维阶段**：打包调试版本，记录平台差异对比报告

### 🏗️ 开发任务清单
| 任务阶段 | 主要内容 | 关键技术点 |
|----------|----------|------------|
| Android登录 | Kotlin + Activity跳转 | EditText、Intent、Bundle |
| iOS登录 | SwiftUI + ViewController | @State、Navigation |
| 组内对比 | 技术分享 | 平台差异分析 |

### ✅ 成功标准
- [ ] Android登录页面功能完整
- [ ] iOS登录页面功能完整
- [ ] Activity跳转与数据传递正常
- [ ] 输入验证逻辑正确
- [ ] 平台差异对比报告完成

---

## 实验任务与案例

### 核心任务
使用Kotlin实现Android登录页面（EditText输入验证、Activity跳转与数据传递），使用SwiftUI实现iOS登录页面，组内成员选择不同平台实现同一功能，完成后进行技术对比分享。

### 实战案例
开发"智慧校园"登录模块，学生在登录页面输入学号和密码，系统验证成功后跳转到个人中心页面，显示个性化的欢迎信息和用户资料。

---

## 第一课时：Android登录页面设计（2学时）

### 2.1 需求分析阶段

#### 步骤1：编写需求文档
1. **功能需求**
   - 用户名输入（学号）
   - 密码输入
   - 登录按钮
   - 输入验证（不能为空、长度限制）

2. **界面需求**
   - Material Design风格
   - 输入框占位提示
   - 密码隐藏显示

3. **跳转需求**
   - 登录成功 → 个人中心
   - 传递用户名数据

### 2.2 Android项目创建

#### 步骤1：创建项目

1. 打开Android Studio
2. 创建Empty Activity项目
3. 选择Kotlin语言
4. 最低SDK：API 24

### 2.3 AI辅助编码

#### 步骤1：生成登录页面代码
1. 使用TRAE描述需求：Kotlin登录页面，EditText输入验证，Activity跳转
2. AI生成代码片段
3. 手动完善业务逻辑

#### 步骤2：实现布局

```xml
<!-- activity_login.xml -->
<LinearLayout
    android:orientation="vertical"
    android:padding="16dp">
    
    <EditText
        android:id="@+id/et_username"
        android:hint="请输入学号"
        android:inputType="text"/>
    
    <EditText
        android:id="@+id/et_password"
        android:hint="请输入密码"
        android:inputType="textPassword"/>
    
    <Button
        android:id="@+id/btn_login"
        android:text="登录"/>
</LinearLayout>
```

#### 步骤3：实现登录逻辑
```kotlin
// LoginActivity.kt
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
            // 跳转到个人中心
            val intent = Intent(this, HomeActivity::class.java)
            intent.putExtra("username", username)
            startActivity(intent)
        } else {
            Toast.makeText(this, "用户名或密码错误", Toast.LENGTH_SHORT).show()
        }
    }
}
```

### 2.4 创建个人中心页面

#### 步骤1：创建HomeActivity
1. 新建Activity：HomeActivity
2. 布局显示欢迎信息

#### 步骤2：接收传递数据
```kotlin
// HomeActivity.kt
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

---

## 第二课时：iOS登录与平台对比（2学时）

### 2.5 iOS登录实现（演示/模拟器）

#### 步骤1：创建SwiftUI项目
1. 打开Xcode
2. 创建SwiftUI项目
3. 命名为NativeLogin

#### 步骤2：AI辅助生成SwiftUI代码
1. 使用TRAE描述需求：SwiftUI登录页面，Navigation导航
2. 生成代码片段

#### 步骤3：实现登录页面
```swift
// ContentView.swift
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

#### 步骤4：创建个人中心页面
```swift
// HomeView.swift
struct HomeView: View {
    let username: String
    
    var body: some View {
        VStack {
            Text("欢迎 \(username)")
                .font(.largeTitle)
                .padding()
        }
        .navigationTitle("个人中心")
    }
}
```

### 2.6 测试验证阶段

#### 步骤1：编写测试用例
1. 输入测试
2.为空 用户名格式测试
3. 密码长度测试
4. 正确凭证测试

#### 步骤2：执行测试
1. 在模拟器上运行
2. 验证边界条件
3. 记录测试结果

### 2.7 平台差异对比

#### 步骤1：整理对比报告
| 对比项 | Android | iOS |
|--------|---------|-----|
| 开发语言 | Kotlin | Swift |
| UI框架 | XML/Compose | SwiftUI |
| 页面跳转 | Intent | NavigationLink |
| 数据传递 | Intent.putExtra | @Binding |

#### 步骤2：组内技术分享
1. 各成员介绍实现方案
2. 讨论平台差异
3. 总结技术选型考虑

---

## 总结与思考

### 实验总结
- 掌握Android Kotlin登录页面开发
- 理解iOS SwiftUI登录实现
- 学会Activity间数据传递
- 完成平台差异对比分析

### 课后思考
1. 原生开发相比跨平台的优势和劣势
2. 如何选择原生开发vs跨平台开发
3. AI辅助代码生成对开发效率的影响
