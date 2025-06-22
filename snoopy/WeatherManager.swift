import Foundation

class WeatherManager {
    private var amapAPIKey: String?
    private var currentWeather: WeatherCondition = .cloudy  // 手动控制的天气变量
    private var currentAdcode: String?  // 当前地区编码
    private var weatherAPIAvailable: Bool = false  // 天气API是否可用

    init() {
        loadConfiguration()
    }

    private func loadConfiguration() {
        guard
            let configPath = Bundle(for: type(of: self)).path(
                forResource: "Config", ofType: "plist"),
            let configDict = NSDictionary(contentsOfFile: configPath)
        else {
            debugLog("⚠️ 无法加载 Config.plist 文件")
            return
        }

        self.amapAPIKey = configDict["AmapAPIKey"] as? String
        if let key = amapAPIKey, !key.isEmpty && key != "YOUR_AMAP_API_KEY_HERE" {
            debugLog("✅ 高德地图 API Key 加载成功")

            // 检查网络权限并启动天气更新
            checkNetworkPermissionAndUpdateWeather()
        } else {
            debugLog("⚠️ 高德地图 API Key 未配置，将使用手动天气设置")
        }
    }

    private func checkNetworkPermissionAndUpdateWeather() {
        debugLog("🔍 检查网络权限...")

        // 先尝试一个简单的网络请求来检测权限
        guard let testURL = URL(string: "https://www.apple.com") else {
            updateWeatherFromAPI()
            return
        }

        let testTask = URLSession.shared.dataTask(with: testURL) { [weak self] _, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMessage = error.localizedDescription
                    let nsError = error as NSError

                    // 检查是否是网络权限或DNS相关问题
                    if errorMessage.contains("Sandbox") || errorMessage.contains("networkd")
                        || errorMessage.contains("DNSServiceCreateDelegateConnection")
                        || nsError.code == -1003
                    {  // NSURLErrorCannotFindHost

                        debugLog("⚠️ 网络访问受限或DNS解析失败：\(errorMessage)")
                        debugLog("💡 这可能是由于沙盒网络权限限制，启用天气回退模式")
                        self?.weatherAPIAvailable = false
                    } else {
                        debugLog("🌐 网络测试失败但可能是其他原因，尝试获取天气信息")
                        self?.updateWeatherFromAPI()
                    }
                } else {
                    debugLog("🌐 网络权限正常，开始获取天气信息")
                    self?.updateWeatherFromAPI()
                }
            }
        }
        testTask.resume()
    }

    func updateWeatherFromAPI() {
        guard let apiKey = amapAPIKey, !apiKey.isEmpty else {
            debugLog("❌ API Key 未配置，无法获取天气信息")
            return
        }

        debugLog("🌐 开始获取天气信息...")

        // 直接通过高德IP定位API获取地区编码（无需手动获取IP）
        getAdcodeFromCurrentIP(apiKey: apiKey) { [weak self] adcode in
            guard let self = self, let adcode = adcode else {
                debugLog("❌ 获取地区编码失败，启用天气回退模式")
                self?.weatherAPIAvailable = false
                return
            }

            debugLog("🏙️ 地区编码: \(adcode)")
            self.currentAdcode = adcode

            // 通过地区编码获取天气
            self.getWeatherFromAdcode(adcode: adcode, apiKey: apiKey) { weather in
                guard let weather = weather else {
                    debugLog("❌ 获取天气信息失败，启用天气回退模式")
                    self.weatherAPIAvailable = false
                    return
                }

                debugLog("🌤️ 当前天气: \(weather)")
                self.updateWeatherCondition(from: weather)
            }
        }
    }

    private func getAdcodeFromCurrentIP(apiKey: String, completion: @escaping (String?) -> Void) {
        let urlString = "https://restapi.amap.com/v3/ip?output=json&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                let errorMessage = error?.localizedDescription ?? "未知错误"
                let nsError = error as? NSError
                debugLog("❌ 地区编码获取请求失败: \(errorMessage)")

                // 检查是否是沙盒网络权限或DNS问题
                if errorMessage.contains("Sandbox") || errorMessage.contains("networkd")
                    || errorMessage.contains("DNSServiceCreateDelegateConnection")
                    || nsError?.code == -1003
                {
                    debugLog("⚠️ 检测到网络访问限制，可能需要配置entitlements文件中的网络权限")
                }

                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let adcode = json["adcode"] as? String
                {
                    DispatchQueue.main.async {
                        completion(adcode)
                    }
                } else {
                    debugLog("❌ 地区编码解析失败")
                    completion(nil)
                }
            } catch {
                debugLog("❌ 地区编码JSON解析失败: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }

    private func getWeatherFromAdcode(
        adcode: String, apiKey: String, completion: @escaping (String?) -> Void
    ) {
        let urlString =
            "https://restapi.amap.com/v3/weather/weatherInfo?city=\(adcode)&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                let errorMessage = error?.localizedDescription ?? "未知错误"
                let nsError = error as? NSError
                debugLog("❌ 天气信息获取请求失败: \(errorMessage)")

                // 检查是否是沙盒网络权限或DNS问题
                if errorMessage.contains("Sandbox") || errorMessage.contains("networkd")
                    || errorMessage.contains("DNSServiceCreateDelegateConnection")
                    || nsError?.code == -1003
                {
                    debugLog("⚠️ 检测到网络访问限制，可能需要配置entitlements文件中的网络权限")
                }

                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let lives = json["lives"] as? [[String: Any]],
                    let firstLive = lives.first,
                    let weather = firstLive["weather"] as? String
                {
                    DispatchQueue.main.async {
                        completion(weather)
                    }
                } else {
                    debugLog("❌ 天气信息解析失败")
                    completion(nil)
                }
            } catch {
                debugLog("❌ 天气JSON解析失败: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }

    private func updateWeatherCondition(from weatherString: String) {
        let newWeather: WeatherCondition

        if weatherString.contains("晴") {
            newWeather = .sunny
        } else if weatherString.contains("雨") || weatherString.contains("雷") {
            newWeather = .rainy
        } else {
            newWeather = .cloudy
        }

        if newWeather != currentWeather {
            currentWeather = newWeather
            debugLog("🌤️ 天气状态更新为: \(newWeather) (原始: \(weatherString))")
        }

        // 成功获取天气信息，标记API可用
        weatherAPIAvailable = true
        debugLog("✅ 天气API标记为可用")
    }

    func getCurrentWeather() -> WeatherCondition {
        return currentWeather
    }

    func getCurrentAdcode() -> String? {
        return currentAdcode
    }

    func isAPIAvailable() -> Bool {
        return weatherAPIAvailable
    }

    // 公共方法用于启动天气更新过程
    func startWeatherUpdate() {
        checkNetworkPermissionAndUpdateWeather()
    }
}
