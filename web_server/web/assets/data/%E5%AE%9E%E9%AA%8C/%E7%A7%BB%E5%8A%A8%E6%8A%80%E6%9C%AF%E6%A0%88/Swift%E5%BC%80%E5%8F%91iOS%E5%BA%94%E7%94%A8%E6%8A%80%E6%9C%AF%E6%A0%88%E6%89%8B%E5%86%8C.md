# Swift开发iOS应用技术栈手册

## 一、技术栈概述

### 1.1 核心技术
- **编程语言**：Swift
- **开发框架**：UIKit / SwiftUI
- **构建工具**：Xcode
- **包管理**：Swift Package Manager (SPM)
- **版本要求**：Swift 5.9+, iOS 17+

### 1.2 依赖管理
- **包管理**：Swift Package Manager, CocoaPods
- **依赖仓库**：Swift Package Index, CocoaPods Spec Repository
- **版本控制**：Git

### 1.3 测试框架
- **单元测试**：XCTest
- **UI测试**：XCUITest
- **集成测试**：XCTest Framework

## 二、环境搭建

### 2.1 开发环境配置

```swift
// Package.swift
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MyApp",
            targets: ["MyApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0"),
        .package(url: "https://github.com/SDWebImage/SDWebImage.git", from: "5.18.0")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: ["Alamofire", "SDWebImage"]
        ),
        .testTarget(
            name: "MyAppTests",
            dependencies: ["MyApp"]
        )
    ]
)
```

### 2.2 依赖配置

```swift
// 使用Swift Package Manager
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, World!")
    }
}

// 使用CocoaPods
// Podfile
platform :ios, '17.0'

target 'MyApp' do
  use_frameworks!
  
  pod 'Alamofire', '~> 5.8'
  pod 'SDWebImage', '~> 5.18'
  pod 'Kingfisher', '~> 7.10'
  
  target 'MyAppTests' do
    inherit! :search_paths
  end
end
```

## 三、基础语法与特性

### 3.1 Swift基础语法

#### 3.1.1 变量声明

```swift
// let：不可变变量
let name = "张三"
let age = 25

// var：可变变量
var count = 0
count += 1

// 类型标注
var message: String = "Hello Swift"
var number: Int = 100

// 数组
var numbers: [Int] = [1, 2, 3, 4, 5]
var fruits = ["苹果", "香蕉", "橙子"]

// 字典
var person: [String: Any] = [
    "name": "李四",
    "age": 30,
    "email": "lisi@example.com"
]
```

#### 3.1.2 函数定义

```swift
// 基本函数
func greet(name: String) -> String {
    return "你好，\(name)"
}

// 默认参数
func createUser(name: String, age: Int = 18) {
    print("创建用户：\(name)，年龄：\(age)")
}

// 可变参数
func sumAll(_ numbers: Int...) -> Int {
    return numbers.reduce(0, +)
}

// 闭包
let add = { (a: Int, b: Int) -> Int in
    return a + b
}
let result = add(3, 5)

// 尾随闭包
func performOperation(_ operation: (Int, Int) -> Int) {
    let result = operation(10, 20)
    print("结果：\(result)")
}

performOperation { $0 + $1 } // 使用尾随闭包
```

#### 3.1.3 结构体与类

```swift
// 结构体（值类型）
struct User {
    let id: Int
    var name: String
    var email: String
    var age: Int
    
    // 计算属性
    var isAdult: Bool {
        return age >= 18
    }
    
    // 方法
    func introduce() -> String {
        return "我叫\(name)，今年\(age)岁"
    }
    
    // 可变方法
    mutating func celebrateBirthday() {
        age += 1
    }
}

// 使用结构体
var user = User(id: 1, name: "王五", email: "wangwu@example.com", age: 25)
print(user.introduce())
user.celebrateBirthday()

// 类（引用类型）
class Person {
    var name: String
    var age: Int
    
    init(name: String, age: Int) {
        self.name = name
        self.age = age
    }
    
    deinit {
        print("\(name) 被销毁")
    }
}

// 使用类
let person = Person(name: "赵六", age: 28)
```

#### 3.1.4 可选类型

```swift
// 可选类型
var name: String? = nil
var age: Int? = 25

// 可选绑定
if let unwrappedName = name {
    print("名字：\(unwrappedName)")
} else {
    print("名字为空")
}

// 空合运算符
let displayName = name ?? "匿名用户"

// 强制解包（不推荐）
let userName = name! // 如果name为nil，会崩溃

// 可选链
let userLength = name?.count

// guard语句
func processUser(name: String?, age: Int?) {
    guard let userName = name, let userAge = age else {
        print("用户信息不完整")
        return
    }
    print("处理用户：\(userName)，年龄：\(userAge)")
}
```

### 3.2 Swift高级特性

#### 3.2.1 协议与扩展

```swift
// 协议定义
protocol Identifiable {
    var id: Int { get }
}

protocol Named {
    var name: String { get set }
}

// 协议遵循
struct Product: Identifiable, Named {
    let id: Int
    var name: String
    var price: Double
}

// 协议扩展
extension Identifiable {
    func describe() -> String {
        return "ID: \(id)"
    }
}

// 扩展String
extension String {
    func isValidEmail() -> Bool {
        return self.contains("@") && self.contains(".")
    }
}

// 使用扩展
let email = "user@example.com"
if email.isValidEmail() {
    print("邮箱格式正确")
}
```

#### 3.2.2 泛型

```swift
// 泛型函数
func swapValues<T>(_ a: inout T, _ b: inout T) {
    let temp = a
    a = b
    b = temp
}

var x = 10
var y = 20
swapValues(&x, &y)

// 泛型类型
struct Stack<Element> {
    private var items: [Element] = []
    
    mutating func push(_ item: Element) {
        items.append(item)
    }
    
    mutating func pop() -> Element? {
        return items.popLast()
    }
}

// 使用泛型
var intStack = Stack<Int>()
intStack.push(1)
intStack.push(2)
```

#### 3.2.3 错误处理

```swift
// 定义错误类型
enum NetworkError: Error {
    case invalidURL
    case requestFailed
    case invalidResponse
}

// 抛出错误的函数
func fetchData(from urlString: String) throws -> String {
    guard let url = URL(string: urlString) else {
        throw NetworkError.invalidURL
    }
    
    // 模拟网络请求
    return "数据"
}

// 处理错误
do {
    let data = try fetchData(from: "https://api.example.com/data")
    print(data)
} catch NetworkError.invalidURL {
    print("URL无效")
} catch NetworkError.requestFailed {
    print("请求失败")
} catch {
    print("未知错误：\(error)")
}

// try? 和 try!
let data1 = try? fetchData(from: "invalid_url") // 返回可选类型
let data2 = try! fetchData(from: "https://api.example.com/data") // 强制解包
```

## 四、SwiftUI开发

### 4.1 SwiftUI基础

#### 4.1.1 视图创建

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Hello, SwiftUI!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("欢迎使用SwiftUI")
                .font(.title2)
                .foregroundColor(.gray)
            
            Image(systemName: "star.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
        }
        .padding()
    }
}

// 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

#### 4.1.2 状态管理

```swift
import SwiftUI

struct CounterView: View {
    @State private var count = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("计数：\(count)")
                .font(.title)
            
            HStack(spacing: 20) {
                Button(action: {
                    count -= 1
                }) {
                    Text("-")
                        .font(.title)
                        .frame(width: 60, height: 60)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                }
                
                Button(action: {
                    count += 1
                }) {
                    Text("+")
                        .font(.title)
                        .frame(width: 60, height: 60)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                }
            }
        }
        .padding()
    }
}
```

#### 4.1.3 列表显示

```swift
import SwiftUI

struct User: Identifiable {
    let id = UUID()
    let name: String
    let email: String
    let avatar: String
}

struct UserListView: View {
    let users = [
        User(name: "张三", email: "zhangsan@example.com", avatar: "person.circle.fill"),
        User(name: "李四", email: "lisi@example.com", avatar: "person.circle.fill"),
        User(name: "王五", email: "wangwu@example.com", avatar: "person.circle.fill")
    ]
    
    var body: some View {
        List(users) { user in
            UserRow(user: user)
        }
        .listStyle(.plain)
    }
}

struct UserRow: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: user.avatar)
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.headline)
                
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### 4.2 导航组件

#### 4.2.1 NavigationStack

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("首页", destination: HomeView())
                NavigationLink("个人中心", destination: ProfileView())
                NavigationLink("设置", destination: SettingsView())
            }
            .navigationTitle("主菜单")
        }
    }
}

struct HomeView: View {
    var body: some View {
        VStack {
            Text("首页内容")
                .font(.title)
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProfileView: View {
    var body: some View {
        VStack {
            Text("个人中心")
                .font(.title)
        }
        .navigationTitle("个人中心")
    }
}

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("设置")
                .font(.title)
        }
        .navigationTitle("设置")
    }
}
```

#### 4.2.2 TabView

```swift
import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
            
            DiscoverView()
                .tabItem {
                    Label("发现", systemImage: "compass.fill")
                }
            
            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
        }
    }
}

struct HomeView: View {
    var body: some View {
        VStack {
            Text("首页")
                .font(.title)
        }
    }
}

struct DiscoverView: View {
    var body: some View {
        VStack {
            Text("发现")
                .font(.title)
        }
    }
}

struct ProfileView: View {
    var body: some View {
        VStack {
            Text("我的")
                .font(.title)
        }
    }
}
```

## 五、MVVM架构实战

### 5.1 ViewModel实现

```swift
import Foundation
import Combine

class UserViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadUsers()
    }
    
    func loadUsers() {
        isLoading = true
        errorMessage = nil
        
        UserRepository.shared.getUsers()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        self.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { users in
                    self.users = users
                }
            )
            .store(in: &cancellables)
    }
    
    func addUser(_ user: User) {
        UserRepository.shared.addUser(user)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in
                    self.loadUsers()
                }
            )
            .store(in: &cancellables)
    }
}
```

### 5.2 Repository模式

```swift
import Foundation
import Combine

struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let age: Int
}

class UserRepository {
    static let shared = UserRepository()
    
    private let baseURL = "https://api.example.com"
    
    private init() {}
    
    func getUsers() -> AnyPublisher<[User], Error> {
        guard let url = URL(string: "\(baseURL)/users") else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: [User].self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func addUser(_ user: User) -> AnyPublisher<User, Error> {
        guard let url = URL(string: "\(baseURL)/users") else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(user)
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: User.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func deleteUser(id: Int) -> AnyPublisher<Bool, Error> {
        guard let url = URL(string: "\(baseURL)/users/\(id)") else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map { _ in true }
            .eraseToAnyPublisher()
    }
}
```

### 5.3 网络请求

```swift
import Foundation
import Alamofire

enum NetworkError: Error {
    case invalidURL
    case requestFailed
    case invalidResponse
    case decodingFailed
}

class NetworkManager {
    static let shared = NetworkManager()
    
    private let baseURL = "https://api.example.com"
    
    private init() {}
    
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil
    ) -> AnyPublisher<T, Error> {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        return Future<T, Error> { promise in
            AF.request(
                url,
                method: method,
                parameters: parameters,
                encoding: JSONEncoding.default
            )
            .validate()
            .responseDecodable(of: T.self) { response in
                switch response.result {
                case .success(let data):
                    promise(.success(data))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

// 使用示例
NetworkManager.shared.request(endpoint: "/users")
    .sink(
        receiveCompletion: { completion in
            if case .failure(let error) = completion {
                print("请求失败：\(error)")
            }
        },
        receiveValue: { (users: [User]) in
            print("用户列表：\(users)")
        }
    )
```

## 六、项目实战案例

### 6.1 项目一：适老居家生活辅助系统

#### 6.1.1 项目概述
开发一个面向老年人的iOS应用，包含健康监测、紧急呼叫、家属关联等功能。

#### 6.1.2 核心功能实现

**紧急呼叫功能**
```swift
import SwiftUI
import UIKit

struct EmergencyCallView: View {
    @State private var emergencyContact = "110"
    @State private var countdown = 0
    @State private var isCountingDown = false
    private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 30) {
            // 紧急呼叫按钮
            Button(action: {
                startCountdown()
            }) {
                VStack(spacing: 10) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 60))
                    Text("紧急呼叫")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .frame(width: 200, height: 200)
                .background(Color.red)
                .foregroundColor(.white)
                .clipShape(Circle())
                .shadow(radius: 10)
            }
            
            // 倒计时显示
            if isCountingDown {
                Text("\(countdown)秒后拨打")
                    .font(.title)
                    .foregroundColor(.red)
            }
            
            // 联系人设置
            TextField("紧急联系人电话", text: $emergencyContact)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .keyboardType(.phonePad)
        }
        .padding()
    }
    
    private func startCountdown() {
        guard !isCountingDown else { return }
        
        isCountingDown = true
        countdown = 3
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            countdown -= 1
            
            if countdown <= 0 {
                makeEmergencyCall()
                stopCountdown()
            }
        }
    }
    
    private func stopCountdown() {
        isCountingDown = false
        timer?.invalidate()
        timer = nil
        countdown = 0
    }
    
    private func makeEmergencyCall() {
        if let url = URL(string: "tel:\(emergencyContact)") {
            UIApplication.shared.open(url)
        }
    }
}
```

**健康监测数据展示**
```swift
import SwiftUI

struct HealthData {
    let heartRate: Int
    let bloodPressure: String
    let bloodSugar: Double
    let timestamp: Date
}

struct HealthMonitoringView: View {
    @State private var healthData = HealthData(
        heartRate: 75,
        bloodPressure: "120/80",
        bloodSugar: 5.6,
        timestamp: Date()
    )
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 心率卡片
                HealthCard(
                    title: "心率",
                    value: "\(healthData.heartRate) bpm",
                    icon: "heart.fill",
                    color: .red
                )
                
                // 血压卡片
                HealthCard(
                    title: "血压",
                    value: "\(healthData.bloodPressure) mmHg",
                    icon: "heart.text.square.fill",
                    color: .blue
                )
                
                // 血糖卡片
                HealthCard(
                    title: "血糖",
                    value: "\(healthData.bloodSugar) mmol/L",
                    icon: "drop.fill",
                    color: .green
                )
            }
            .padding()
        }
    }
}

struct HealthCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(color)
                .frame(width: 60)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 4)
    }
}
```

#### 6.1.3 AI功能集成

**AI语音助手**
```swift
import SwiftUI
import Speech

class VoiceAssistantViewModel: ObservableObject {
    @Published var recognizedText = ""
    @Published var aiResponse = ""
    @Published var isListening = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            return
        }
        
        isListening = true
        recognizedText = ""
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }
            
            if isFinal || error != nil {
                self.stopListening()
                self.processWithAI()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
    
    private func processWithAI() {
        // 调用AI服务处理语音指令
        AIService.shared.processCommand(recognizedText) { response in
            DispatchQueue.main.async {
                self.aiResponse = response ?? "抱歉，我没有理解您的指令"
            }
        }
    }
}

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAssistantViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // 语音识别结果
            Text(viewModel.recognizedText.isEmpty ? "点击按钮开始语音识别" : viewModel.recognizedText)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()
            
            // AI响应
            if !viewModel.aiResponse.isEmpty {
                Text(viewModel.aiResponse)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            // 语音识别按钮
            Button(action: {
                if viewModel.isListening {
                    viewModel.stopListening()
                } else {
                    viewModel.startListening()
                }
            }) {
                Text(viewModel.isListening ? "停止识别" : "开始识别")
                    .font(.title2)
                    .padding()
                    .background(viewModel.isListening ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}
```

### 6.2 项目二：云端智能畜牧养殖管理系统

#### 6.2.1 项目概述
开发一个智能畜牧养殖管理iOS应用，包含动物健康监测、疾病诊断、生长预测等功能。

#### 6.2.2 核心功能实现

**动物列表管理**
```swift
import SwiftUI

struct Livestock: Identifiable {
    let id = UUID()
    let name: String
    let imageUrl: String
    let weight: Double
    let age: Int
    let healthStatus: String
}

struct LivestockListView: View {
    @StateObject private var viewModel = LivestockViewModel()
    
    var body: some View {
        VStack {
            // 搜索框
            SearchBar(text: $viewModel.searchText)
                .padding()
            
            // 动物列表
            List {
                ForEach(viewModel.filteredLivestock) { livestock in
                    LivestockRow(livestock: livestock)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct LivestockRow: View {
    let livestock: Livestock
    
    var body: some View {
        HStack(spacing: 12) {
            // 动物图片
            AsyncImage(url: URL(string: livestock.imageUrl)) { image in
                image.resizable()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(livestock.name)
                    .font(.headline)
                
                HStack {
                    Text("体重：\(livestock.weight)kg")
                    Text("年龄：\(livestock.age)个月")
                }
                .font(.subheadline)
                .foregroundColor(.gray)
                
                // 健康状态标签
                Text(livestock.healthStatus)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(healthColor.opacity(0.2))
                    .foregroundColor(healthColor)
                    .cornerRadius(12)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var healthColor: Color {
        switch livestock.healthStatus {
        case "健康":
            return .green
        case "生病":
            return .red
        default:
            return .orange
        }
    }
}

class LivestockViewModel: ObservableObject {
    @Published var livestockList: [Livestock] = []
    @Published var searchText = ""
    
    var filteredLivestock: [Livestock] {
        if searchText.isEmpty {
            return livestockList
        }
        return livestockList.filter { $0.name.contains(searchText) }
    }
    
    init() {
        loadLivestock()
    }
    
    func loadLivestock() {
        // 加载牲畜列表
        livestockList = [
            Livestock(name: "奶牛1号", imageUrl: "https://example.com/cow1.jpg", weight: 450, age: 24, healthStatus: "健康"),
            Livestock(name: "奶牛2号", imageUrl: "https://example.com/cow2.jpg", weight: 480, age: 30, healthStatus: "生病"),
            Livestock(name: "奶牛3号", imageUrl: "https://example.com/cow3.jpg", weight: 520, age: 36, healthStatus: "健康")
        ]
    }
}
```

#### 6.2.3 AI功能集成

**AI疾病诊断**
```swift
import SwiftUI
import Vision

class DiseaseDiagnosisViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var diagnosisResult: DiagnosisResult?
    @Published var isAnalyzing = false
    
    func diagnoseDisease(image: UIImage) {
        isAnalyzing = true
        
        // 使用Vision框架进行图像识别
        guard let cgImage = image.cgImage else {
            isAnalyzing = false
            return
        }
        
        let request = VNRecognizeAnimalsRequest { request, error in
            if let error = error {
                print("识别失败：\(error)")
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                }
                return
            }
            
            // 处理识别结果
            DispatchQueue.main.async {
                self.processDiagnosisResults(observations)
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
    
    private func processDiagnosisResults(_ observations: [VNRecognizedObjectObservation]) {
        // 模拟AI诊断结果
        let result = DiagnosisResult(
            diseaseName: "牛瘟",
            confidence: 0.85,
            treatment: "立即隔离，使用抗生素治疗，补充营养",
            severity: "严重"
        )
        
        diagnosisResult = result
        isAnalyzing = false
    }
}

struct DiagnosisResult {
    let diseaseName: String
    let confidence: Double
    let treatment: String
    let severity: String
}

struct DiseaseDiagnosisView: View {
    @StateObject private var viewModel = DiseaseDiagnosisViewModel()
    @State private var showingImagePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            // 图片选择
            Button("选择图片") {
                showingImagePicker = true
            }
            .buttonStyle(.borderedProminent)
            
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(12)
            }
            
            // 诊断结果
            if let result = viewModel.diagnosisResult {
                DiagnosisResultCard(result: result)
            }
            
            // 分析中状态
            if viewModel.isAnalyzing {
                ProgressView("正在分析...")
            }
        }
        .padding()
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $viewModel.selectedImage)
        }
    }
}

struct DiagnosisResultCard: View {
    let result: DiagnosisResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("诊断结果")
                .font(.title)
                .fontWeight(.bold)
            
            HStack {
                Text("疾病名称：")
                Text(result.diseaseName)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
            
            HStack {
                Text("置信度：")
                Text("\(String(format: "%.1f", result.confidence * 100))%")
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading) {
                Text("治疗方案：")
                Text(result.treatment)
                    .font(.subheadline)
            }
            
            HStack {
                Text("严重程度：")
                Text(result.severity)
                    .fontWeight(.bold)
                    .foregroundColor(severityColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 4)
    }
    
    private var severityColor: Color {
        switch result.severity {
        case "轻微":
            return .green
        case "中等":
            return .orange
        case "严重":
            return .red
        default:
            return .orange
        }
    }
}
```

## 七、测试与调试

### 7.1 单元测试

```swift
import XCTest
@testable import MyApp

class UserViewModelTests: XCTestCase {
    var viewModel: UserViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = UserViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func testLoadUsers() {
        // Given
        let expectation = self.expectation(description: "加载用户列表")
        
        // When
        viewModel.loadUsers()
        
        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            XCTAssertFalse(self.viewModel.users.isEmpty)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testAddUser() {
        // Given
        let newUser = User(id: 4, name: "测试用户", email: "test@example.com", age: 25)
        
        // When
        viewModel.addUser(newUser)
        
        // Then
        XCTAssertTrue(viewModel.users.contains { $0.id == newUser.id })
    }
}
```

### 7.2 UI测试

```swift
import XCTest

class ContentViewUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testEmergencyCallButton() {
        // Given
        let emergencyButton = app.buttons["紧急呼叫"]
        
        // When
        XCTAssertTrue(emergencyButton.exists)
        emergencyButton.tap()
        
        // Then
        XCTAssertTrue(app.staticTexts["3秒后拨打"].exists)
    }
    
    func testCounterIncrement() {
        // Given
        let incrementButton = app.buttons["+"]
        let countText = app.staticTexts["计数："]
        
        // When
        incrementButton.tap()
        
        // Then
        XCTAssertTrue(countText.label.contains("1"))
    }
}
```

## 八、性能优化

### 8.1 内存优化

```swift
// 使用weak避免循环引用
class NetworkManager {
    static let shared = NetworkManager()
    
    func fetchData(completion: @escaping (Result<Data, Error>) -> Void) {
        // 使用weak self避免循环引用
        URLSession.shared.dataTask(with: URL(string: "https://api.example.com/data")!) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let data = data {
                completion(.success(data))
            }
        }.resume()
    }
}
```

### 8.2 启动优化

```swift
// 延迟加载非关键资源
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 立即加载关键资源
        setupCoreServices()
        
        // 延迟加载非关键资源
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.setupNonCriticalServices()
        }
        
        return true
    }
    
    private func setupCoreServices() {
        // 初始化核心服务
    }
    
    private func setupNonCriticalServices() {
        // 初始化非关键服务
    }
}
```

## 九、发布与部署

### 9.1 App Store配置

```swift
// Info.plist配置
<key>CFBundleDisplayName</key>
<string>我的应用</string>
<key>CFBundleIdentifier</key>
<string>com.example.myapp</string>
<key>CFBundleVersion</key>
<string>1.0.0</string>
<key>NSCameraUsageDescription</key>
<string>需要访问相机以拍摄照片</string>
<key>NSMicrophoneUsageDescription</key>
<string>需要访问麦克风以录制语音</string>
```

### 9.2 证书配置

```swift
// 在Xcode中配置签名
// 1. 选择项目 -> Signing & Capabilities
// 2. 选择开发团队
// 3. 自动管理签名
// 4. 添加必要的Capabilities（如推送通知、地图等）
```

## 十、常见问题与解决方案

### 10.1 内存泄漏
**问题**：闭包导致循环引用

**解决方案**：
```swift
// 使用[weak self]避免循环引用
viewModel.$users
    .sink { [weak self] users in
        self?.updateUI(with: users)
    }
    .store(in: &cancellables)
```

### 10.2 线程问题
**问题**：在后台线程更新UI

**解决方案**：
```swift
DispatchQueue.global(qos: .background).async {
    // 后台线程执行耗时操作
    let data = self.fetchData()
    
    DispatchQueue.main.async {
        // 主线程更新UI
        self.updateUI(with: data)
    }
}
```

## 十一、学习资源

### 11.1 官方文档
- Swift官方文档：https://swift.org/documentation/
- SwiftUI官方文档：https://developer.apple.com/documentation/swiftui
- iOS开发者指南：https://developer.apple.com/documentation/

### 11.2 推荐书籍
- 《Swift编程语言》
- 《SwiftUI实战》
- 《iOS开发艺术探索》

### 11.3 在线课程
- Apple官方Swift教程
- Stanford CS193p课程
- Ray Wenderlich教程

## 十二、实验项目要求

### 12.1 基础要求
1. 使用Swift语言开发
2. 采用SwiftUI构建UI
3. 实现MVVM架构
4. 集成Combine框架进行响应式编程
5. 实现网络请求和数据持久化
6. 添加单元测试和UI测试

### 12.2 进阶要求
1. 实现Core Data数据持久化
2. 集成AI功能（语音识别、图像识别等）
3. 优化应用性能和启动速度
4. 实现深色模式支持
5. 添加国际化支持
6. 实现无障碍功能

### 12.3 提交要求
1. 完整的项目源代码
2. 详细的README文档
3. IPA安装包（Debug和Release版本）
4. 测试报告
5. 技术文档和架构设计图