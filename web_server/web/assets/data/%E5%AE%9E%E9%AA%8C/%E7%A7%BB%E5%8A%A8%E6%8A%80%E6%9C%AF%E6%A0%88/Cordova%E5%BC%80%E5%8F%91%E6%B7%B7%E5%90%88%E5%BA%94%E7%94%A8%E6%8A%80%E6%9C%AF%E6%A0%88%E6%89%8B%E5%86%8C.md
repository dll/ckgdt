# Cordova开发混合应用技术栈手册

## 一、技术栈概述

### 1.1 核心技术
- **编程语言**：JavaScript / HTML5 / CSS3
- **开发框架**：Apache Cordova
- **UI框架**：Bootstrap / Ionic / Framework7
- **构建工具**：Cordova CLI / npm
- **版本要求**：Cordova 11.0+, Node.js 16+

### 1.2 依赖管理
- **包管理**：npm
- **依赖仓库**：npm官方仓库
- **版本控制**：Git

### 1.3 测试框架
- **单元测试**：Jest
- **E2E测试**：Protractor / Cypress
- **组件测试**：Mocha + Chai

## 二、环境搭建

### 2.1 开发环境配置

```json
{
  "name": "cordova-app",
  "version": "1.0.0",
  "description": "Cordova混合应用",
  "main": "index.js",
  "scripts": {
    "start": "cordova serve",
    "build": "cordova build",
    "build:android": "cordova build android",
    "build:ios": "cordova build ios",
    "run:android": "cordova run android",
    "run:ios": "cordova run ios"
  },
  "dependencies": {
    "cordova-android": "^12.0.0",
    "cordova-ios": "^6.2.0",
    "cordova-plugin-camera": "^6.0.0",
    "cordova-plugin-file": "^7.0.0",
    "cordova-plugin-geolocation": "^5.0.0",
    "cordova-plugin-device": "^2.1.0",
    "cordova-plugin-inappbrowser": "^5.0.0"
  },
  "devDependencies": {
    "cordova": "^11.0.0",
    "eslint": "^8.50.0"
  }
}
```

### 2.2 项目初始化

```bash
# 安装Cordova CLI
npm install -g cordova

# 创建Cordova项目
cordova create myapp com.example.myapp MyApp

# 进入项目目录
cd myapp

# 添加平台
cordova platform add android
cordova platform add ios

# 安装插件
cordova plugin add cordova-plugin-camera
cordova plugin add cordova-plugin-geolocation
cordova plugin add cordova-plugin-file
```

## 三、基础语法与特性

### 3.1 HTML5基础

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'self' data: gap: https://ssl.gstatic.com 'unsafe-eval'; style-src 'self' 'unsafe-inline'; media-src *; img-src 'self' data: content:;">
    <title>我的Cordova应用</title>
    <link rel="stylesheet" href="css/index.css">
</head>
<body>
    <div class="app">
        <h1>欢迎使用Cordova</h1>
        <div id="deviceready" class="blink">
            <p class="event listening">正在连接设备...</p>
            <p class="event received">设备已就绪</p>
        </div>
        <button id="cameraBtn">拍照</button>
        <button id="locationBtn">获取位置</button>
        <div id="result"></div>
    </div>
    <script type="text/javascript" src="cordova.js"></script>
    <script type="text/javascript" src="js/index.js"></script>
</body>
</html>
```

### 3.2 JavaScript基础

```javascript
// 等待设备就绪
document.addEventListener('deviceready', onDeviceReady, false);

function onDeviceReady() {
    console.log('设备已就绪');
    
    // 获取设备信息
    const deviceInfo = {
        platform: device.platform,
        version: device.version,
        model: device.model,
        uuid: device.uuid
    };
    
    console.log('设备信息:', deviceInfo);
    
    // 绑定按钮事件
    document.getElementById('cameraBtn').addEventListener('click', takePicture);
    document.getElementById('locationBtn').addEventListener('click', getLocation);
}

// 拍照功能
function takePicture() {
    navigator.camera.getPicture(
        function(imageData) {
            const image = document.getElementById('myImage');
            image.src = "data:image/jpeg;base64," + imageData;
        },
        function(message) {
            alert('拍照失败: ' + message);
        },
        {
            quality: 50,
            destinationType: Camera.DestinationType.DATA_URL
        }
    );
}

// 获取位置
function getLocation() {
    navigator.geolocation.getCurrentPosition(
        function(position) {
            const result = document.getElementById('result');
            result.innerHTML = `
                <p>纬度: ${position.coords.latitude}</p>
                <p>经度: ${position.coords.longitude}</p>
                <p>精度: ${position.coords.accuracy}米</p>
            `;
        },
        function(error) {
            alert('获取位置失败: ' + error.message);
        },
        { enableHighAccuracy: true }
    );
}
```

### 3.3 CSS3样式

```css
/* 基础样式 */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    background-color: #f5f5f5;
    color: #333;
}

.app {
    max-width: 600px;
    margin: 0 auto;
    padding: 20px;
    background-color: #fff;
    min-height: 100vh;
}

h1 {
    text-align: center;
    color: #2c3e50;
    margin-bottom: 30px;
}

/* 按钮样式 */
button {
    width: 100%;
    padding: 15px;
    margin: 10px 0;
    background-color: #3498db;
    color: #fff;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    cursor: pointer;
    transition: background-color 0.3s;
}

button:active {
    background-color: #2980b9;
}

/* 结果显示区域 */
#result {
    margin-top: 20px;
    padding: 15px;
    background-color: #ecf0f1;
    border-radius: 8px;
}

/* 图片样式 */
#myImage {
    width: 100%;
    height: auto;
    border-radius: 8px;
    margin-top: 20px;
}

/* 响应式设计 */
@media (max-width: 768px) {
    .app {
        padding: 15px;
    }
    
    h1 {
        font-size: 24px;
    }
    
    button {
        padding: 12px;
        font-size: 14px;
    }
}
```

## 四、Cordova插件开发

### 4.1 相机插件

```javascript
// 使用相机插件
function takePhoto() {
    const options = {
        quality: 75,
        destinationType: Camera.DestinationType.FILE_URI,
        sourceType: Camera.PictureSourceType.CAMERA,
        allowEdit: true,
        encodingType: Camera.EncodingType.JPEG,
        targetWidth: 800,
        targetHeight: 800,
        saveToPhotoAlbum: true
    };
    
    navigator.camera.getPicture(
        function(imageURI) {
            displayImage(imageURI);
        },
        function(error) {
            console.error('拍照失败:', error);
            alert('拍照失败: ' + error);
        },
        options
    );
}

function displayImage(imageURI) {
    const imageElement = document.getElementById('photo');
    imageElement.src = imageURI;
    imageElement.style.display = 'block';
}

// 从相册选择图片
function selectFromGallery() {
    const options = {
        quality: 75,
        destinationType: Camera.DestinationType.FILE_URI,
        sourceType: Camera.PictureSourceType.PHOTOLIBRARY,
        mediaType: Camera.MediaType.PICTURE
    };
    
    navigator.camera.getPicture(
        function(imageURI) {
            displayImage(imageURI);
        },
        function(error) {
            console.error('选择图片失败:', error);
        },
        options
    );
}
```

### 4.2 地理位置插件

```javascript
// 获取当前位置
function getCurrentLocation() {
    const options = {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0
    };
    
    navigator.geolocation.getCurrentPosition(
        function(position) {
            const location = {
                latitude: position.coords.latitude,
                longitude: position.coords.longitude,
                accuracy: position.coords.accuracy,
                altitude: position.coords.altitude,
                altitudeAccuracy: position.coords.altitudeAccuracy,
                heading: position.coords.heading,
                speed: position.coords.speed,
                timestamp: position.timestamp
            };
            
            displayLocation(location);
        },
        function(error) {
            console.error('获取位置失败:', error);
            handleLocationError(error);
        },
        options
    );
}

// 持续监听位置变化
let watchId = null;

function startLocationWatch() {
    const options = {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 0
    };
    
    watchId = navigator.geolocation.watchPosition(
        function(position) {
            const location = {
                latitude: position.coords.latitude,
                longitude: position.coords.longitude,
                accuracy: position.coords.accuracy
            };
            
            updateLocationDisplay(location);
        },
        function(error) {
            console.error('位置监听失败:', error);
        },
        options
    );
}

function stopLocationWatch() {
    if (watchId !== null) {
        navigator.geolocation.clearWatch(watchId);
        watchId = null;
    }
}

function displayLocation(location) {
    const resultDiv = document.getElementById('locationResult');
    resultDiv.innerHTML = `
        <h3>当前位置</h3>
        <p>纬度: ${location.latitude.toFixed(6)}</p>
        <p>经度: ${location.longitude.toFixed(6)}</p>
        <p>精度: ${location.accuracy.toFixed(2)}米</p>
        ${location.altitude ? `<p>海拔: ${location.altitude.toFixed(2)}米</p>` : ''}
    `;
}

function handleLocationError(error) {
    let message = '';
    switch(error.code) {
        case error.PERMISSION_DENIED:
            message = '用户拒绝了位置请求';
            break;
        case error.POSITION_UNAVAILABLE:
            message = '位置信息不可用';
            break;
        case error.TIMEOUT:
            message = '请求位置超时';
            break;
        default:
            message = '未知错误';
    }
    alert(message);
}
```

### 4.3 文件系统插件

```javascript
// 写入文件
function writeFile(filename, content) {
    window.requestFileSystem(LocalFileSystem.PERSISTENT, 0, function(fs) {
        fs.root.getFile(filename, {create: true, exclusive: false}, function(fileEntry) {
            fileEntry.createWriter(function(fileWriter) {
                fileWriter.onwriteend = function() {
                    console.log('文件写入成功');
                    alert('文件保存成功');
                };
                
                fileWriter.onerror = function(e) {
                    console.error('文件写入失败:', e);
                    alert('文件保存失败');
                };
                
                const blob = new Blob([content], {type: 'text/plain'});
                fileWriter.write(blob);
            });
        });
    }, function(error) {
        console.error('文件系统访问失败:', error);
    });
}

// 读取文件
function readFile(filename) {
    window.requestFileSystem(LocalFileSystem.PERSISTENT, 0, function(fs) {
        fs.root.getFile(filename, {}, function(fileEntry) {
            fileEntry.file(function(file) {
                const reader = new FileReader();
                reader.onloadend = function() {
                    console.log('文件内容:', this.result);
                    document.getElementById('fileContent').textContent = this.result;
                };
                reader.readAsText(file);
            });
        }, function(error) {
            console.error('文件读取失败:', error);
        });
    });
}

// 删除文件
function deleteFile(filename) {
    window.requestFileSystem(LocalFileSystem.PERSISTENT, 0, function(fs) {
        fs.root.getFile(filename, {}, function(fileEntry) {
            fileEntry.remove(function() {
                console.log('文件删除成功');
                alert('文件删除成功');
            }, function(error) {
                console.error('文件删除失败:', error);
                alert('文件删除失败');
            });
        });
    });
}

// 创建目录
function createDirectory(dirname) {
    window.requestFileSystem(LocalFileSystem.PERSISTENT, 0, function(fs) {
        fs.root.getDirectory(dirname, {create: true}, function(dirEntry) {
            console.log('目录创建成功:', dirEntry.fullPath);
            alert('目录创建成功');
        }, function(error) {
            console.error('目录创建失败:', error);
            alert('目录创建失败');
        });
    });
}
```

## 五、项目实战案例

### 5.1 项目一：适老居家生活辅助系统

#### 5.1.1 项目概述
开发一个面向老年人的混合应用，包含健康监测、紧急呼叫、家属关联等功能。

#### 5.1.2 核心功能实现

**紧急呼叫功能**
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>紧急呼叫</title>
    <link rel="stylesheet" href="css/emergency.css">
</head>
<body>
    <div class="emergency-container">
        <h1>紧急呼叫</h1>
        
        <div class="emergency-button" id="emergencyBtn">
            <div class="button-icon">📞</div>
            <div class="button-text">紧急呼叫</div>
        </div>
        
        <div class="countdown" id="countdown" style="display: none;">
            <div class="countdown-number" id="countdownNumber">3</div>
            <div class="countdown-text">秒后拨打</div>
        </div>
        
        <div class="contact-setting">
            <label for="emergencyContact">紧急联系人</label>
            <input type="tel" id="emergencyContact" value="110" placeholder="请输入电话号码">
        </div>
    </div>
    
    <script type="text/javascript" src="cordova.js"></script>
    <script type="text/javascript" src="js/emergency.js"></script>
</body>
</html>
```

```javascript
// js/emergency.js
document.addEventListener('deviceready', function() {
    const emergencyBtn = document.getElementById('emergencyBtn');
    emergencyBtn.addEventListener('click', startCountdown);
    
    // 加载保存的联系人
    loadEmergencyContact();
});

let countdown = 0;
let countdownInterval = null;

function loadEmergencyContact() {
    const savedContact = localStorage.getItem('emergencyContact');
    if (savedContact) {
        document.getElementById('emergencyContact').value = savedContact;
    }
}

function saveEmergencyContact() {
    const contact = document.getElementById('emergencyContact').value;
    localStorage.setItem('emergencyContact', contact);
}

function startCountdown() {
    if (countdown > 0) return;
    
    const contact = document.getElementById('emergencyContact').value;
    if (!contact) {
        alert('请先设置紧急联系人');
        return;
    }
    
    saveEmergencyContact();
    countdown = 3;
    
    const countdownDiv = document.getElementById('countdown');
    const countdownNumber = document.getElementById('countdownNumber');
    
    countdownDiv.style.display = 'block';
    countdownNumber.textContent = countdown;
    
    // 播放提示音
    playAlertSound();
    
    countdownInterval = setInterval(function() {
        countdown--;
        countdownNumber.textContent = countdown;
        
        if (countdown <= 0) {
            clearInterval(countdownInterval);
            makeEmergencyCall(contact);
            resetCountdown();
        }
    }, 1000);
}

function resetCountdown() {
    countdown = 0;
    document.getElementById('countdown').style.display = 'none';
}

function makeEmergencyCall(phoneNumber) {
    window.plugins.CallNumber.callNumber(
        function(success) {
            console.log('拨打电话成功');
        },
        function(error) {
            console.error('拨打电话失败:', error);
            alert('拨打电话失败，请手动拨打');
        },
        phoneNumber,
        true
    );
}

function playAlertSound() {
    const media = new Media('file:///android_asset/www/sounds/alert.mp3');
    media.play();
}
```

```css
/* css/emergency.css */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background-color: #f5f5f5;
    min-height: 100vh;
}

.emergency-container {
    max-width: 600px;
    margin: 0 auto;
    padding: 30px 20px;
    text-align: center;
}

h1 {
    color: #2c3e50;
    margin-bottom: 40px;
    font-size: 28px;
}

.emergency-button {
    width: 200px;
    height: 200px;
    margin: 0 auto 40px;
    background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
    border-radius: 50%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    box-shadow: 0 10px 30px rgba(231, 76, 60, 0.4);
    transition: transform 0.2s, box-shadow 0.2s;
}

.emergency-button:active {
    transform: scale(0.95);
    box-shadow: 0 5px 15px rgba(231, 76, 60, 0.4);
}

.button-icon {
    font-size: 60px;
    margin-bottom: 10px;
}

.button-text {
    color: white;
    font-size: 20px;
    font-weight: bold;
}

.countdown {
    margin-bottom: 40px;
}

.countdown-number {
    font-size: 72px;
    font-weight: bold;
    color: #e74c3c;
    margin-bottom: 10px;
}

.countdown-text {
    font-size: 18px;
    color: #7f8c8d;
}

.contact-setting {
    text-align: left;
}

.contact-setting label {
    display: block;
    margin-bottom: 10px;
    font-size: 16px;
    color: #34495e;
    font-weight: 500;
}

.contact-setting input {
    width: 100%;
    padding: 15px;
    border: 2px solid #bdc3c7;
    border-radius: 8px;
    font-size: 16px;
    transition: border-color 0.3s;
}

.contact-setting input:focus {
    outline: none;
    border-color: #3498db;
}
```

**健康监测数据展示**
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>健康监测</title>
    <link rel="stylesheet" href="css/health.css">
</head>
<body>
    <div class="health-container">
        <h1>健康监测</h1>
        
        <div class="health-cards">
            <div class="health-card" id="heartRateCard">
                <div class="card-icon">❤️</div>
                <div class="card-info">
                    <div class="card-title">心率</div>
                    <div class="card-value" id="heartRateValue">75 bpm</div>
                </div>
            </div>
            
            <div class="health-card" id="bloodPressureCard">
                <div class="card-icon">🩺</div>
                <div class="card-info">
                    <div class="card-title">血压</div>
                    <div class="card-value" id="bloodPressureValue">120/80 mmHg</div>
                </div>
            </div>
            
            <div class="health-card" id="bloodSugarCard">
                <div class="card-icon">🩸</div>
                <div class="card-info">
                    <div class="card-title">血糖</div>
                    <div class="card-value" id="bloodSugarValue">5.6 mmol/L</div>
                </div>
            </div>
            
            <div class="health-card" id="temperatureCard">
                <div class="card-icon">🌡️</div>
                <div class="card-info">
                    <div class="card-title">体温</div>
                    <div class="card-value" id="temperatureValue">36.5 °C</div>
                </div>
            </div>
        </div>
        
        <button class="refresh-button" id="refreshBtn">刷新数据</button>
    </div>
    
    <script type="text/javascript" src="cordova.js"></script>
    <script type="text/javascript" src="js/health.js"></script>
</body>
</html>
```

```javascript
// js/health.js
document.addEventListener('deviceready', function() {
    loadHealthData();
    
    document.getElementById('refreshBtn').addEventListener('click', function() {
        loadHealthData();
    });
});

function loadHealthData() {
    // 模拟从服务器加载健康数据
    fetch('https://api.example.com/health/data', {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json'
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.code === 200) {
            updateHealthData(data.data);
        }
    })
    .catch(error => {
        console.error('加载健康数据失败:', error);
        // 使用模拟数据
        const mockData = {
            heartRate: Math.floor(Math.random() * 30) + 60,
            bloodPressure: `${Math.floor(Math.random() * 30) + 110}/${Math.floor(Math.random() * 20) + 70}`,
            bloodSugar: (Math.random() * 2 + 4).toFixed(1),
            temperature: (Math.random() * 1 + 36).toFixed(1)
        };
        updateHealthData(mockData);
    });
}

function updateHealthData(data) {
    document.getElementById('heartRateValue').textContent = `${data.heartRate} bpm`;
    document.getElementById('bloodPressureValue').textContent = `${data.bloodPressure} mmHg`;
    document.getElementById('bloodSugarValue').textContent = `${data.bloodSugar} mmol/L`;
    document.getElementById('temperatureValue').textContent = `${data.temperature} °C`;
    
    // 保存到本地存储
    localStorage.setItem('healthData', JSON.stringify(data));
    localStorage.setItem('healthDataTime', Date.now());
}
```

```css
/* css/health.css */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background-color: #f5f5f5;
    min-height: 100vh;
}

.health-container {
    max-width: 600px;
    margin: 0 auto;
    padding: 30px 20px;
}

h1 {
    text-align: center;
    color: #2c3e50;
    margin-bottom: 30px;
    font-size: 28px;
}

.health-cards {
    display: grid;
    grid-template-columns: 1fr;
    gap: 20px;
    margin-bottom: 30px;
}

.health-card {
    background-color: white;
    border-radius: 16px;
    padding: 20px;
    display: flex;
    align-items: center;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.08);
    transition: transform 0.2s, box-shadow 0.2s;
}

.health-card:active {
    transform: scale(0.98);
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.08);
}

.card-icon {
    font-size: 48px;
    margin-right: 20px;
}

.card-info {
    flex: 1;
}

.card-title {
    font-size: 16px;
    color: #7f8c8d;
    margin-bottom: 8px;
}

.card-value {
    font-size: 24px;
    font-weight: bold;
    color: #2c3e50;
}

.refresh-button {
    width: 100%;
    padding: 15px;
    background-color: #3498db;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 500;
    cursor: pointer;
    transition: background-color 0.3s;
}

.refresh-button:active {
    background-color: #2980b9;
}

@media (min-width: 768px) {
    .health-cards {
        grid-template-columns: repeat(2, 1fr);
    }
}
```

## 六、测试与调试

### 6.1 单元测试

```javascript
// tests/unit/emergency.spec.js
describe('紧急呼叫功能', function() {
    beforeEach(function() {
        // 每个测试前的准备工作
        document.body.innerHTML = `
            <input type="tel" id="emergencyContact" value="110">
        `;
    });
    
    it('应该能够保存紧急联系人', function() {
        const contact = '120';
        document.getElementById('emergencyContact').value = contact;
        saveEmergencyContact();
        
        expect(localStorage.getItem('emergencyContact')).toBe(contact);
    });
    
    it('应该能够加载保存的联系人', function() {
        const contact = '119';
        localStorage.setItem('emergencyContact', contact);
        loadEmergencyContact();
        
        expect(document.getElementById('emergencyContact').value).toBe(contact);
    });
});
```

### 6.2 E2E测试

```javascript
// tests/e2e/emergency.spec.js
describe('紧急呼叫E2E测试', function() {
    it('应该能够启动倒计时', function() {
        browser.get('/emergency.html');
        
        const emergencyBtn = element(by.id('emergencyBtn'));
        emergencyBtn.click();
        
        const countdownDiv = element(by.id('countdown'));
        expect(countdownDiv.isDisplayed()).toBe(true);
    });
    
    it('应该能够拨打紧急电话', function() {
        browser.get('/emergency.html');
        
        const contactInput = element(by.id('emergencyContact'));
        contactInput.sendKeys('110');
        
        const emergencyBtn = element(by.id('emergencyBtn'));
        emergencyBtn.click();
        
        // 等待倒计时结束
        browser.sleep(4000);
        
        // 验证是否调用了拨号功能
        expect(browser.getCurrentUrl()).toContain('tel:');
    });
});
```

## 七、性能优化

### 7.1 图片优化

```javascript
// 图片懒加载
function lazyLoadImages() {
    const images = document.querySelectorAll('img[data-src]');
    
    const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const img = entry.target;
                img.src = img.dataset.src;
                img.removeAttribute('data-src');
                observer.unobserve(img);
            }
        });
    });
    
    images.forEach(img => {
        imageObserver.observe(img);
    });
}

// 图片压缩
function compressImage(imageURI, quality = 0.7) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = function() {
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            
            canvas.width = img.width * quality;
            canvas.height = img.height * quality;
            
            ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
            
            resolve(canvas.toDataURL('image/jpeg', quality));
        };
        
        img.onerror = reject;
        img.src = imageURI;
    });
}
```

### 7.2 缓存优化

```javascript
// 使用LocalStorage缓存数据
function cacheData(key, data, expiry = 3600000) {
    const cacheItem = {
        data: data,
        timestamp: Date.now(),
        expiry: expiry
    };
    
    localStorage.setItem(key, JSON.stringify(cacheItem));
}

function getCachedData(key) {
    const cachedItem = localStorage.getItem(key);
    
    if (!cachedItem) {
        return null;
    }
    
    const parsedItem = JSON.parse(cachedItem);
    const now = Date.now();
    
    if (now - parsedItem.timestamp > parsedItem.expiry) {
        localStorage.removeItem(key);
        return null;
    }
    
    return parsedItem.data;
}

// 使用IndexedDB存储大量数据
const dbName = 'MyAppDB';
const storeName = 'healthData';

function openDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(dbName, 1);
        
        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve(request.result);
        
        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            if (!db.objectStoreNames.contains(storeName)) {
                db.createObjectStore(storeName, { keyPath: 'id', autoIncrement: true });
            }
        };
    });
}

function addHealthData(data) {
    return openDB().then(db => {
        return new Promise((resolve, reject) => {
            const transaction = db.transaction([storeName], 'readwrite');
            const store = transaction.objectStore(storeName);
            const request = store.add(data);
            
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    });
}
```

## 八、发布与部署

### 8.1 Android发布

```bash
# 构建Android APK
cordova build android --release

# 签名APK
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore my-release-key.keystore platforms/android/app/build/outputs/apk/release/app-release-unsigned.apk alias_name

# 对齐APK
zipalign -v 4 app-release-unsigned.apk app-release.apk
```

### 8.2 iOS发布

```bash
# 构建iOS应用
cordova build ios --release

# 使用Xcode打开项目
open platforms/ios/MyApp.xcworkspace

# 在Xcode中进行签名和打包
```

### 8.3 Web发布

```bash
# 构建Web版本
cordova build browser

# 部署到Web服务器
# 将platforms/browser/www目录下的文件上传到服务器
```

## 九、常见问题与解决方案

### 9.1 跨平台兼容性
**问题**：不同平台API不一致

**解决方案**：
```javascript
// 检测平台
function getPlatform() {
    if (device.platform === 'Android') {
        return 'android';
    } else if (device.platform === 'iOS') {
        return 'ios';
    } else {
        return 'browser';
    }
}

// 平台特定代码
function platformSpecificFunction() {
    const platform = getPlatform();
    
    if (platform === 'android') {
        // Android特定代码
    } else if (platform === 'ios') {
        // iOS特定代码
    } else {
        // 浏览器特定代码
    }
}
```

### 9.2 权限问题
**问题**：应用权限被拒绝

**解决方案**：
```javascript
// 请求权限
function requestPermission(permissionType) {
    return new Promise((resolve, reject) => {
        const permissions = cordova.plugins.permissions;
        
        permissions.checkPermission(permissionType, function(status) {
            if (status.hasPermission) {
                resolve(true);
            } else {
                permissions.requestPermission(permissionType, function(status) {
                    if (status.hasPermission) {
                        resolve(true);
                    } else {
                        reject(new Error('权限被拒绝'));
                    }
                }, function(error) {
                    reject(error);
                });
            }
        });
    });
}

// 使用示例
async function requestCameraPermission() {
    try {
        await requestPermission(cordova.plugins.permissions.CAMERA);
        console.log('相机权限已授予');
    } catch (error) {
        console.error('相机权限被拒绝:', error);
        alert('需要相机权限才能使用此功能');
    }
}
```

## 十、学习资源

### 10.1 官方文档
- Cordova官方文档：https://cordova.apache.org/docs/en/latest/
- Cordova插件API：https://cordova.apache.org/docs/en/latest/reference/cordova-plugin-geolocation/
- Cordova CLI文档：https://cordova.apache.org/docs/en/latest/reference/cordova-cli/

### 10.2 推荐书籍
- 《Apache Cordova实战》
- 《HTML5移动应用开发》
- 《JavaScript高级程序设计》

### 10.3 在线课程
- Cordova官方教程
- HTML5移动开发课程
- JavaScript高级教程

## 十一、实验项目要求

### 11.1 基础要求
1. 使用HTML5 + CSS3 + JavaScript开发
2. 采用Cordova框架
3. 实现跨平台适配（Android、iOS、Web）
4. 集成常用Cordova插件
5. 实现组件化开发
6. 添加单元测试和E2E测试

### 11.2 进阶要求
1. 实现自定义Cordova插件
2. 集成第三方SDK（如支付宝、微信支付）
3. 优化应用性能和加载速度
4. 实现离线功能
5. 添加推送通知功能
6. 实现数据同步功能

### 11.3 提交要求
1. 完整的项目源代码
2. 详细的README文档
3. Android APK和iOS IPA安装包
4. 测试报告
5. 技术文档和架构设计图