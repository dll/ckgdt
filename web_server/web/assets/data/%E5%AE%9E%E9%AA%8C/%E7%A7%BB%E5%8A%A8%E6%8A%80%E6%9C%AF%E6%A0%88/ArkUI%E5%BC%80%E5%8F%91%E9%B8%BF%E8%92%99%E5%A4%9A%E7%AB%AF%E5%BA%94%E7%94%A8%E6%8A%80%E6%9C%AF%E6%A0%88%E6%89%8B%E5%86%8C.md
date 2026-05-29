# ArkUI开发鸿蒙多端应用技术栈手册

## 一、技术栈概述

### 1.1 核心技术
- **编程语言**：ArkTS
- **开发框架**：HarmonyOS SDK
- **UI框架**：ArkUI（声明式UI框架）
- **构建工具**：hvigor
- **IDE**：DevEco Studio
- **版本要求**：ArkTS 4.0+, HarmonyOS API 9+

### 1.2 依赖管理
- **包管理**：ohpm（OpenHarmony Package Manager）
- **依赖仓库**：HarmonyOS官方仓库
- **版本控制**：Git

### 1.3 测试框架
- **单元测试**：@ohos/hypium
- **UI测试**：ArkUI Test
- **集成测试**：HarmonyOS Test Framework

## 二、环境搭建

### 2.1 开发环境配置

```typescript
// build-profile.json5
{
  "app": {
    "signingConfigs": [],
    "compileSdkVersion": 9,
    "compatibleSdkVersion": 9,
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compatibleSdkVersion": 9,
        "runtimeOS": "HarmonyOS"
      }
    ]
  }
}
```

### 2.2 依赖配置

```typescript
// oh-package.json5
{
  "name": "harmony-app",
  "version": "1.0.0",
  "description": "HarmonyOS应用",
  "main": "",
  "author": "",
  "license": "",
  "dependencies": {
    "@ohos/hypium": "^1.0.6",
    "@ohos/axios": "^2.2.0",
    "@ohos/common": "^1.0.0"
  },
  "devDependencies": {
    "@ohos/hypium": "^1.0.6"
  }
}
```

## 三、基础语法与特性

### 3.1 ArkTS基础语法

#### 3.1.1 变量声明

```typescript
// let：可变变量
let count: number = 0;
count++;

// const：不可变变量
const name: string = "张三";

// 类型推断
const message = "Hello ArkTS"; // 自动推断为string
const number = 100; // 自动推断为number

// 数组类型
const numbers: number[] = [1, 2, 3, 4, 5];

// 对象类型
interface User {
  id: number;
  name: string;
  email: string;
}

const user: User = {
  id: 1,
  name: "李四",
  email: "lisi@example.com"
};
```

#### 3.1.2 函数定义

```typescript
// 基本函数
function greet(name: string): string {
  return `你好，${name}`;
}

// 箭头函数
const add = (a: number, b: number): number => a + b;
const result = add(3, 5);

// 可选参数
function createUser(name: string, age: number = 18): User {
  console.log(`创建用户：${name}，年龄：${age}`);
  return { id: 0, name, age };
}

// 异步函数
async function fetchData(): Promise<User[]> {
  const response = await fetch('https://api.example.com/users');
  return await response.json();
}
```

#### 3.1.3 类定义

```typescript
// 类定义
class Person {
  private _name: string;
  private _age: number;

  constructor(name: string, age: number) {
    this._name = name;
    this._age = age;
  }

  // getter和setter
  get name(): string {
    return this._name;
  }

  set name(value: string) {
    this._name = value;
  }

  // 方法
  introduce(): string {
    return `我叫${this._name}，今年${this._age}岁`;
  }
}

// 使用类
const person = new Person("王五", 25);
console.log(person.introduce());
```

#### 3.1.4 装饰器

```typescript
// @Entry：页面入口
@Entry
@Component
struct HomePage {
  @State count: number = 0;

  build() {
    Column() {
      Text(`计数：${this.count}`)
      Button('增加')
        .onClick(() => {
          this.count++;
        })
    }
  }
}

// @State：状态管理
@Component
struct Counter {
  @State count: number = 0;

  build() {
    Row() {
      Button('减少')
        .onClick(() => {
          this.count--;
        })
      Text(`${this.count}`)
    }
  }
}

// @Prop：属性传递
@Component
struct ChildComponent {
  @Prop title: string = "";
  @Prop count: number = 0;

  build() {
    Text(`${this.title}：${this.count}`)
  }
}
```

### 3.2 ArkUI特性

#### 3.2.1 声明式UI

```typescript
@Entry
@Component
struct WeatherPage {
  @State temperature: number = 25;
  @State weather: string = "晴天";

  build() {
    Column() {
      // 天气卡片
      Column() {
        Text('当前天气')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        
        Text(`${this.temperature}°C`)
          .fontSize(48)
          .fontColor(this.weather === '晴天' ? '#FF6B35' : '#4A90E2')
        
        Text(this.weather)
          .fontSize(20)
          .margin({ top: 8 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: 4 })
    }
  }
}
```

#### 3.2.2 列表渲染

```typescript
@Entry
@Component
struct UserListPage {
  @State users: User[] = [
    { id: 1, name: '张三', email: 'zhangsan@example.com' },
    { id: 2, name: '李四', email: 'lisi@example.com' },
    { id: 3, name: '王五', email: 'wangwu@example.com' }
  ];

  build() {
    List({ space: 12 }) {
      ForEach(this.users, (item: User) => item.id.toString(), (item: User) => {
        ListItem() {
          UserItem({ user: item })
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}

@Component
struct UserItem {
  @Prop user: User;

  build() {
    Row() {
      // 用户头像
      Image($r('app.media.icon'))
        .width(48)
        .height(48)
        .borderRadius(24)
        .margin({ right: 12 })
      
      Column() {
        Text(this.user.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        
        Text(this.user.email)
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 4 })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }
}
```

#### 3.2.3 状态管理

```typescript
// @State：组件内部状态
@Component
struct StateExample {
  @State count: number = 0;
  @State message: string = "Hello";

  build() {
    Column() {
      Text(this.message)
      Text(`计数：${this.count}`)
      Button('增加')
        .onClick(() => {
          this.count++;
          this.message = "计数已更新";
        })
    }
  }
}

// @Prop：父组件传递属性
@Component
struct ParentComponent {
  @State parentCount: number = 0;

  build() {
    Column() {
      ChildComponent({ 
        count: this.parentCount,
        onCountChange: (value: number) => {
          this.parentCount = value;
        }
      })
    }
  }
}

@Component
struct ChildComponent {
  @Prop count: number = 0;
  onCountChange?: (value: number) => void;

  build() {
    Row() {
      Button('减少')
        .onClick(() => {
          const newValue = this.count - 1;
          if (this.onCountChange) {
            this.onCountChange(newValue);
          }
        })
      Text(`${this.count}`)
    }
  }
}
```

## 四、ArkUI组件开发

### 4.1 基础组件

#### 4.1.1 文本组件

```typescript
@Entry
@Component
struct TextExample {
  build() {
    Column({ space: 16 }) {
      // 普通文本
      Text('Hello HarmonyOS')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      
      // 多行文本
      Text('这是一段很长的文本内容，需要换行显示。')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(16)
      
      // 富文本
      Text() {
        Span('红色文字')
          .fontColor('#FF0000')
          .fontSize(18)
        Span('蓝色文字')
          .fontColor('#0000FF')
          .fontSize(18)
      }
    }
    .padding(20)
  }
}
```

#### 4.1.2 按钮组件

```typescript
@Entry
@Component
struct ButtonExample {
  @State isLoading: boolean = false;

  build() {
    Column({ space: 12 }) {
      // 普通按钮
      Button('点击我')
        .onClick(() => {
          console.log('按钮被点击');
        })
      
      // 图标按钮
      Button() {
        Image($r('app.media.icon'))
          .width(24)
          .height(24)
      }
      .type(ButtonType.Circle)
      
      // 加载按钮
      Button(this.isLoading ? '加载中...' : '提交')
        .enabled(!this.isLoading)
        .onClick(() => {
          this.isLoading = true;
          // 模拟异步操作
          setTimeout(() => {
            this.isLoading = false;
          }, 2000);
        })
      
      // 自定义样式按钮
      Button('自定义按钮')
        .backgroundColor('#4CAF50')
        .fontColor('#FFFFFF')
        .borderRadius(20)
    }
    .padding(20)
  }
}
```

#### 4.1.3 输入框组件

```typescript
@Entry
@Component
struct InputExample {
  @State username: string = "";
  @State password: string = "";
  @State showPassword: boolean = false;

  build() {
    Column({ space: 16 }) {
      // 用户名输入
      TextInput({ placeholder: '请输入用户名', text: this.username })
        .onChange((value: string) => {
          this.username = value;
        })
        .maxLength(20)
      
      // 密码输入
      TextInput({ 
        placeholder: '请输入密码', 
        text: this.password,
        type: this.showPassword ? InputType.Normal : InputType.Password 
      })
        .onChange((value: string) => {
          this.password = value;
        })
        .showPasswordIcon(true)
        .onPasswordIconClick(() => {
          this.showPassword = !this.showPassword;
        })
      
      // 多行输入
      TextArea({ placeholder: '请输入描述' })
        .height(100)
        .maxLength(200)
    }
    .padding(20)
  }
}
```

### 4.2 布局组件

#### 4.2.1 Flex布局

```typescript
@Entry
@Component
struct FlexExample {
  build() {
    Flex({ 
      direction: FlexDirection.Row,
      justifyContent: FlexAlign.SpaceBetween,
      alignItems: ItemAlign.Center 
    }) {
      Text('左侧')
        .width('30%')
      
      Text('中间')
        .width('40%')
      
      Text('右侧')
        .width('30%')
    }
    .width('100%')
    .height(100)
    .backgroundColor('#F0F0F0')
  }
}
```

#### 4.2.2 Grid布局

```typescript
@Entry
@Component
struct GridExample {
  @State items: string[] = [
    '项目1', '项目2', '项目3', '项目4',
    '项目5', '项目6', '项目7', '项目8'
  ];

  build() {
    Grid() {
      ForEach(this.items, (item: string) => item, (item: string) => {
        GridItem() {
          Text(item)
            .fontSize(16)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .height(80)
        .backgroundColor('#2196F3')
        .borderRadius(8)
      }
    })
    }
    .columnsTemplate('1fr 1fr')
    .rowsTemplate('1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .width('100%')
    .height(300)
    .padding(16)
  }
}
```

### 4.3 导航组件

#### 4.3.1 路由导航

```typescript
// router页面配置
export class Router {
  static home: string = 'pages/HomePage';
  static profile: string = 'pages/ProfilePage';
  static settings: string = 'pages/SettingsPage';
}

@Entry
@Component
struct NavigationExample {
  build() {
    Column() {
      // 导航到首页
      Button('首页')
        .onClick(() => {
          router.pushUrl({ url: Router.home });
        })
      
      // 导航到个人中心
      Button('个人中心')
        .onClick(() => {
          router.pushUrl({ url: Router.profile });
        })
      
      // 导航到设置
      Button('设置')
        .onClick(() => {
          router.pushUrl({ url: Router.settings });
        })
      
      // 返回上一页
      Button('返回')
        .onClick(() => {
          router.back();
        })
    }
    .padding(20)
  }
}
```

#### 4.3.2 Tab导航

```typescript
@Entry
@Component
struct TabExample {
  @State currentTabIndex: number = 0;

  @Builder
  tabBuilder(index: number) {
    if (index === 0) {
      TabContent() {
        Text('首页内容')
          .fontSize(20)
      }
    } else if (index === 1) {
      TabContent() {
        Text('发现内容')
          .fontSize(20)
      }
    } else if (index === 2) {
      TabContent() {
        Text('我的内容')
          .fontSize(20)
      }
    }
  }

  build() {
    Tabs({ barPosition: BarPosition.Start }) {
      TabContent() {
        this.tabBuilder(0)
      }
      TabContent() {
        this.tabBuilder(1)
      }
      TabContent() {
        this.tabBuilder(2)
      }
    }
    .onChange((index: number) => {
      this.currentTabIndex = index;
    })
  }
}
```

## 五、数据持久化

### 5.1 首选项存储

```typescript
import preferences from '@ohos.data.preferences';

// 存储数据
async function saveData(key: string, value: string): Promise<void> {
  try {
    const preferences = await preferences.getPreferences(context, 'my_app');
    await preferences.put(key, value);
    await preferences.flush();
  } catch (err) {
    console.error('存储数据失败', err);
  }
}

// 读取数据
async function getData(key: string): Promise<string | undefined> {
  try {
    const preferences = await preferences.getPreferences(context, 'my_app');
    return await preferences.get(key, '');
  } catch (err) {
    console.error('读取数据失败', err);
    return undefined;
  }
}

// 使用示例
class SettingsViewModel {
  async saveTheme(theme: string): Promise<void> {
    await saveData('theme', theme);
  }

  async getTheme(): Promise<string> {
    return await getData('theme') || 'light';
  }
}
```

### 5.2 关系型数据库

```typescript
import relationalStore from '@ohos.data.relationalStore';

// 定义表结构
const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'UserStore',
  securityLevel: relationalStore.SecurityLevel.S1
};

interface User {
  id: number;
  name: string;
  email: string;
  age: number;
}

// 数据库操作
class UserRepository {
  private store: relationalStore.RdbStore | null = null;

  async init(): Promise<void> {
    this.store = await relationalStore.getRdbStore(context, STORE_CONFIG);
  }

  async insertUser(user: User): Promise<number> {
    const valueBucket = relationalStore.createValueBucket();
    valueBucket.put('name', user.name);
    valueBucket.put('email', user.email);
    valueBucket.put('age', user.age.toString());
    
    return await this.store.insert('user', valueBucket);
  }

  async queryUsers(): Promise<User[]> {
    const predicates = new relationalStore.RdbPredicates();
    const resultSet = await this.store.query('user', predicates);
    
    const users: User[] = [];
    while (resultSet.goToNextRow()) {
      const user: User = {
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        email: resultSet.getString(resultSet.getColumnIndex('email')),
        age: resultSet.getLong(resultSet.getColumnIndex('age'))
      };
      users.push(user);
    }
    
    return users;
  }
}
```

## 六、网络请求

### 6.1 HTTP请求

```typescript
import axios from '@ohos/axios';

// 创建axios实例
const http = axios.create({
  baseURL: 'https://api.example.com',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json'
  }
});

// GET请求
async function getUsers(): Promise<User[]> {
  try {
    const response = await http.get<User[]>('/users');
    return response.data;
  } catch (error) {
    console.error('获取用户列表失败', error);
    return [];
  }
}

// POST请求
async function createUser(user: User): Promise<User> {
  try {
    const response = await http.post<User>('/users', user);
    return response.data;
  } catch (error) {
    console.error('创建用户失败', error);
    throw error;
  }
}

// PUT请求
async function updateUser(id: number, user: User): Promise<User> {
  try {
    const response = await http.put<User>(`/users/${id}`, user);
    return response.data;
  } catch (error) {
    console.error('更新用户失败', error);
    throw error;
  }
}

// DELETE请求
async function deleteUser(id: number): Promise<boolean> {
  try {
    await http.delete(`/users/${id}`);
    return true;
  } catch (error) {
    console.error('删除用户失败', error);
    return false;
  }
}
```

### 6.2 数据解析

```typescript
// JSON解析
interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}

async function fetchUsers(): Promise<User[]> {
  const response = await http.get<ApiResponse<User[]>>('/users');
  
  if (response.data.code === 200) {
    return response.data.data;
  } else {
    throw new Error(response.data.message);
  }
}

// 使用示例
class UserViewModel {
  @State users: User[] = [];

  async loadUsers(): Promise<void> {
    try {
      this.users = await fetchUsers();
    } catch (error) {
      console.error('加载用户失败', error);
    }
  }
}
```

## 七、项目实战案例

### 7.1 项目一：适老居家生活辅助系统

#### 7.1.1 项目概述
开发一个面向老年人的鸿蒙应用，包含健康监测、紧急呼叫、家属关联等功能。

#### 7.1.2 核心功能实现

**紧急呼叫功能**
```typescript
@Entry
@Component
struct EmergencyCallPage {
  @State emergencyContact: string = "110";
  @State countdown: number = 0;
  private timer: number = -1;

  build() {
    Column() {
      // 紧急呼叫按钮
      Button() {
        Column() {
          Image($r('app.media.phone'))
            .width(60)
            .height(60)
          Text('紧急呼叫')
            .fontSize(20)
            .fontColor('#FFFFFF')
            .margin({ top: 8 })
        }
      }
      .type(ButtonType.Circle)
      .width(200)
      .height(200)
      .backgroundColor('#FF5252')
      .onClick(() => {
        this.startCountdown();
      })
      
      if (this.countdown > 0) {
        Text(`${this.countdown}秒后拨打`)
          .fontSize(24)
          .fontColor('#FF5252')
          .margin({ top: 32 })
      }
      
      // 联系人设置
      TextInput({ 
        placeholder: '紧急联系人电话', 
        text: this.emergencyContact 
      })
        .onChange((value: string) => {
          this.emergencyContact = value;
        })
        .margin({ top: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F5F5')
  }

  private startCountdown(): void {
    if (this.timer === -1) {
      this.countdown = 3;
      this.timer = setInterval(() => {
        this.countdown--;
        if (this.countdown <= 0) {
          this.makeEmergencyCall();
          this.clearInterval();
        }
      }, 1000);
    }
  }

  private makeEmergencyCall(): void {
    call.makeCall(this.emergencyContact, false);
  }

  private clearInterval(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
      this.countdown = 0;
    }
  }
}
```

**健康监测数据展示**
```typescript
interface HealthData {
  heartRate: number;
  bloodPressure: string;
  bloodSugar: number;
  timestamp: number;
}

@Entry
@Component
struct HealthMonitoringPage {
  @State healthData: HealthData = {
    heartRate: 75,
    bloodPressure: "120/80",
    bloodSugar: 5.6,
    timestamp: Date.now()
  };

  build() {
    Scroll() {
      Column({ space: 16 }) {
        // 心率卡片
        HealthCard(
          title: '心率',
          value: `${this.healthData.heartRate} bpm`,
          icon: $r('app.media.heart'),
          color: '#FF5252'
        )
        
        // 血压卡片
        HealthCard(
          title: '血压',
          value: `${this.healthData.bloodPressure} mmHg`,
          icon: $r('app.media.blood_pressure'),
          color: '#2196F3'
        )
        
        // 血糖卡片
        HealthCard(
          title: '血糖',
          value: `${this.healthData.bloodSugar} mmol/L`,
          icon: $r('app.media.blood_sugar'),
          color: '#4CAF50'
        )
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}

@Component
struct HealthCard {
  @Prop title: string = "";
  @Prop value: string = "";
  @Prop icon: Resource = $r('');
  @Prop color: string = '#000000';

  build() {
    Column() {
      Row() {
        Image(this.icon)
          .width(48)
          .height(48)
          .margin({ right: 12 })
        
        Column() {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#666666')
          
          Text(this.value)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.color)
            .margin({ top: 8 })
        }
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: '#1A000000',
      offsetX: 0,
      offsetY: 2
    })
  }
}
```

#### 7.1.3 AI功能集成

**AI语音助手**
```typescript
import speechRecognizer from '@ohos.ai.speechRecognition';

@Entry
@Component
struct VoiceAssistantPage {
  @State recognizedText: string = "";
  @State isListening: boolean = false;
  @State aiResponse: string = "";

  build() {
    Column() {
      // 语音识别结果
      Text(this.recognizedText || "点击按钮开始语音识别")
        .fontSize(16)
        .margin(16)
      
      // AI响应
      if (this.aiResponse) {
        Text(this.aiResponse)
          .fontSize(18)
          .fontColor('#2196F3')
          .margin(16)
      }
      
      // 语音识别按钮
      Button(this.isListening ? '停止识别' : '开始识别')
        .onClick(() => {
          if (this.isListening) {
            this.stopRecognition();
          } else {
            this.startRecognition();
          }
        })
        .margin(16)
    }
    .padding(20)
  }

  private async startRecognition(): Promise<void> {
    try {
      this.isListening = true;
      const result = await speechRecognizer.start();
      this.recognizedText = result;
      this.aiResponse = await this.processWithAI(result);
    } catch (error) {
      console.error('语音识别失败', error);
      this.isListening = false;
    }
  }

  private stopRecognition(): void {
    speechRecognizer.stop();
    this.isListening = false;
  }

  private async processWithAI(text: string): Promise<string> {
    // 调用AI服务处理语音指令
    const response = await AIService.processCommand(text);
    return response || "抱歉，我没有理解您的指令";
  }
}
```

### 7.2 项目二：云端智能畜牧养殖管理系统

#### 7.2.1 项目概述
开发一个智能畜牧养殖管理鸿蒙应用，包含动物健康监测、疾病诊断、生长预测等功能。

#### 7.2.2 核心功能实现

**动物列表管理**
```typescript
@Entry
@Component
struct LivestockListPage {
  @State livestockList: Livestock[] = [];
  @State searchText: string = "";

  aboutToAppear() {
    this.loadLivestock();
  }

  build() {
    Column() {
      // 搜索框
      TextInput({ 
        placeholder: '搜索牲畜', 
        text: this.searchText 
      })
        .onChange((value: string) => {
          this.searchText = value;
        })
        .margin(16)
      
      // 牲畜列表
      List({ space: 12 }) {
        ForEach(
          this.filteredLivestock,
          (item: Livestock) => item.id.toString(),
          (item: Livestock) => {
            ListItem() {
              LivestockItem({ livestock: item })
            }
          }
        )
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  private get filteredLivestock(): Livestock[] {
    if (!this.searchText) {
      return this.livestockList;
    }
    return this.livestockList.filter(item => 
      item.name.includes(this.searchText)
    );
  }

  private async loadLivestock(): Promise<void> {
    try {
      this.livestockList = await LivestockRepository.getAll();
    } catch (error) {
      console.error('加载牲畜列表失败', error);
    }
  }
}

@Component
struct LivestockItem {
  @Prop livestock: Livestock;

  build() {
    Row() {
      // 牲畜图片
      Image(this.livestock.imageUrl)
        .width(80)
        .height(80)
        .borderRadius(40)
        .margin({ right: 12 })
      
      Column() {
        Text(this.livestock.name)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        
        Row() {
          Text(`体重：${this.livestock.weight}kg`)
            .fontSize(14)
            .fontColor('#666666')
          
          Text(`年龄：${this.livestock.age}个月`)
            .fontSize(14)
            .fontColor('#666666')
            .margin({ left: 16 })
        }
        
        // 健康状态标签
        Text(this.livestock.healthStatus)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.getHealthColor())
          .borderRadius(12)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .shadow({
      radius: 4,
      color: '#1A000000',
      offsetX: 0,
      offsetY: 2
    })
  }

  private getHealthColor(): string {
    switch (this.livestock.healthStatus) {
      case '健康':
        return '#4CAF50';
      case '生病':
        return '#FF5252';
      default:
        return '#FFA000';
    }
  }
}
```

#### 7.2.3 AI功能集成

**AI疾病诊断**
```typescript
@Entry
@Component
struct DiseaseDiagnosisPage {
  @State selectedImage: string = "";
  @State diagnosisResult: DiagnosisResult | null = null;
  @State isAnalyzing: boolean = false;

  build() {
    Column() {
      // 图片选择
      Button('选择图片')
        .onClick(() => {
          this.selectImage();
        })
        .margin(16)
      
      // 诊断结果
      if (this.diagnosisResult) {
        DiagnosisResultCard({ result: this.diagnosisResult })
      }
      
      // 分析中状态
      if (this.isAnalyzing) {
        LoadingDialog()
      }
    }
    .padding(20)
  }

  private async selectImage(): Promise<void> {
    // 选择图片逻辑
    this.selectedImage = "selected_image_path";
    await this.analyzeImage();
  }

  private async analyzeImage(): Promise<void> {
    try {
      this.isAnalyzing = true;
      const result = await AIService.diagnoseDisease(this.selectedImage);
      this.diagnosisResult = result;
    } catch (error) {
      console.error('疾病诊断失败', error);
    } finally {
      this.isAnalyzing = false;
    }
  }
}

@Component
struct DiagnosisResultCard {
  @Prop result: DiagnosisResult;

  build() {
    Column() {
      Text('诊断结果')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })
      
      Row() {
        Text('疾病名称：')
          .fontSize(16)
        Text(this.result.diseaseName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF5252')
      }
      
      Row() {
        Text('置信度：')
          .fontSize(16)
        Text(`${(this.result.confidence * 100).toFixed(1)}%`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2196F3')
      }
      
      Text(`治疗方案：${this.result.treatment}`)
        .fontSize(16)
        .margin({ top: 8 })
      
      Text(`严重程度：${this.result.severity}`)
        .fontSize(16)
        .fontColor(this.getSeverityColor())
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  private getSeverityColor(): string {
    switch (this.result.severity) {
      case '轻微':
        return '#4CAF50';
      case '中等':
        return '#FFA000';
      case '严重':
        return '#FF5252';
      default:
        return '#FFA000';
    }
  }
}
```

## 八、测试与调试

### 8.1 单元测试

```typescript
import { describe, it, expect } from '@ohos/hypium/index';

describe('UserRepository', () => {
  it('should insert user successfully', async () => {
    const user: User = {
      id: 1,
      name: '张三',
      email: 'zhangsan@example.com',
      age: 25
    };
    
    const id = await UserRepository.insertUser(user);
    expect(id).toBeGreaterThan(0);
  });

  it('should query users successfully', async () => {
    const users = await UserRepository.queryUsers();
    expect(users.length).toBeGreaterThan(0);
    expect(users[0].name).toBe('张三');
  });
});
```

### 8.2 UI测试

```typescript
import { Driver, ON } from '@ohos/hypium/index';

describe('HomePage UI Test', () => {
  let driver: Driver;

  beforeAll(async () => {
    driver = Driver.create();
    await driver.delayMs(1000);
  });

  it('should display greeting text', async () => {
    const text = await driver.findComponent(ON.id('greeting_text'));
    expect(await text.getText()).toContain('Hello');
  });

  it('should increment count on button click', async () => {
    const button = await driver.findComponent(ON.id('increment_button'));
    await button.click();
    
    const countText = await driver.findComponent(ON.id('count_text'));
    const count = await countText.getText();
    expect(count).toContain('1');
  });
});
```

## 九、性能优化

### 9.1 渲染优化

```typescript
// 使用LazyForEach替代ForEach进行列表渲染
@Entry
@Component
struct OptimizedListPage {
  @State items: string[] = Array.from({ length: 1000 }, (_, i) => `项目${i}`);

  build() {
    List() {
      LazyForEach(this.items, (item: string) => item, (item: string) => {
        ListItem() {
          Text(item)
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
```

### 9.2 内存优化

```typescript
// 使用@Reusable组件复用
@Component
struct ReusableItem {
  @Prop item: string = "";

  build() {
    Text(this.item)
  }
}

@Entry
@Component
struct ReusableListPage {
  @State items: string[] = ['项目1', '项目2', '项目3'];

  build() {
    List() {
      ForEach(this.items, (item: string) => item, (item: string) => {
        ListItem() {
          ReusableItem({ item: item })
        }
      })
    }
  }
}
```

## 十、常见问题与解决方案

### 10.1 状态更新问题
**问题**：直接修改状态变量不会触发UI更新

**解决方案**：
```typescript
@Entry
@Component
struct CorrectStateUpdate {
  @State count: number = 0;

  build() {
    Column() {
      Text(`计数：${this.count}`)
      Button('增加')
        .onClick(() => {
          // 正确：使用this.count++
          this.count++;
        })
    }
  }
}
```

### 10.2 组件通信问题
**问题**：父子组件之间数据传递不清晰

**解决方案**：
```typescript
// 父组件
@Entry
@Component
struct ParentComponent {
  @State parentData: string = "父组件数据";

  build() {
    Column() {
      ChildComponent({ 
        childData: this.parentData,
        onDataChange: (value: string) => {
          this.parentData = value;
        }
      })
    }
  }
}

// 子组件
@Component
struct ChildComponent {
  @Prop childData: string = "";
  onDataChange?: (value: string) => void;

  build() {
    Column() {
      Text(this.childData)
      Button('修改数据')
        .onClick(() => {
          const newValue = "子组件修改的数据";
          if (this.onDataChange) {
            this.onDataChange(newValue);
          }
        })
    }
  }
}
```

## 十一、学习资源

### 11.1 官方文档
- HarmonyOS开发者文档：https://developer.harmonyos.com/cn/
- ArkTS语言指南：https://developer.harmonyos.com/cn/docs/documentation/doc-guides/arkts-get-started
- ArkUI组件参考：https://developer.harmonyos.com/cn/docs/documentation/doc-references/arkui-ts

### 11.2 推荐书籍
- 《HarmonyOS应用开发实战》
- 《ArkTS从入门到精通》
- 《鸿蒙应用设计与开发》

### 11.3 在线课程
- HarmonyOS开发者培训课程
- 鸿蒙应用开发官方教程
- ArkUI组件开发实战

## 十二、实验项目要求

### 12.1 基础要求
1. 使用ArkTS语言开发
2. 采用ArkUI声明式UI框架
3. 实现多端适配（手机、平板、折叠屏）
4. 集成网络请求和数据持久化
5. 实现组件化开发
6. 添加单元测试和UI测试

### 12.2 进阶要求
1. 实现分布式能力（多设备协同）
2. 集成AI功能（语音识别、图像识别等）
3. 优化应用性能和渲染效率
4. 实现深色模式支持
5. 添加国际化支持
6. 实现无障碍功能

### 12.3 提交要求
1. 完整的项目源代码
2. 详细的README文档
3. HAP安装包（Debug和Release版本）
4. 测试报告
5. 技术文档和架构设计图