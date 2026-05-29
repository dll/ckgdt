# 实验四：微信小程序开发

## 实验项目基本信息

- **实验编号**：d20301035104、d20301009204
- **学时分配**：4学时
- **实验类型**：验证型
- **每组人数**：6人
- **对应课程目标**：课程目标2

## 🎯 核心步骤列表

### 📋 实验概览
1. **需求分析阶段**：绘制小程序页面流程图与数据模型
2. **AI辅助编码阶段**：使用TRAE生成小程序页面代码与数据绑定逻辑
3. **测试验证阶段**：使用微信开发者工具进行真机预览与功能测试
4. **部署运维阶段**：体验小程序审核与发布流程（体验版）

### 🏗️ 开发任务清单
| 任务阶段 | 主要内容 | 关键技术点 |
|----------|----------|------------|
| 通知列表 | 列表展示 | WXML、wx:for |
| 详情页 | 内容展示 | 页面路由、参数传递 |
| 本地存储 | 数据持久化 | wx.setStorage |
| AI辅助 | 代码生成 | TRAE使用 |

### ✅ 成功标准
- [ ] 通知列表页面功能完整
- [ ] 详情页跳转正常
- [ ] 数据本地存储功能正常
- [ ] AI辅助开发体验良好
- [ ] 小程序可预览

---

## 实验任务与案例

### 核心任务
借助AI编程工具辅助开发通知小程序（列表 + 详情页路由 + 本地存储），体验AI工具在代码生成与调试中的作用，完成一个可预览的"智慧校园通知"小程序。

### 实战案例
开发"智慧校园通知"小程序，展示校园通知列表，点击进入详情页，支持已读状态本地存储，体验小程序完整开发流程。

---

## 第一课时：小程序基础与列表开发（2学时）

### 4.1 需求分析阶段

#### 步骤1：绘制页面流程图
```
首页(通知列表) → 详情页(通知详情)
     ↓
  本地存储(已读状态)
```

#### 步骤2：定义数据模型
```javascript
// 通知数据结构
{
  id: 1,
  title: "关于期末考试安排的通知",
  content: "详细内容...",
  author: "教务处",
  time: "2024-01-01",
  isRead: false
}
```

### 4.2 创建小程序项目

#### 步骤1：新建项目
1. 打开微信开发者工具
2. 新建小程序项目
3. 填写AppID（如无则使用测试号）
4. 选择JavaScript模板

### 4.3 AI辅助编码

#### 步骤1：生成列表页代码
1. 使用TRAE描述需求：微信小程序通知列表页面，WXML列表渲染，点击跳转详情页
2. AI生成代码片段
3. 手动完善

#### 步骤2：实现通知列表页面
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
    // 模拟数据
    const newsList = [
      { id: 1, title: "关于期末考试安排的通知", content: "详细内容...", author: "教务处", time: "2024-01-01", isRead: false },
      { id: 2, title: "图书馆开放时间调整", content: "详细内容...", author: "图书馆", time: "2024-01-02", isRead: false },
      { id: 3, title: "校园网络维护通知", content: "详细内容...", author: "信息中心", time: "2024-01-03", isRead: false }
    ];
    
    // 读取本地存储的已读状态
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

### 4.4 配置文件

```json
// pages/index/index.json
{
  "navigationBarTitleText": "智慧校园通知",
  "enablePullDownRefresh": true,
  "usingComponents": {}
}
```

---

## 第二课时：详情页、存储与发布（2学时）

### 4.5 详情页开发

#### 步骤1：AI辅助生成详情页
1. 使用TRAE描述需求：微信小程序通知详情页，接收参数显示内容
2. 生成代码片段

#### 步骤2：实现详情页
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
    // 模拟数据
    const allNews = [
      { id: 1, title: "关于期末考试安排的通知", content: "本次期末考试安排如下...", author: "教务处", time: "2024-01-01" },
      { id: 2, title: "图书馆开放时间调整", content: "图书馆开放时间调整...", author: "图书馆", time: "2024-01-02" },
      { id: 3, title: "校园网络维护通知", content: "网络维护通知...", author: "信息中心", time: "2024-01-03" }
    ];
    
    const news = allNews.find(n => n.id === id);
    this.setData({ news });
    
    // 标记为已读
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

### 4.6 本地存储

#### 步骤1：实现已读状态存储
```javascript
// 保存已读ID
wx.setStorageSync('readIds', [1, 2, 3]);

// 读取已读ID
const readIds = wx.getStorageSync('readIds');

// 检查是否已读
const isRead = readIds.includes(newsId);
```

### 4.7 测试验证

#### 步骤1：真机预览
1. 编译项目
2. 扫描二维码预览
3. 测试各项功能

#### 步骤2：功能测试
1. 列表展示测试
2. 跳转测试
3. 存储测试

### 4.8 部署运维

#### 步骤1：体验版发布
1. 点击上传
2. 填写版本信息
3. 获取体验版二维码

#### 步骤2：审核发布流程了解
1. 了解审核要求
2. 准备发布材料
3. 体验完整流程

---

## 总结与思考

### 实验总结
- 掌握微信小程序开发流程
- 学会WXML/WXSS/JS开发
- 理解页面路由与数据传递
- 掌握本地存储使用
- 体验AI辅助开发

### 课后思考
1. 小程序相比原生App的优势
2. 如何利用AI工具提升开发效率
3. 小程序在校园场景的创新应用
