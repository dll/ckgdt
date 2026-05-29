# MAUI开发跨平台应用技术栈手册

## 一、技术栈概述

### 1.1 核心技术
- **编程语言**：C#
- **开发框架**：.NET MAUI
- **UI框架**：MAUI Controls
- **构建工具**：.NET CLI / Visual Studio
- **版本要求**：.NET 8.0+, MAUI 8.0+

### 1.2 依赖管理
- **包管理**：NuGet
- **依赖仓库**：nuget.org
- **版本控制**：Git

### 1.3 测试框架
- **单元测试**：xUnit / NUnit / MSTest
- **UI测试**：Appium / Xamarin.UITest
- **集成测试**：.NET Test Framework

## 二、环境搭建

### 2.1 开发环境配置

```xml
<!-- MauiApp.csproj -->
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFrameworks>net8.0-android;net8.0-ios;net8.0-maccatalyst</TargetFrameworks>
    <TargetFrameworks Condition="$([MSBuild]::IsOSPlatform('windows'))">$(TargetFrameworks);net8.0-windows10.0.19041.0</TargetFrameworks>
    <OutputType>Exe</OutputType>
    <RootNamespace>MauiApp</RootNamespace>
    <UseMaui>true</UseMaui>
    <SingleProject>true</SingleProject>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>

    <SupportedOSPlatformVersion Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)') == 'ios'">11.0</SupportedOSPlatformVersion>
    <SupportedOSPlatformVersion Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)') == 'maccatalyst'">13.1</SupportedOSPlatformVersion>
    <SupportedOSPlatformVersion Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)') == 'android'">21.0</SupportedOSPlatformVersion>
    <SupportedOSPlatformVersion Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)') == 'windows'">10.0.17763.0</SupportedOSPlatformVersion>
    <TargetPlatformMinVersion Condition="$([MSBuild]::GetTargetPlatformIdentifier('$(TargetFramework)') == 'windows'">10.0.17763.0</TargetPlatformMinVersion>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Maui.Controls" Version="8.0.0" />
    <PackageReference Include="Microsoft.Maui.Controls.Compatibility" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Debug" Version="8.0.0" />
  </ItemGroup>

</Project>
```

### 2.2 项目初始化

```bash
# 安装.NET SDK
# 下载并安装.NET 8.0 SDK

# 安装MAUI工作负载
dotnet workload install maui

# 创建MAUI项目
dotnet new maui -n MauiApp

# 进入项目目录
cd MauiApp

# 运行应用
dotnet run

# 构建应用
dotnet build
```

## 三、基础语法与特性

### 3.1 C#基础语法

#### 3.1.1 变量声明

```csharp
// var：类型推断
var name = "张三";
var age = 25;

// 显式类型声明
string username = "李四";
int userAge = 30;
double price = 99.99;

// 常量
const int MaxCount = 100;
readonly DateTime CreatedDate = DateTime.Now;

// 可空类型
string? nullableString = null;
int? nullableInt = null;

// 列表
List<int> numbers = new() { 1, 2, 3, 4, 5 };
List<string> fruits = new() { "苹果", "香蕉", "橙子" };

// 字典
Dictionary<string, dynamic> person = new()
{
    { "name", "王五" },
    { "age", 28 },
    { "email", "wangwu@example.com" }
};
```

#### 3.1.2 函数定义

```csharp
// 基本函数
string Greet(string name)
{
    return $"你好，{name}";
}

// 表达式体方法
string Greet2(string name) => $"你好，{name}";

// 可选参数
void CreateUser(string name, int age = 18)
{
    Console.WriteLine($"创建用户：{name}，年龄：{age}");
}

// 命名参数
void PrintInfo(string name, int age)
{
    Console.WriteLine($"姓名：{name}，年龄：{age}");
}

// 使用命名参数
PrintInfo(name: "张三", age: 25);

// 可变参数
int SumAll(params int[] numbers)
{
    return numbers.Sum();
}

// Lambda表达式
Func<int, int, int> add = (a, b) => a + b;
var result = add(3, 5);

// 委托
delegate void Operation(int a, int b);

void PerformOperation(int a, int b, Operation operation)
{
    operation(a, b);
}

// 使用委托
PerformOperation(10, 20, (a, b) => Console.WriteLine(a + b));
```

#### 3.1.3 类定义

```csharp
// 类定义
public class User
{
    // 私有字段
    private readonly int _id;
    private string _name;
    private string _email;
    private int _age;

    // 属性
    public int Id => _id;
    public string Name
    {
        get => _name;
        set => _name = value;
    }
    public string Email
    {
        get => _email;
        set => _email = value;
    }
    public int Age
    {
        get => _age;
        set
        {
            if (value >= 0)
                _age = value;
        }
    }

    // 构造函数
    public User(int id, string name, string email, int age)
    {
        _id = id;
        _name = name;
        _email = email;
        _age = age;
    }

    // 方法
    public string Introduce()
    {
        return $"我叫{_name}，今年{_age}岁";
    }

    // 计算属性
    public bool IsAdult => _age >= 18;

    // 静态方法
    public static User CreateDefault()
    {
        return new User(0, "默认用户", "default@example.com", 18);
    }
}

// 使用类
var user = new User(1, "赵六", "zhaoliu@example.com", 25);
Console.WriteLine(user.Introduce());
Console.WriteLine(user.IsAdult);
```

#### 3.1.4 异步编程

```csharp
// 异步方法
async Task<string> FetchDataAsync()
{
    await Task.Delay(2000);
    return "数据加载完成";
}

// 使用异步方法
async Task LoadDataAsync()
{
    try
    {
        string data = await FetchDataAsync();
        Console.WriteLine(data);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"加载失败：{ex.Message}");
    }
}

// Task常用方法
async void TaskExamples()
{
    // Task.Run：在线程池中执行
    var result = await Task.Run(() => {
        Thread.Sleep(1000);
        return "计算完成";
    });

    // Task.WhenAll：等待所有任务完成
    var tasks = new List<Task<string>>
    {
        FetchDataAsync(),
        FetchDataAsync()
    };
    var results = await Task.WhenAll(tasks);

    // Task.WhenAny：等待任一任务完成
    var completedTask = await Task.WhenAny(tasks);
    var firstResult = await completedTask;
}
```

### 3.2 MAUI特性

#### 3.2.1 XAML基础

```xml
<?xml version="1.0" encoding="utf-8" ?>
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
             xmlns:x="http://schemas.microsoft.com/winfx/2009/xaml"
             x:Class="MauiApp.MainPage">

    <ScrollView>
        <VerticalStackLayout 
            Spacing="25" 
            Padding="30,0" 
            VerticalOptions="Center">

            <Label 
                Text="Hello, MAUI!"
                SemanticProperties.HeadingLevel="Level1"
                FontSize="32"
                HorizontalOptions="Center" />

            <Label 
                Text="Welcome to .NET MAUI"
                SemanticProperties.HeadingLevel="Level2"
                SemanticProperties.Description="Welcome to .NET Multi-platform App UI"
                FontSize="18"
                HorizontalOptions="Center" />

            <Button 
                x:Name="CounterBtn"
                Text="Click me"
                Clicked="OnCounterClicked"
                HorizontalOptions="Center" />

        </VerticalStackLayout>
    </ScrollView>

</ContentPage>
```

#### 3.2.2 常用控件

```xml
<?xml version="1.0" encoding="utf-8" ?>
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
             xmlns:x="http://schemas.microsoft.com/winfx/2009/xaml"
             x:Class="MauiApp.ControlsPage">

    <ScrollView>
        <StackLayout Padding="20" Spacing="15">

            <!-- Label：标签 -->
            <Label Text="常用控件" 
                   FontSize="24" 
                   FontAttributes="Bold" />

            <!-- Entry：输入框 -->
            <Label Text="用户名：" />
            <Entry x:Name="UsernameEntry" 
                   Placeholder="请输入用户名" />

            <!-- Editor：多行输入 -->
            <Label Text="描述：" />
            <Editor x:Name="DescriptionEditor"
                    Placeholder="请输入描述"
                    HeightRequest="100" />

            <!-- Button：按钮 -->
            <Button Text="提交" 
                    Clicked="OnSubmitClicked" />

            <!-- CheckBox：复选框 -->
            <CheckBox x:Name="AgreeCheckBox"
                      IsChecked="False" />
            <Label Text="我同意协议" />

            <!-- Switch：开关 -->
            <Switch x:Name="NotificationSwitch"
                    IsToggled="False" />
            <Label Text="启用通知" />

            <!-- Slider：滑块 -->
            <Label Text="音量：" />
            <Slider x:Name="VolumeSlider"
                    Minimum="0"
                    Maximum="100"
                    Value="50" />

            <!-- Picker：选择器 -->
            <Label Text="城市：" />
            <Picker x:Name="CityPicker"
                    Title="选择城市">
                <Picker.Items>
                    <x:String>北京</x:String>
                    <x:String>上海</x:String>
                    <x:String>广州</x:String>
                    <x:String>深圳</x:String>
                </Picker.Items>
            </Picker>

            <!-- DatePicker：日期选择器 -->
            <Label Text="生日：" />
            <DatePicker x:Name="BirthdayDatePicker" />

            <!-- TimePicker：时间选择器 -->
            <Label Text="时间：" />
            <TimePicker x:Name="TimeTimePicker" />

            <!-- Image：图片 -->
            <Image Source="dotnet_bot.png"
                   HeightRequest="200"
                   HorizontalOptions="Center" />

            <!-- ActivityIndicator：加载指示器 -->
            <ActivityIndicator x:Name="LoadingIndicator"
                              IsRunning="False"
                              Color="Blue" />

        </StackLayout>
    </ScrollView>

</ContentPage>
```

#### 3.2.3 布局控件

```xml
<?xml version="1.0" encoding="utf-8" ?>
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
             xmlns:x="http://schemas.microsoft.com/winfx/2009/xaml"
             x:Class="MauiApp.LayoutsPage">

    <ScrollView>
        <StackLayout Padding="20" Spacing="20">

            <!-- StackLayout：堆叠布局 -->
            <Label Text="StackLayout布局" 
                   FontSize="20" 
                   FontAttributes="Bold" />
            <StackLayout Orientation="Horizontal" Spacing="10">
                <BoxView Color="Red" WidthRequest="80" HeightRequest="80" />
                <BoxView Color="Green" WidthRequest="80" HeightRequest="80" />
                <BoxView Color="Blue" WidthRequest="80" HeightRequest="80" />
            </StackLayout>

            <!-- Grid：网格布局 -->
            <Label Text="Grid布局" 
                   FontSize="20" 
                   FontAttributes="Bold" />
            <Grid RowDefinitions="Auto,Auto,Auto" 
                  ColumnDefinitions="*,*,*">
                <BoxView Color="Red" Grid.Row="0" Grid.Column="0" />
                <BoxView Color="Green" Grid.Row="0" Grid.Column="1" />
                <BoxView Color="Blue" Grid.Row="0" Grid.Column="2" />
                <BoxView Color="Yellow" Grid.Row="1" Grid.Column="0" />
                <BoxView Color="Purple" Grid.Row="1" Grid.Column="1" />
                <BoxView Color="Orange" Grid.Row="1" Grid.Column="2" />
                <BoxView Color="Pink" Grid.Row="2" Grid.Column="0" 
                         Grid.ColumnSpan="2" />
                <BoxView Color="Cyan" Grid.Row="2" Grid.Column="2" />
            </Grid>

            <!-- FlexLayout：弹性布局 -->
            <Label Text="FlexLayout布局" 
                   FontSize="20" 
                   FontAttributes="Bold" />
            <FlexLayout Direction="Row" 
                        Wrap="Wrap" 
                        JustifyContent="SpaceEvenly">
                <BoxView Color="Red" WidthRequest="80" HeightRequest="80" />
                <BoxView Color="Green" WidthRequest="80" HeightRequest="80" />
                <BoxView Color="Blue" WidthRequest="80" HeightRequest="80" />
                <BoxView Color="Yellow" WidthRequest="80" HeightRequest="80" />
                <BoxView Color="Purple" WidthRequest="80" HeightRequest="80" />
            </FlexLayout>

            <!-- AbsoluteLayout：绝对布局 -->
            <Label Text="AbsoluteLayout布局" 
                   FontSize="20" 
                   FontAttributes="Bold" />
            <AbsoluteLayout HeightRequest="200">
                <BoxView Color="Red" 
                         WidthRequest="80" HeightRequest="80"
                         AbsoluteLayout.LayoutBounds="0,0,80,80" />
                <BoxView Color="Green" 
                         WidthRequest="80" HeightRequest="80"
                         AbsoluteLayout.LayoutBounds="60,60,80,80" />
                <BoxView Color="Blue" 
                         WidthRequest="80" HeightRequest="80"
                         AbsoluteLayout.LayoutBounds="120,120,80,80" />
            </AbsoluteLayout>

        </StackLayout>
    </ScrollView>

</ContentPage>
```

## 四、MVVM架构实战

### 4.1 ViewModel实现

```csharp
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

public class BaseViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    protected bool SetProperty<T>(ref T backingStore, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(backingStore, value))
            return false;

        backingStore = value;
        OnPropertyChanged(propertyName);
        return true;
    }
}

public class UserViewModel : BaseViewModel
{
    private ObservableCollection<User> _users;
    private bool _isLoading;
    private string? _errorMessage;

    public ObservableCollection<User> Users
    {
        get => _users;
        set => SetProperty(ref _users, value);
    }

    public bool IsLoading
    {
        get => _isLoading;
        set => SetProperty(ref _isLoading, value);
    }

    public string? ErrorMessage
    {
        get => _errorMessage;
        set => SetProperty(ref _errorMessage, value);
    }

    public UserViewModel()
    {
        Users = new ObservableCollection<User>();
        LoadUsersCommand = new Command(async () => await LoadUsersAsync());
        AddUserCommand = new Command<User>(async (user) => await AddUserAsync(user));
    }

    public Command LoadUsersCommand { get; }
    public Command<User> AddUserCommand { get; }

    private async Task LoadUsersAsync()
    {
        try
        {
            IsLoading = true;
            ErrorMessage = null;

            var users = await UserRepository.GetUsersAsync();
            Users.Clear();
            foreach (var user in users)
            {
                Users.Add(user);
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task AddUserAsync(User user)
    {
        try
        {
            await UserRepository.AddUserAsync(user);
            await LoadUsersAsync();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }
}
```

### 4.2 Repository模式

```csharp
using System.Net.Http.Json;

public class User
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public int Age { get; set; }
}

public class UserRepository
{
    private static readonly HttpClient _httpClient = new()
    {
        BaseAddress = new Uri("https://api.example.com")
    };

    public static async Task<List<User>> GetUsersAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync("/users");
            response.EnsureSuccessStatusCode();

            return await response.Content.ReadFromJsonAsync<List<User>>() 
                   ?? new List<User>();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"获取用户列表失败：{ex.Message}");
            throw;
        }
    }

    public static async Task<User> AddUserAsync(User user)
    {
        try
        {
            var response = await _httpClient.PostAsJsonAsync("/users", user);
            response.EnsureSuccessStatusCode();

            return await response.Content.ReadFromJsonAsync<User>() 
                   ?? user;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"添加用户失败：{ex.Message}");
            throw;
        }
    }

    public static async Task<bool> DeleteUserAsync(int id)
    {
        try
        {
            var response = await _httpClient.DeleteAsync($"/users/{id}");
            return response.IsSuccessStatusCode;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"删除用户失败：{ex.Message}");
            return false;
        }
    }
}
```

## 五、项目实战案例

### 5.1 项目一：适老居家生活辅助系统

#### 5.1.1 项目概述
开发一个面向老年人的MAUI应用，包含健康监测、紧急呼叫、家属关联等功能。

#### 5.1.2 核心功能实现

**紧急呼叫功能**

```csharp
// MainPage.xaml
<?xml version="1.0" encoding="utf-8" ?>
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
             xmlns:x="http://schemas.microsoft.com/winfx/2009/xaml"
             x:Class="MauiApp.MainPage">

    <Grid RowDefinitions="Auto,*,Auto" Padding="20">
        
        <!-- 标题 -->
        <Label Grid.Row="0"
               Text="紧急呼叫"
               FontSize="28"
               FontAttributes="Bold"
               HorizontalOptions="Center"
               Margin="0,0,0,30" />

        <!-- 紧急呼叫按钮 -->
        <Button Grid.Row="1"
                x:Name="EmergencyButton"
                Text="紧急呼叫"
                FontSize="24"
                WidthRequest="200"
                HeightRequest="200"
                CornerRadius="100"
                BackgroundColor="#FF5252"
                TextColor="White"
                Clicked="OnEmergencyClicked"
                HorizontalOptions="Center"
                VerticalOptions="Center" />

        <!-- 倒计时显示 -->
        <Label Grid.Row="1"
               x:Name="CountdownLabel"
               Text=""
               FontSize="32"
               FontAttributes="Bold"
               TextColor="#FF5252"
               HorizontalOptions="Center"
               VerticalOptions="End"
               Margin="0,0,0,30"
               IsVisible="False" />

        <!-- 联系人设置 -->
        <StackLayout Grid.Row="2" Spacing="10">
            <Label Text="紧急联系人" FontSize="16" />
            <Entry x:Name="EmergencyContactEntry"
                   Placeholder="请输入电话号码"
                   Keyboard="Telephone"
                   TextChanged="OnContactTextChanged" />
        </StackLayout>

    </Grid>

</ContentPage>
```

```csharp
// MainPage.xaml.cs
using System.Diagnostics;

namespace MauiApp;

public partial class MainPage : ContentPage
{
    private int _countdown = 0;
    private CancellationTokenSource? _cancellationTokenSource;

    public MainPage()
    {
        InitializeComponent();
        LoadEmergencyContact();
    }

    private async void LoadEmergencyContact()
    {
        var contact = await Preferences.Default.GetAsync<string>("emergency_contact", "110");
        EmergencyContactEntry.Text = contact;
    }

    private async void OnContactTextChanged(object? sender, TextChangedEventArgs e)
    {
        var contact = EmergencyContactEntry.Text;
        await Preferences.Default.SetAsync("emergency_contact", contact);
    }

    private async void OnEmergencyClicked(object? sender, EventArgs e)
    {
        if (_countdown > 0)
            return;

        var contact = EmergencyContactEntry.Text;
        if (string.IsNullOrWhiteSpace(contact))
        {
            await DisplayAlert("提示", "请先设置紧急联系人", "确定");
            return;
        }

        await StartCountdownAsync(contact);
    }

    private async Task StartCountdownAsync(string contact)
    {
        _countdown = 3;
        CountdownLabel.IsVisible = true;
        CountdownLabel.Text = $"{_countdown}秒后拨打";

        _cancellationTokenSource = new CancellationTokenSource();

        try
        {
            for (int i = _countdown; i > 0; i--)
            {
                CountdownLabel.Text = $"{i}秒后拨打";
                await Task.Delay(1000, _cancellationTokenSource.Token);
            }

            await MakeEmergencyCallAsync(contact);
        }
        catch (OperationCanceledException)
        {
            // 用户取消
        }
        finally
        {
            ResetCountdown();
        }
    }

    private void ResetCountdown()
    {
        _countdown = 0;
        CountdownLabel.IsVisible = false;
        _cancellationTokenSource?.Cancel();
        _cancellationTokenSource?.Dispose();
        _cancellationTokenSource = null;
    }

    private async Task MakeEmergencyCallAsync(string phoneNumber)
    {
        try
        {
            if (PhoneDialer.Default.IsSupported)
            {
                PhoneDialer.Default.Open(phoneNumber);
            }
            else
            {
                await DisplayAlert("提示", "当前设备不支持拨打电话", "确定");
            }
        }
        catch (Exception ex)
        {
            await DisplayAlert("错误", $"拨打电话失败：{ex.Message}", "确定");
        }
    }
}
```

**健康监测数据展示**

```csharp
// HealthMonitoringPage.xaml
<?xml version="1.0" encoding="utf-8" ?>
<ContentPage xmlns="http://schemas.microsoft.com/dotnet/2021/maui"
             xmlns:x="http://schemas.microsoft.com/winfx/2009/xaml"
             x:Class="MauiApp.HealthMonitoringPage">

    <ScrollView>
        <StackLayout Padding="20" Spacing="20">

            <Label Text="健康监测"
                   FontSize="28"
                   FontAttributes="Bold"
                   HorizontalOptions="Center" />

            <!-- 心率卡片 -->
            <Frame CornerRadius="15" Padding="20" HasShadow="True">
                <Grid ColumnDefinitions="Auto,*">
                    <Label Grid.Column="0"
                           Text="❤️"
                           FontSize="48"
                           VerticalOptions="Center" />
                    <StackLayout Grid.Column="1" Spacing="5" Margin="20,0,0,0">
                        <Label Text="心率"
                               FontSize="16"
                               TextColor="#666666" />
                        <Label x:Name="HeartRateLabel"
                               Text="75 bpm"
                               FontSize="24"
                               FontAttributes="Bold"
                               TextColor="#FF5252" />
                    </StackLayout>
                </Grid>
            </Frame>

            <!-- 血压卡片 -->
            <Frame CornerRadius="15" Padding="20" HasShadow="True">
                <Grid ColumnDefinitions="Auto,*">
                    <Label Grid.Column="0"
                           Text="🩺"
                           FontSize="48"
                           VerticalOptions="Center" />
                    <StackLayout Grid.Column="1" Spacing="5" Margin="20,0,0,0">
                        <Label Text="血压"
                               FontSize="16"
                               TextColor="#666666" />
                        <Label x:Name="BloodPressureLabel"
                               Text="120/80 mmHg"
                               FontSize="24"
                               FontAttributes="Bold"
                               TextColor="#2196F3" />
                    </StackLayout>
                </Grid>
            </Frame>

            <!-- 血糖卡片 -->
            <Frame CornerRadius="15" Padding="20" HasShadow="True">
                <Grid ColumnDefinitions="Auto,*">
                    <Label Grid.Column="0"
                           Text="🩸"
                           FontSize="48"
                           VerticalOptions="Center" />
                    <StackLayout Grid.Column="1" Spacing="5" Margin="20,0,0,0">
                        <Label Text="血糖"
                               FontSize="16"
                               TextColor="#666666" />
                        <Label x:Name="BloodSugarLabel"
                               Text="5.6 mmol/L"
                               FontSize="24"
                               FontAttributes="Bold"
                               TextColor="#4CAF50" />
                    </StackLayout>
                </Grid>
            </Frame>

            <!-- 体温卡片 -->
            <Frame CornerRadius="15" Padding="20" HasShadow="True">
                <Grid ColumnDefinitions="Auto,*">
                    <Label Grid.Column="0"
                           Text="🌡️"
                           FontSize="48"
                           VerticalOptions="Center" />
                    <StackLayout Grid.Column="1" Spacing="5" Margin="20,0,0,0">
                        <Label Text="体温"
                               FontSize="16"
                               TextColor="#666666" />
                        <Label x:Name="TemperatureLabel"
                               Text="36.5 °C"
                               FontSize="24"
                               FontAttributes="Bold"
                               TextColor="#FF9800" />
                    </StackLayout>
                </Grid>
            </Frame>

            <!-- 刷新按钮 -->
            <Button Text="刷新数据"
                    Clicked="OnRefreshClicked"
                    HorizontalOptions="Center" />

        </StackLayout>
    </ScrollView>

</ContentPage>
```

```csharp
// HealthMonitoringPage.xaml.cs
namespace MauiApp;

public partial class HealthMonitoringPage : ContentPage
{
    public HealthMonitoringPage()
    {
        InitializeComponent();
        LoadHealthData();
    }

    private async void LoadHealthData()
    {
        try
        {
            // 模拟从服务器加载数据
            await Task.Delay(1000);

            var random = new Random();
            var healthData = new
            {
                HeartRate = random.Next(60, 90),
                BloodPressure = $"{random.Next(110, 130)}/{random.Next(70, 90)}",
                BloodSugar = (random.NextDouble() * 2 + 4).ToString("F1"),
                Temperature = (random.NextDouble() * 1 + 36).ToString("F1")
            };

            HeartRateLabel.Text = $"{healthData.HeartRate} bpm";
            BloodPressureLabel.Text = $"{healthData.BloodPressure} mmHg";
            BloodSugarLabel.Text = $"{healthData.BloodSugar} mmol/L";
            TemperatureLabel.Text = $"{healthData.Temperature} °C";
        }
        catch (Exception ex)
        {
            await DisplayAlert("错误", $"加载健康数据失败：{ex.Message}", "确定");
        }
    }

    private void OnRefreshClicked(object? sender, EventArgs e)
    {
        LoadHealthData();
    }
}
```

## 六、测试与调试

### 6.1 单元测试

```csharp
using Xunit;

public class UserViewModelTests
{
    [Fact]
    public async Task LoadUsers_ShouldPopulateUsers()
    {
        // Arrange
        var viewModel = new UserViewModel();

        // Act
        await viewModel.LoadUsersCommand.ExecuteAsync(null);

        // Assert
        Assert.NotNull(viewModel.Users);
        Assert.True(viewModel.Users.Count > 0);
    }

    [Fact]
    public void IsAdult_ShouldReturnTrue_ForAdultUser()
    {
        // Arrange
        var user = new User { Id = 1, Name = "张三", Email = "zhangsan@example.com", Age = 25 };

        // Act
        var isAdult = user.Age >= 18;

        // Assert
        Assert.True(isAdult);
    }
}
```

### 6.2 UI测试

```csharp
using Xunit;
using Xunit.Abstractions;

public class MainPageUITests
{
    private readonly ITestOutputHelper _output;

    public MainPageUITests(ITestOutputHelper output)
    {
        _output = output;
    }

    [Fact]
    public void EmergencyButton_ShouldBeVisible()
    {
        // Arrange & Act & Assert
        // 使用Appium或Xamarin.UITest进行UI测试
        _output.WriteLine("紧急呼叫按钮应该可见");
    }
}
```

## 七、性能优化

### 7.1 列表优化

```csharp
// 使用CollectionView替代ListView
public class OptimizedListPage : ContentPage
{
    public OptimizedListPage()
    {
        var collectionView = new CollectionView
        {
            ItemsLayout = new LinearItemsLayout(ItemsLayoutOrientation.Vertical),
            ItemTemplate = new DataTemplate(() =>
            {
                var grid = new Grid
                {
                    Padding = 10,
                    ColumnDefinitions =
                    {
                        new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
                    }
                };

                var label = new Label();
                label.SetBinding(Label.TextProperty, "Name");

                grid.Add(label);
                return grid;
            })
        };

        Content = collectionView;
    }
}
```

### 7.2 图片优化

```csharp
// 使用CachedImage
public class OptimizedImagePage : ContentPage
{
    public OptimizedImagePage()
    {
        var cachedImage = new CachedImage
        {
            Source = "https://example.com/image.jpg",
            WidthRequest = 200,
            HeightRequest = 200,
            Aspect = Aspect.AspectFill,
            CacheDuration = TimeSpan.FromDays(30),
            LoadingPlaceholder = "loading.png",
            ErrorPlaceholder = "error.png"
        };

        Content = new StackLayout
        {
            Children = { cachedImage }
        };
    }
}
```

## 八、发布与部署

### 8.1 Android发布

```bash
# 构建Android APK
dotnet publish -f net8.0-android -c Release

# 构建Android App Bundle
dotnet publish -f net8.0-android -c Release /p:AndroidPackageFormat=aab
```

### 8.2 iOS发布

```bash
# 构建iOS应用
dotnet publish -f net8.0-ios -c Release

# 使用Xcode打开项目进行签名和打包
```

### 8.3 Windows发布

```bash
# 构建Windows应用
dotnet publish -f net8.0-windows10.0.19041.0 -c Release
```

## 九、常见问题与解决方案

### 9.1 内存泄漏
**问题**：事件处理器未取消订阅导致内存泄漏

**解决方案**：
```csharp
public class MyPage : ContentPage
{
    private readonly MyViewModel _viewModel;

    public MyPage()
    {
        _viewModel = new MyViewModel();
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        // 处理属性变化
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
    }
}
```

### 9.2 线程问题
**问题**：在后台线程更新UI

**解决方案**：
```csharp
private async Task LoadDataAsync()
{
    // 在后台线程执行耗时操作
    var data = await Task.Run(() => FetchData());

    // 切换到主线程更新UI
    await MainThread.InvokeOnMainThreadAsync(() =>
    {
        MyLabel.Text = data;
    });
}
```

## 十、学习资源

### 10.1 官方文档
- .NET MAUI官方文档：https://learn.microsoft.com/dotnet/maui/
- C#语言指南：https://learn.microsoft.com/dotnet/csharp/
- XAML文档：https://learn.microsoft.com/dotnet/maui/xaml/

### 10.2 推荐书籍
- 《.NET MAUI实战》
- 《C#高级编程》
- 《移动应用开发实战》

### 10.3 在线课程
- Microsoft Learn
- .NET MAUI官方教程
- Pluralsight课程

## 十一、实验项目要求

### 11.1 基础要求
1. 使用C#语言开发
2. 采用.NET MAUI框架
3. 实现跨平台适配（Android、iOS、Windows）
4. 集成MVVM架构
5. 实现组件化开发
6. 添加单元测试和UI测试

### 11.2 进阶要求
1. 实现自定义控件
2. 集成第三方SDK（如地图、支付等）
3. 优化应用性能和渲染效率
4. 实现深色模式支持
5. 添加国际化支持
6. 实现无障碍功能

### 11.3 提交要求
1. 完整的项目源代码
2. 详细的README文档
3. Android APK、iOS IPA和Windows安装包
4. 测试报告
5. 技术文档和架构设计图