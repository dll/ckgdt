
# codex exceeded retry limit, last status:429 完整解决方案
## 一、报错含义
`429 Too Many Requests` = 上游API/中转网关触发**速率限流**；
`exceeded retry limit` = codex 按内置策略自动重试多次后依然被限，达到最大重试次数直接终止任务。
两个核心诱因：
1. 短时间发请求太频繁（RPM 每分钟请求超限）
2. 单次prompt/输出token太大（TPM 每分钟token超限）
3. 共享中转IP/共享Key被多人挤爆（你之前Claude 502也是同类共享密钥问题）

## 二、立刻生效临时解决（按顺序操作）
### 1. 强制等待冷却（最快恢复）
停止所有codex操作，静置 **2～5分钟** 再重试；
如果是中转服务商限流，冷却时间可能长达10分钟。

### 2. 缩小任务、拆分请求（根治高频429）
不要一次性执行全局重构、全项目分析这种超大任务：
- 把大指令拆成单文件、单模块分步执行
- 减少上下文历史：重启codex会话清空旧对话
- 降低输出长度，指令里加`精简输出，控制token`

### 3. 关闭并发、串行执行
codex默认无并发控制，循环批量文件极易爆429；
批量脚本加sleep延时，示例：
```bash
# 每处理一个文件等待3秒
for f in src/*.go; do codex "优化$f" ; sleep 3; done
```

### 4. 切换网络/更换API密钥（共享网关专用）
你之前用OpenCode中转Claude出现过凭据禁用，同样共享网关极易429：
1. 断开VPN/代理，直连网络测试（共享IP是重灾区）
2. 登出旧密钥，切换**个人独立API Key**（不要共用中转Key）
```bash
# 清除旧Claude/OpenAI凭据
opencode auth logout anthropic
# 重新绑定自己独立Key
opencode auth login --provider anthropic
```

### 5. 交互式会话查看限流状态
进入codex交互界面，输入命令查看额度与重置时间：
```
/status
```
会显示剩余请求、token限额、多久重置窗口。

## 三、永久配置优化（修改codex全局配置 ~/.codex/config.toml）
### 1. 调低最大重试次数，加长重试间隔（避免疯狂重试加重限流）
```toml
[network]
timeout = 45
retries = 2          # 默认4，调低减少反复冲击API
retry_delay = 4      # 每次重试间隔4秒，指数退避
```

### 2. 限制并发请求，防止批量轰炸
```toml
[performance]
max_concurrent_requests = 1
```

### 3. 可选：关闭激进自动重试（彻底杜绝`exceeded retry limit`）
```toml
[retry]
request_max_retries = 0
```
设为0后触发429不会自动重试，直接提示你手动等待，不会耗尽重试次数报错退出。

## 四、命令行临时参数单次生效（不用改配置）
### 1. 单次执行加长延时、减少重试
```bash
codex --retries 2 --retry-delay 4 "优化当前模块"
```
### 2. 完全关闭自动重试，触发429直接停止
```bash
codex --retries 0 --full-auto "修复接口bug"
```

## 五、兜底方案（持续频繁429时）
1. **升级API账户额度**：登录OpenAI/Anthropic后台提升RPM/TPM限流上限
2. **多密钥轮询**：配置多个独立API Key做负载分摊
3. **切换独立直连地址**：放弃第三方中转网关，直连官方API，避开共享IP限流
4. **降低使用频率**：长任务分段，不要连续不间断调用codex

## 六、快速修复一键流程
```bash
# 1. 清除失效中转密钥
opencode auth logout anthropic
# 2. 冷却3分钟（手动等待）
# 3. 重新配置个人独立API Key
opencode auth login --provider anthropic
# 4. 低重试模式测试小任务
codex --retries 0 --full-auto "输出hello"
```