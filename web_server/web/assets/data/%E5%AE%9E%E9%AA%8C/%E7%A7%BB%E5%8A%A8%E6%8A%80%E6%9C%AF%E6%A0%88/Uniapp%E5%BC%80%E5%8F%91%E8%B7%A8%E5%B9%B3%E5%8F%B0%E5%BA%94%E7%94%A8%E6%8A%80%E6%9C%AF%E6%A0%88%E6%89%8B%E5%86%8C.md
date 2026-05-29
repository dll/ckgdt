# Uniapp开发跨平台应用技术栈手册

## 一、技术栈概述

### 1.1 核心技术
- **编程语言**：JavaScript / TypeScript
- **开发框架**：Uniapp（基于Vue.js）
- **UI框架**：uView UI / uni-ui
- **构建工具**：HBuilderX / Vue CLI
- **版本要求**：Vue 3+, Uniapp 3.0+

### 1.2 依赖管理
- **包管理**：npm / yarn
- **依赖仓库**：npm官方仓库
- **版本控制**：Git

### 1.3 测试框架
- **单元测试**：Jest
- **E2E测试**：Cypress
- **组件测试**：@vue/test-utils

## 二、环境搭建

### 2.1 开发环境配置

```javascript
// package.json
{
  "name": "uniapp-project",
  "version": "1.0.0",
  "description": "Uniapp跨平台应用",
  "main": "main.js",
  "scripts": {
    "dev:h5": "uni -p h5",
    "dev:mp-weixin": "uni -p mp-weixin",
    "dev:app": "uni -p app",
    "build:h5": "uni build -p h5",
    "build:mp-weixin": "uni build -p mp-weixin",
    "build:app": "uni build -p app"
  },
  "dependencies": {
    "@dcloudio/uni-app": "^3.0.0",
    "@dcloudio/uni-h5": "^3.0.0",
    "@dcloudio/uni-mp-weixin": "^3.0.0",
    "vue": "^3.3.0",
    "pinia": "^2.1.0"
  },
  "devDependencies": {
    "@dcloudio/types": "^3.3.0",
    "@dcloudio/uni-automator": "^3.0.0",
    "@dcloudio/uni-cli-shared": "^3.0.0",
    "sass": "^1.69.0",
    "typescript": "^5.2.0"
  }
}
```

### 2.2 依赖配置

```javascript
// 安装依赖
npm install

// 安装UI组件库
npm install uview-ui

// 安装网络请求库
npm install @dcloudio/uni-axios

// 安装状态管理库
npm install pinia
```

## 三、基础语法与特性

### 3.1 Vue 3基础语法

#### 3.1.1 响应式数据

```javascript
// setup语法糖
<script setup>
import { ref, reactive, computed } from 'vue'

// ref：基本类型响应式
const count = ref(0)

// reactive：对象类型响应式
const user = reactive({
  name: '张三',
  age: 25,
  email: 'zhangsan@example.com'
})

// computed：计算属性
const isAdult = computed(() => user.age >= 18)

// 方法
function increment() {
  count.value++
}

function updateName(newName) {
  user.name = newName
}
</script>

<template>
  <view>
    <text>计数：{{ count }}</text>
    <button @click="increment">增加</button>
    
    <text>姓名：{{ user.name }}</text>
    <text>年龄：{{ user.age }}</text>
    <text v-if="isAdult">成年人</text>
  </view>
</template>
```

#### 3.1.2 生命周期

```javascript
<script setup>
import { onMounted, onUnmounted, onShow, onHide } from '@dcloudio/uni-app'

// 页面加载完成
onMounted(() => {
  console.log('页面加载完成')
  loadData()
})

// 页面显示
onShow(() => {
  console.log('页面显示')
})

// 页面隐藏
onHide(() => {
  console.log('页面隐藏')
})

// 页面卸载
onUnmounted(() => {
  console.log('页面卸载')
})

// 加载数据
async function loadData() {
  try {
    const data = await fetchData()
    console.log('数据加载成功', data)
  } catch (error) {
    console.error('数据加载失败', error)
  }
}
</script>
```

#### 3.1.3 组件通信

```javascript
// 父组件
<template>
  <view>
    <ChildComponent 
      :title="parentTitle" 
      :count="parentCount"
      @update="handleUpdate"
    />
  </view>
</template>

<script setup>
import { ref } from 'vue'
import ChildComponent from './ChildComponent.vue'

const parentTitle = ref('父组件标题')
const parentCount = ref(0)

function handleUpdate(newValue) {
  parentCount.value = newValue
}
</script>

// 子组件
<template>
  <view>
    <text>{{ title }}</text>
    <text>{{ count }}</text>
    <button @click="increment">增加</button>
  </view>
</template>

<script setup>
import { ref } from 'vue'

const props = defineProps({
  title: {
    type: String,
    default: ''
  },
  count: {
    type: Number,
    default: 0
  }
})

const emit = defineEmits(['update'])

function increment() {
  emit('update', props.count + 1)
}
</script>
```

### 3.2 Uniapp特性

#### 3.2.1 条件编译

```javascript
// #ifdef H5
// H5平台特有代码
console.log('这是H5平台')
// #endif

// #ifdef MP-WEIXIN
// 微信小程序特有代码
console.log('这是微信小程序')
// #endif

// #ifdef APP-PLUS
// App特有代码
console.log('这是App')
// #endif

// #ifndef H5
// 非H5平台代码
console.log('这不是H5平台')
// #endif
```

#### 3.2.2 API调用

```javascript
// 网络请求
function fetchData() {
  return new Promise((resolve, reject) => {
    uni.request({
      url: 'https://api.example.com/data',
      method: 'GET',
      success: (res) => {
        resolve(res.data)
      },
      fail: (err) => {
        reject(err)
      }
    })
  })
}

// 本地存储
function saveData(key, value) {
  uni.setStorageSync(key, value)
}

function getData(key) {
  return uni.getStorageSync(key)
}

// 页面跳转
function navigateTo(url) {
  uni.navigateTo({
    url: url
  })
}

function redirectTo(url) {
  uni.redirectTo({
    url: url
  })
}

// 消息提示
function showToast(title, icon = 'none') {
  uni.showToast({
    title: title,
    icon: icon,
    duration: 2000
  })
}

// 加载提示
function showLoading(title = '加载中...') {
  uni.showLoading({
    title: title
  })
}

function hideLoading() {
  uni.hideLoading()
}

// 模态框
function showModal(title, content) {
  return new Promise((resolve) => {
    uni.showModal({
      title: title,
      content: content,
      success: (res) => {
        resolve(res.confirm)
      }
    })
  })
}
```

## 四、组件开发

### 4.1 基础组件

#### 4.1.1 视图容器

```vue
<template>
  <view class="container">
    <!-- view：基础容器 -->
    <view class="box">
      <text>这是一个view容器</text>
    </view>
    
    <!-- scroll-view：可滚动容器 -->
    <scroll-view 
      class="scroll-box" 
      scroll-y 
      @scrolltolower="loadMore"
    >
      <view v-for="item in items" :key="item.id" class="item">
        {{ item.name }}
      </view>
    </scroll-view>
    
    <!-- swiper：轮播图 -->
    <swiper class="swiper" :indicator-dots="true" :autoplay="true">
      <swiper-item v-for="(image, index) in images" :key="index">
        <image :src="image" mode="aspectFill" />
      </swiper-item>
    </swiper>
  </view>
</template>

<script setup>
import { ref } from 'vue'

const items = ref([
  { id: 1, name: '项目1' },
  { id: 2, name: '项目2' },
  { id: 3, name: '项目3' }
])

const images = ref([
  'https://example.com/image1.jpg',
  'https://example.com/image2.jpg',
  'https://example.com/image3.jpg'
])

function loadMore() {
  console.log('加载更多')
}
</script>

<style scoped>
.container {
  padding: 20rpx;
}

.box {
  width: 100%;
  height: 200rpx;
  background-color: #f0f0f0;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 20rpx;
}

.scroll-box {
  height: 400rpx;
  background-color: #ffffff;
}

.item {
  height: 100rpx;
  line-height: 100rpx;
  padding: 0 20rpx;
  border-bottom: 1rpx solid #f0f0f0;
}

.swiper {
  height: 400rpx;
  margin-top: 20rpx;
}

.swiper image {
  width: 100%;
  height: 100%;
}
</style>
```

#### 4.1.2 表单组件

```vue
<template>
  <view class="form-container">
    <!-- input：输入框 -->
    <view class="form-item">
      <text class="label">用户名</text>
      <input 
        v-model="formData.username" 
        placeholder="请输入用户名"
        class="input"
      />
    </view>
    
    <!-- textarea：多行输入 -->
    <view class="form-item">
      <text class="label">描述</text>
      <textarea 
        v-model="formData.description" 
        placeholder="请输入描述"
        class="textarea"
      />
    </view>
    
    <!-- radio：单选框 -->
    <view class="form-item">
      <text class="label">性别</text>
      <radio-group @change="handleGenderChange">
        <label v-for="item in genders" :key="item.value">
          <radio :value="item.value" :checked="formData.gender === item.value" />
          <text>{{ item.label }}</text>
        </label>
      </radio-group>
    </view>
    
    <!-- checkbox：复选框 -->
    <view class="form-item">
      <text class="label">爱好</text>
      <checkbox-group @change="handleHobbyChange">
        <label v-for="item in hobbies" :key="item.value">
          <checkbox :value="item.value" :checked="formData.hobbies.includes(item.value)" />
          <text>{{ item.label }}</text>
        </label>
      </checkbox-group>
    </view>
    
    <!-- picker：选择器 -->
    <view class="form-item">
      <text class="label">城市</text>
      <picker 
        :range="cities" 
        @change="handleCityChange"
      >
        <view class="picker">
          {{ formData.city || '请选择城市' }}
        </view>
      </picker>
    </view>
    
    <!-- button：按钮 -->
    <button type="primary" @click="submit">提交</button>
  </view>
</template>

<script setup>
import { reactive } from 'vue'

const formData = reactive({
  username: '',
  description: '',
  gender: 'male',
  hobbies: [],
  city: ''
})

const genders = [
  { label: '男', value: 'male' },
  { label: '女', value: 'female' }
]

const hobbies = [
  { label: '阅读', value: 'reading' },
  { label: '运动', value: 'sports' },
  { label: '音乐', value: 'music' }
]

const cities = ['北京', '上海', '广州', '深圳']

function handleGenderChange(e) {
  formData.gender = e.detail.value
}

function handleHobbyChange(e) {
  formData.hobbies = e.detail.value
}

function handleCityChange(e) {
  formData.city = cities[e.detail.value]
}

function submit() {
  console.log('表单数据', formData)
  uni.showToast({
    title: '提交成功',
    icon: 'success'
  })
}
</script>

<style scoped>
.form-container {
  padding: 30rpx;
}

.form-item {
  margin-bottom: 30rpx;
}

.label {
  display: block;
  margin-bottom: 10rpx;
  font-size: 28rpx;
  color: #333;
}

.input, .textarea {
  width: 100%;
  padding: 20rpx;
  border: 1rpx solid #e0e0e0;
  border-radius: 8rpx;
  font-size: 28rpx;
}

.textarea {
  height: 200rpx;
}

.picker {
  padding: 20rpx;
  border: 1rpx solid #e0e0e0;
  border-radius: 8rpx;
  font-size: 28rpx;
}
</style>
```

### 4.2 uView UI组件

```vue
<template>
  <view class="container">
    <!-- u-button：按钮 -->
    <u-button type="primary" @click="handleClick">主要按钮</u-button>
    <u-button type="success">成功按钮</u-button>
    <u-button type="warning">警告按钮</u-button>
    <u-button type="error">危险按钮</u-button>
    
    <!-- u-input：输入框 -->
    <u-input 
      v-model="inputValue" 
      placeholder="请输入内容"
      :border="true"
    />
    
    <!-- u-card：卡片 -->
    <u-card :title="'卡片标题'">
      <view class="card-content">
        这是卡片内容
      </view>
    </u-card>
    
    <!-- u-list：列表 -->
    <u-list>
      <u-list-item v-for="item in listData" :key="item.id">
        <view class="list-item">
          <text>{{ item.name }}</text>
        </view>
      </u-list-item>
    </u-list>
    
    <!-- u-popup：弹窗 -->
    <u-popup v-model="showPopup" mode="center">
      <view class="popup-content">
        <text>这是弹窗内容</text>
        <u-button @click="showPopup = false">关闭</u-button>
      </view>
    </u-popup>
    
    <!-- u-toast：提示 -->
    <u-toast ref="toast" />
  </view>
</template>

<script setup>
import { ref } from 'vue'

const inputValue = ref('')
const showPopup = ref(false)
const toast = ref(null)

const listData = ref([
  { id: 1, name: '列表项1' },
  { id: 2, name: '列表项2' },
  { id: 3, name: '列表项3' }
])

function handleClick() {
  toast.value.show({
    message: '按钮被点击',
    type: 'success'
  })
}
</script>

<style scoped>
.container {
  padding: 20rpx;
}

.card-content {
  padding: 20rpx;
}

.list-item {
  padding: 20rpx;
  border-bottom: 1rpx solid #f0f0f0;
}

.popup-content {
  padding: 40rpx;
  text-align: center;
}
</style>
```

## 五、状态管理

### 5.1 Pinia状态管理

```javascript
// stores/user.js
import { defineStore } from 'pinia'

export const useUserStore = defineStore('user', {
  state: () => ({
    userInfo: null,
    token: '',
    isLoggedIn: false
  }),
  
  getters: {
    userId: (state) => state.userInfo?.id,
    userName: (state) => state.userInfo?.name
  },
  
  actions: {
    async login(username, password) {
      try {
        const response = await uni.request({
          url: 'https://api.example.com/login',
          method: 'POST',
          data: { username, password }
        })
        
        if (response.data.code === 200) {
          this.token = response.data.data.token
          this.userInfo = response.data.data.user
          this.isLoggedIn = true
          
          // 保存token到本地
          uni.setStorageSync('token', this.token)
          
          return true
        }
        return false
      } catch (error) {
        console.error('登录失败', error)
        return false
      }
    },
    
    logout() {
      this.userInfo = null
      this.token = ''
      this.isLoggedIn = false
      uni.removeStorageSync('token')
    },
    
    async getUserInfo() {
      try {
        const response = await uni.request({
          url: 'https://api.example.com/user/info',
          method: 'GET',
          header: {
            'Authorization': `Bearer ${this.token}`
          }
        })
        
        if (response.data.code === 200) {
          this.userInfo = response.data.data
        }
      } catch (error) {
        console.error('获取用户信息失败', error)
      }
    }
  }
})
```

```javascript
// stores/index.js
import { createPinia } from 'pinia'

const pinia = createPinia()

export default pinia
```

```javascript
// main.js
import { createSSRApp } from 'vue'
import App from './App.vue'
import pinia from './stores'

export function createApp() {
  const app = createSSRApp(App)
  app.use(pinia)
  return {
    app
  }
}
```

```vue
// 在组件中使用
<template>
  <view>
    <text v-if="userStore.isLoggedIn">欢迎，{{ userStore.userName }}</text>
    <text v-else>请先登录</text>
    <button @click="handleLogin">登录</button>
    <button @click="handleLogout">退出</button>
  </view>
</template>

<script setup>
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()

async function handleLogin() {
  const success = await userStore.login('username', 'password')
  if (success) {
    uni.showToast({
      title: '登录成功',
      icon: 'success'
    })
  }
}

function handleLogout() {
  userStore.logout()
  uni.showToast({
    title: '退出成功',
    icon: 'success'
  })
}
</script>
```

## 六、项目实战案例

### 6.1 项目一：适老居家生活辅助系统

#### 6.1.1 项目概述
开发一个面向老年人的跨平台应用，包含健康监测、紧急呼叫、家属关联等功能。

#### 6.1.2 核心功能实现

**紧急呼叫功能**
```vue
<template>
  <view class="emergency-container">
    <!-- 紧急呼叫按钮 -->
    <view class="emergency-button" @click="startCountdown">
      <text class="button-text">紧急呼叫</text>
      <text class="button-icon">📞</text>
    </view>
    
    <!-- 倒计时显示 -->
    <view v-if="isCountingDown" class="countdown">
      <text class="countdown-text">{{ countdown }}秒后拨打</text>
    </view>
    
    <!-- 联系人设置 -->
    <view class="contact-setting">
      <text class="label">紧急联系人</text>
      <input 
        v-model="emergencyContact" 
        placeholder="请输入电话号码"
        class="input"
        type="number"
      />
    </view>
  </view>
</template>

<script setup>
import { ref, onUnmounted } from 'vue'

const emergencyContact = ref('110')
const countdown = ref(0)
const isCountingDown = ref(false)
let timer = null

function startCountdown() {
  if (isCountingDown.value) return
  
  isCountingDown.value = true
  countdown.value = 3
  
  timer = setInterval(() => {
    countdown.value--
    
    if (countdown.value <= 0) {
      makeEmergencyCall()
      stopCountdown()
    }
  }, 1000)
}

function stopCountdown() {
  isCountingDown.value = false
  countdown.value = 0
  if (timer) {
    clearInterval(timer)
    timer = null
  }
}

function makeEmergencyCall() {
  uni.makePhoneCall({
    phoneNumber: emergencyContact.value,
    success: () => {
      console.log('拨打电话成功')
    },
    fail: (err) => {
      console.error('拨打电话失败', err)
    }
  })
}

onUnmounted(() => {
  stopCountdown()
})
</script>

<style scoped>
.emergency-container {
  padding: 40rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.emergency-button {
  width: 400rpx;
  height: 400rpx;
  background: linear-gradient(135deg, #ff6b6b 0%, #ee5a5a 100%);
  border-radius: 50%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  box-shadow: 0 10rpx 30rpx rgba(255, 107, 107, 0.4);
}

.button-text {
  font-size: 48rpx;
  color: #ffffff;
  font-weight: bold;
  margin-bottom: 20rpx;
}

.button-icon {
  font-size: 80rpx;
}

.countdown {
  margin-top: 40rpx;
}

.countdown-text {
  font-size: 36rpx;
  color: #ff6b6b;
  font-weight: bold;
}

.contact-setting {
  width: 100%;
  margin-top: 60rpx;
}

.label {
  display: block;
  font-size: 32rpx;
  color: #333;
  margin-bottom: 20rpx;
}

.input {
  width: 100%;
  height: 80rpx;
  padding: 0 20rpx;
  border: 2rpx solid #e0e0e0;
  border-radius: 10rpx;
  font-size: 28rpx;
}
</style>
```

**健康监测数据展示**
```vue
<template>
  <view class="health-container">
    <!-- 心率卡片 -->
    <view class="health-card">
      <view class="card-icon" style="background-color: #ff6b6b;">
        <text class="icon">❤️</text>
      </view>
      <view class="card-info">
        <text class="card-title">心率</text>
        <text class="card-value">{{ healthData.heartRate }} bpm</text>
      </view>
    </view>
    
    <!-- 血压卡片 -->
    <view class="health-card">
      <view class="card-icon" style="background-color: #4a90e2;">
        <text class="icon">🩺</text>
      </view>
      <view class="card-info">
        <text class="card-title">血压</text>
        <text class="card-value">{{ healthData.bloodPressure }} mmHg</text>
      </view>
    </view>
    
    <!-- 血糖卡片 -->
    <view class="health-card">
      <view class="card-icon" style="background-color: #4caf50;">
        <text class="icon">🩸</text>
      </view>
      <view class="card-info">
        <text class="card-title">血糖</text>
        <text class="card-value">{{ healthData.bloodSugar }} mmol/L</text>
      </view>
    </view>
    
    <!-- 体温卡片 -->
    <view class="health-card">
      <view class="card-icon" style="background-color: #ff9800;">
        <text class="icon">🌡️</text>
      </view>
      <view class="card-info">
        <text class="card-title">体温</text>
        <text class="card-value">{{ healthData.temperature }} °C</text>
      </view>
    </view>
  </view>
</template>

<script setup>
import { ref, onMounted } from 'vue'

const healthData = ref({
  heartRate: 75,
  bloodPressure: '120/80',
  bloodSugar: 5.6,
  temperature: 36.5
})

onMounted(() => {
  loadHealthData()
})

function loadHealthData() {
  // 模拟从服务器加载健康数据
  uni.request({
    url: 'https://api.example.com/health/data',
    method: 'GET',
    success: (res) => {
      if (res.data.code === 200) {
        healthData.value = res.data.data
      }
    },
    fail: (err) => {
      console.error('加载健康数据失败', err)
    }
  })
}
</script>

<style scoped>
.health-container {
  padding: 30rpx;
}

.health-card {
  display: flex;
  align-items: center;
  background-color: #ffffff;
  border-radius: 20rpx;
  padding: 30rpx;
  margin-bottom: 20rpx;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.08);
}

.card-icon {
  width: 100rpx;
  height: 100rpx;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 30rpx;
}

.icon {
  font-size: 48rpx;
}

.card-info {
  flex: 1;
}

.card-title {
  display: block;
  font-size: 28rpx;
  color: #999;
  margin-bottom: 10rpx;
}

.card-value {
  display: block;
  font-size: 48rpx;
  font-weight: bold;
  color: #333;
}
</style>
```

#### 6.1.3 AI功能集成

**AI语音助手**
```vue
<template>
  <view class="voice-assistant-container">
    <!-- 语音识别结果 -->
    <view class="result-box">
      <text class="result-text">
        {{ recognizedText || '点击按钮开始语音识别' }}
      </text>
    </view>
    
    <!-- AI响应 -->
    <view v-if="aiResponse" class="response-box">
      <text class="response-title">AI助手：</text>
      <text class="response-text">{{ aiResponse }}</text>
    </view>
    
    <!-- 语音识别按钮 -->
    <view class="button-container">
      <button 
        :class="['voice-button', { listening: isListening }]"
        @click="toggleListening"
      >
        <text class="button-icon">🎤</text>
        <text class="button-text">{{ isListening ? '停止识别' : '开始识别' }}</text>
      </button>
    </view>
  </view>
</template>

<script setup>
import { ref } from 'vue'

const recognizedText = ref('')
const aiResponse = ref('')
const isListening = ref(false)

function toggleListening() {
  if (isListening.value) {
    stopListening()
  } else {
    startListening()
  }
}

function startListening() {
  isListening.value = true
  recognizedText.value = ''
  
  // #ifdef MP-WEIXIN
  // 微信小程序语音识别
  const recorderManager = uni.getRecorderManager()
  
  recorderManager.onStop((res) => {
    recognizedText.value = '语音识别结果'
    processWithAI(recognizedText.value)
  })
  
  recorderManager.start({
    format: 'mp3'
  })
  // #endif
  
  // #ifdef APP-PLUS
  // App语音识别
  const speechRecognizer = plus.speech.createRecognizer()
  
  speechRecognizer.onresult = (event) => {
    recognizedText.value = event.result
    processWithAI(recognizedText.value)
  }
  
  speechRecognizer.start()
  // #endif
}

function stopListening() {
  isListening.value = false
  
  // #ifdef MP-WEIXIN
  const recorderManager = uni.getRecorderManager()
  recorderManager.stop()
  // #endif
  
  // #ifdef APP-PLUS
  const speechRecognizer = plus.speech.createRecognizer()
  speechRecognizer.stop()
  // #endif
}

async function processWithAI(text) {
  try {
    const response = await uni.request({
      url: 'https://api.example.com/ai/process',
      method: 'POST',
      data: { text }
    })
    
    if (response.data.code === 200) {
      aiResponse.value = response.data.data.result
    }
  } catch (error) {
    console.error('AI处理失败', error)
    aiResponse.value = '抱歉，我没有理解您的指令'
  }
}
</script>

<style scoped>
.voice-assistant-container {
  padding: 40rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.result-box {
  width: 100%;
  min-height: 200rpx;
  background-color: #f5f5f5;
  border-radius: 20rpx;
  padding: 30rpx;
  margin-bottom: 30rpx;
}

.result-text {
  font-size: 32rpx;
  color: #333;
  line-height: 1.6;
}

.response-box {
  width: 100%;
  background-color: #e3f2fd;
  border-radius: 20rpx;
  padding: 30rpx;
  margin-bottom: 40rpx;
}

.response-title {
  display: block;
  font-size: 28rpx;
  color: #1976d2;
  margin-bottom: 10rpx;
  font-weight: bold;
}

.response-text {
  font-size: 32rpx;
  color: #333;
  line-height: 1.6;
}

.button-container {
  width: 100%;
  display: flex;
  justify-content: center;
}

.voice-button {
  width: 300rpx;
  height: 300rpx;
  border-radius: 50%;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: none;
  box-shadow: 0 10rpx 30rpx rgba(102, 126, 234, 0.4);
}

.voice-button.listening {
  background: linear-gradient(135deg, #ff6b6b 0%, #ee5a5a 100%);
  box-shadow: 0 10rpx 30rpx rgba(255, 107, 107, 0.4);
}

.button-icon {
  font-size: 80rpx;
  margin-bottom: 20rpx;
}

.button-text {
  font-size: 32rpx;
  color: #ffffff;
  font-weight: bold;
}
</style>
```

### 6.2 项目二：云端智能畜牧养殖管理系统

#### 6.2.1 项目概述
开发一个智能畜牧养殖管理跨平台应用，包含动物健康监测、疾病诊断、生长预测等功能。

#### 6.2.2 核心功能实现

**动物列表管理**
```vue
<template>
  <view class="livestock-container">
    <!-- 搜索框 -->
    <view class="search-box">
      <input 
        v-model="searchText" 
        placeholder="搜索牲畜"
        class="search-input"
      />
    </view>
    
    <!-- 牲畜列表 -->
    <scroll-view scroll-y class="livestock-list">
      <view 
        v-for="animal in filteredLivestock" 
        :key="animal.id" 
        class="livestock-item"
        @click="viewDetail(animal)"
      >
        <image :src="animal.imageUrl" class="animal-image" mode="aspectFill" />
        <view class="animal-info">
          <text class="animal-name">{{ animal.name }}</text>
          <view class="animal-details">
            <text class="detail-text">体重：{{ animal.weight }}kg</text>
            <text class="detail-text">年龄：{{ animal.age }}个月</text>
          </view>
          <view class="health-status" :style="{ backgroundColor: getHealthColor(animal.healthStatus) }">
            <text class="status-text">{{ animal.healthStatus }}</text>
          </view>
        </view>
      </view>
    </scroll-view>
    
    <!-- 添加按钮 -->
    <view class="add-button" @click="addLivestock">
      <text class="add-icon">+</text>
    </view>
  </view>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'

const searchText = ref('')
const livestockList = ref([])

const filteredLivestock = computed(() => {
  if (!searchText.value) {
    return livestockList.value
  }
  return livestockList.value.filter(item => 
    item.name.includes(searchText.value)
  )
})

onMounted(() => {
  loadLivestock()
})

function loadLivestock() {
  uni.request({
    url: 'https://api.example.com/livestock',
    method: 'GET',
    success: (res) => {
      if (res.data.code === 200) {
        livestockList.value = res.data.data
      }
    },
    fail: (err) => {
      console.error('加载牲畜列表失败', err)
    }
  })
}

function getHealthColor(status) {
  switch (status) {
    case '健康':
      return '#4caf50'
    case '生病':
      return '#ff5252'
    default:
      return '#ff9800'
  }
}

function viewDetail(animal) {
  uni.navigateTo({
    url: `/pages/livestock/detail?id=${animal.id}`
  })
}

function addLivestock() {
  uni.navigateTo({
    url: '/pages/livestock/add'
  })
}
</script>

<style scoped>
.livestock-container {
  height: 100vh;
  display: flex;
  flex-direction: column;
}

.search-box {
  padding: 20rpx;
  background-color: #ffffff;
}

.search-input {
  width: 100%;
  height: 70rpx;
  padding: 0 20rpx;
  background-color: #f5f5f5;
  border-radius: 35rpx;
  font-size: 28rpx;
}

.livestock-list {
  flex: 1;
  padding: 20rpx;
}

.livestock-item {
  display: flex;
  background-color: #ffffff;
  border-radius: 20rpx;
  padding: 20rpx;
  margin-bottom: 20rpx;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.08);
}

.animal-image {
  width: 150rpx;
  height: 150rpx;
  border-radius: 75rpx;
  margin-right: 20rpx;
}

.animal-info {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.animal-name {
  font-size: 32rpx;
  font-weight: bold;
  color: #333;
  margin-bottom: 10rpx;
}

.animal-details {
  display: flex;
  flex-direction: column;
  margin-bottom: 10rpx;
}

.detail-text {
  font-size: 26rpx;
  color: #666;
  margin-bottom: 5rpx;
}

.health-status {
  align-self: flex-start;
  padding: 8rpx 20rpx;
  border-radius: 20rpx;
}

.status-text {
  font-size: 24rpx;
  color: #ffffff;
}

.add-button {
  position: fixed;
  right: 40rpx;
  bottom: 40rpx;
  width: 120rpx;
  height: 120rpx;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  border-radius: 60rpx;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 10rpx 30rpx rgba(102, 126, 234, 0.4);
}

.add-icon {
  font-size: 60rpx;
  color: #ffffff;
  font-weight: bold;
}
</style>
```

#### 6.2.3 AI功能集成

**AI疾病诊断**
```vue
<template>
  <view class="diagnosis-container">
    <!-- 图片选择 -->
    <view class="image-section">
      <view v-if="selectedImage" class="selected-image">
        <image :src="selectedImage" mode="aspectFill" />
        <view class="remove-button" @click="removeImage">
          <text class="remove-icon">×</text>
        </view>
      </view>
      <view v-else class="upload-box" @click="chooseImage">
        <text class="upload-icon">📷</text>
        <text class="upload-text">点击上传图片</text>
      </view>
    </view>
    
    <!-- 诊断按钮 -->
    <button 
      :disabled="!selectedImage || isAnalyzing"
      class="diagnosis-button"
      @click="diagnose"
    >
      {{ isAnalyzing ? '分析中...' : '开始诊断' }}
    </button>
    
    <!-- 诊断结果 -->
    <view v-if="diagnosisResult" class="result-section">
      <view class="result-header">
        <text class="result-title">诊断结果</text>
      </view>
      <view class="result-content">
        <view class="result-item">
          <text class="item-label">疾病名称：</text>
          <text class="item-value disease-name">{{ diagnosisResult.diseaseName }}</text>
        </view>
        <view class="result-item">
          <text class="item-label">置信度：</text>
          <text class="item-value confidence">{{ (diagnosisResult.confidence * 100).toFixed(1) }}%</text>
        </view>
        <view class="result-item">
          <text class="item-label">严重程度：</text>
          <text class="item-value severity" :style="{ color: getSeverityColor(diagnosisResult.severity) }">
            {{ diagnosisResult.severity }}
          </text>
        </view>
        <view class="result-item treatment">
          <text class="item-label">治疗方案：</text>
          <text class="item-value">{{ diagnosisResult.treatment }}</text>
        </view>
      </view>
    </view>
  </view>
</template>

<script setup>
import { ref } from 'vue'

const selectedImage = ref('')
const isAnalyzing = ref(false)
const diagnosisResult = ref(null)

function chooseImage() {
  uni.chooseImage({
    count: 1,
    sizeType: ['compressed'],
    sourceType: ['album', 'camera'],
    success: (res) => {
      selectedImage.value = res.tempFilePaths[0]
    }
  })
}

function removeImage() {
  selectedImage.value = ''
  diagnosisResult.value = null
}

async function diagnose() {
  if (!selectedImage.value) return
  
  isAnalyzing.value = true
  
  try {
    // 上传图片
    const uploadRes = await uploadImage(selectedImage.value)
    
    // 调用AI诊断API
    const response = await uni.request({
      url: 'https://api.example.com/ai/diagnose',
      method: 'POST',
      data: { imageUrl: uploadRes.url }
    })
    
    if (response.data.code === 200) {
      diagnosisResult.value = response.data.data
    }
  } catch (error) {
    console.error('诊断失败', error)
    uni.showToast({
      title: '诊断失败，请重试',
      icon: 'none'
    })
  } finally {
    isAnalyzing.value = false
  }
}

function uploadImage(filePath) {
  return new Promise((resolve, reject) => {
    uni.uploadFile({
      url: 'https://api.example.com/upload',
      filePath: filePath,
      name: 'file',
      success: (res) => {
        const data = JSON.parse(res.data)
        if (data.code === 200) {
          resolve(data.data)
        } else {
          reject(new Error(data.message))
        }
      },
      fail: (err) => {
        reject(err)
      }
    })
  })
}

function getSeverityColor(severity) {
  switch (severity) {
    case '轻微':
      return '#4caf50'
    case '中等':
      return '#ff9800'
    case '严重':
      return '#ff5252'
    default:
      return '#ff9800'
  }
}
</script>

<style scoped>
.diagnosis-container {
  padding: 40rpx;
}

.image-section {
  margin-bottom: 40rpx;
}

.selected-image {
  position: relative;
  width: 100%;
  height: 500rpx;
  border-radius: 20rpx;
  overflow: hidden;
}

.selected-image image {
  width: 100%;
  height: 100%;
}

.remove-button {
  position: absolute;
  top: 20rpx;
  right: 20rpx;
  width: 60rpx;
  height: 60rpx;
  background-color: rgba(0, 0, 0, 0.6);
  border-radius: 30rpx;
  display: flex;
  align-items: center;
  justify-content: center;
}

.remove-icon {
  font-size: 40rpx;
  color: #ffffff;
  font-weight: bold;
}

.upload-box {
  width: 100%;
  height: 500rpx;
  border: 2rpx dashed #e0e0e0;
  border-radius: 20rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background-color: #f9f9f9;
}

.upload-icon {
  font-size: 100rpx;
  margin-bottom: 20rpx;
}

.upload-text {
  font-size: 28rpx;
  color: #999;
}

.diagnosis-button {
  width: 100%;
  height: 90rpx;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: #ffffff;
  font-size: 32rpx;
  border-radius: 45rpx;
  border: none;
  margin-bottom: 40rpx;
}

.diagnosis-button[disabled] {
  background: #e0e0e0;
  color: #999;
}

.result-section {
  background-color: #ffffff;
  border-radius: 20rpx;
  padding: 30rpx;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.08);
}

.result-header {
  margin-bottom: 20rpx;
  padding-bottom: 20rpx;
  border-bottom: 1rpx solid #f0f0f0;
}

.result-title {
  font-size: 36rpx;
  font-weight: bold;
  color: #333;
}

.result-item {
  display: flex;
  margin-bottom: 20rpx;
}

.item-label {
  font-size: 28rpx;
  color: #666;
  min-width: 150rpx;
}

.item-value {
  font-size: 28rpx;
  color: #333;
  flex: 1;
}

.disease-name {
  color: #ff5252;
  font-weight: bold;
}

.confidence {
  color: #4a90e2;
  font-weight: bold;
}

.treatment {
  flex-direction: column;
}

.treatment .item-value {
  margin-top: 10rpx;
  line-height: 1.6;
}
</style>
```

## 七、测试与调试

### 7.1 单元测试

```javascript
// tests/unit/user.spec.js
import { describe, it, expect } from 'vitest'
import { useUserStore } from '@/stores/user'

describe('User Store', () => {
  it('should login successfully', async () => {
    const store = useUserStore()
    const success = await store.login('username', 'password')
    expect(success).toBe(true)
    expect(store.isLoggedIn).toBe(true)
  })
  
  it('should logout successfully', () => {
    const store = useUserStore()
    store.logout()
    expect(store.isLoggedIn).toBe(false)
    expect(store.token).toBe('')
  })
})
```

### 7.2 E2E测试

```javascript
// tests/e2e/home.spec.js
import { test, expect } from '@playwright/test'

test('home page loads correctly', async ({ page }) => {
  await page.goto('/')
  
  await expect(page.locator('text=首页')).toBeVisible()
  await expect(page.locator('.emergency-button')).toBeVisible()
})

test('emergency button works', async ({ page }) => {
  await page.goto('/')
  
  await page.click('.emergency-button')
  await expect(page.locator('.countdown')).toBeVisible()
})
```

## 八、性能优化

### 8.1 图片优化

```javascript
// 使用图片懒加载
<image 
  :src="item.imageUrl" 
  mode="aspectFill" 
  lazy-load
  class="lazy-image"
/>

// 使用图片压缩
function compressImage(filePath) {
  return new Promise((resolve) => {
    uni.compressImage({
      src: filePath,
      quality: 80,
      success: (res) => {
        resolve(res.tempFilePath)
      }
    })
  })
}
```

### 8.2 列表优化

```vue
<!-- 使用虚拟列表 -->
<scroll-view scroll-y class="list">
  <view v-for="item in visibleItems" :key="item.id" class="item">
    {{ item.name }}
  </view>
</scroll-view>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'

const allItems = ref([])
const visibleItems = ref([])
let observer = null

onMounted(() => {
  loadItems()
  setupIntersectionObserver()
})

function loadItems() {
  // 加载所有数据
  allItems.value = Array.from({ length: 1000 }, (_, i) => ({
    id: i,
    name: `项目${i}`
  }))
  updateVisibleItems()
}

function setupIntersectionObserver() {
  // #ifdef APP-PLUS
  observer = uni.createIntersectionObserver()
  observer.observe('.list', (res) => {
    if (res.intersectionRatio > 0) {
      updateVisibleItems()
    }
  })
  // #endif
}

function updateVisibleItems() {
  // 只渲染可见区域的项
  const scrollTop = 0 // 获取滚动位置
  const visibleCount = 20 // 可见项数量
  const startIndex = Math.floor(scrollTop / 100)
  visibleItems.value = allItems.value.slice(startIndex, startIndex + visibleCount)
}

onUnmounted(() => {
  if (observer) {
    observer.disconnect()
  }
})
</script>
```

## 九、发布与部署

### 9.1 H5部署

```javascript
// 构建H5
npm run build:h5

// 部署到服务器
// 将dist/h5目录下的文件上传到Web服务器
```

### 9.2 小程序发布

```javascript
// 构建微信小程序
npm run build:mp-weixin

// 使用微信开发者工具打开dist/dev/mp-weixin目录
// 点击上传按钮发布小程序
```

### 9.3 App发布

```javascript
// 构建App
npm run build:app

// 使用HBuilderX云打包
// 或使用本地打包生成APK/IPA文件
```

## 十、常见问题与解决方案

### 10.1 跨平台兼容性
**问题**：不同平台API不一致

**解决方案**：
```javascript
// 使用条件编译处理平台差异
function getPlatformInfo() {
  // #ifdef H5
  return 'H5平台'
  // #endif
  
  // #ifdef MP-WEIXIN
  return '微信小程序'
  // #endif
  
  // #ifdef APP-PLUS
  return 'App平台'
  // #endif
}
```

### 10.2 性能问题
**问题**：列表渲染性能差

**解决方案**：
```vue
<!-- 使用key优化列表渲染 -->
<view v-for="item in items" :key="item.id">
  {{ item.name }}
</view>

<!-- 使用v-show替代v-if（频繁切换时） -->
<view v-show="isVisible">内容</view>
```

## 十一、学习资源

### 11.1 官方文档
- Uniapp官方文档：https://uniapp.dcloud.net.cn/
- Vue.js官方文档：https://cn.vuejs.org/
- Pinia官方文档：https://pinia.vuejs.org/zh/

### 11.2 推荐书籍
- 《Uniapp从入门到精通》
- 《Vue.js设计与实现》
- 《JavaScript高级程序设计》

### 11.3 在线课程
- Uniapp官方教程
- Vue.js官方教程
- DCloud开发者社区

## 十二、实验项目要求

### 12.1 基础要求
1. 使用Vue 3 + Uniapp开发
2. 采用Composition API
3. 实现跨平台适配（H5、小程序、App）
4. 集成Pinia状态管理
5. 实现组件化开发
6. 添加单元测试和E2E测试

### 12.2 进阶要求
1. 实现多端差异化功能
2. 集成AI功能（语音识别、图像识别等）
3. 优化应用性能和加载速度
4. 实现深色模式支持
5. 添加国际化支持
6. 实现无障碍功能

### 12.3 提交要求
1. 完整的项目源代码
2. 详细的README文档
2. H5、小程序、App安装包
4. 测试报告
5. 技术文档和架构设计图