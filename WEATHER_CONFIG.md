# Snoopy 屏保配置

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