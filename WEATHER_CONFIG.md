# Snoopy 屏保配置指南

## 高德地图天气 API 配置

为了启用自动天气获取功能，您需要配置高德地图 API Key。

### 1. 获取高德地图 API Key

1. 访问 [高德开放平台](https://lbs.amap.com/)
2. 注册并登录账户
3. 创建应用并获取 API Key
4. 确保 API Key 有以下服务权限：
   - IP定位
   - 天气查询

### 2. 配置 API Key

1. 在项目根目录找到 `Config.plist` 文件
2. 将 `YOUR_AMAP_API_KEY_HERE` 替换为您的实际 API Key

```xml
<key>AmapAPIKey</key>
<string>您的高德地图API_KEY</string>
```

### 3. 天气功能说明

配置完成后，屏保将自动：
- 通过高德地图IP定位API获取地区编码（无需手动获取IP）
- 获取当前天气信息
- 根据天气和时间条件播放相应的 VI/WE 动画

#### VI/WE 播放规则

- **基础内容**: VI001, VI005 - 始终可播放
- **夜晚内容**: VI002, VI003 - 仅在 18:00-05:00 播放
- **雨天内容**: WE001 - 仅在雨天播放（API可用时）
- **晴天内容**: 
  - WE003 - 仅在晴天且 05:00-18:00 播放（API可用时）
  - VI004 - 仅在晴天且 18:00-05:00 播放（API可用时）

#### 天气API不可用时的回退模式

当天气API无法获取数据时，系统将自动启用回退模式：

- **基础内容**: 正常播放
- **夜晚内容**: 正常播放（按时间限制）
- **雨天内容**: 添加到随机列表中，可随机播放
- **晴天内容**: 添加到随机列表中，但仍遵循时间限制
  - WE003 - 仅在 05:00-18:00 播放
  - VI004 - 仅在 18:00-05:00 播放

这样确保即使无法获取天气信息，用户也能体验到所有类型的动画内容。

### 4. 手动控制

如果不配置 API Key，您仍可以通过代码手动设置天气条件：

```swift
// 在代码中调用
snoopyView.setWeatherCondition(.sunny)  // 晴天
snoopyView.setWeatherCondition(.rainy)  // 雨天
snoopyView.setWeatherCondition(.cloudy) // 阴天（默认）
```

### 5. 故障排除

#### 网络权限问题
如果看到类似 "Sandbox is preventing this process from reading networkd settings" 或 "DNSServiceCreateDelegateConnection failed" 的错误：

1. **Entitlements 配置（开发者）**
   - 确保项目中的 `*.entitlements` 文件包含网络权限：
   ```xml
   <key>com.apple.security.network.client</key>
   <true/>
   ```

#### 其他常见问题
- 如果天气获取失败，屏保将回退到默认的阴天模式
- 查看控制台日志获取详细的错误信息
- 确保网络连接正常
- 验证 API Key 是否正确且有效

#### 测试网络权限
屏保会在启动时自动检测网络权限：
- ✅ 网络权限正常：将显示 "🌐 网络权限正常，开始获取天气信息"
- ⚠️ 权限受限：将显示权限提示并启用回退模式
