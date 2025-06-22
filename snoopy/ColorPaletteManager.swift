//
//  ColorPaletteManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import AppKit
import Foundation

struct ColorPalette {
    let weather: [String]
    let timeOfDay: String
    let backgroundColor: NSColor
    let overlayColor: NSColor
}

class ColorPaletteManager {
    private var colorPalettes: [String: ColorPalette] = [:]

    init() {
        loadColorPalettes()
    }

    private func loadColorPalettes() {
        guard
            let plistPath = Bundle(for: type(of: self)).path(
                forResource: "ColorPaletteConfig", ofType: "plist"),
            let plistData = NSDictionary(contentsOfFile: plistPath),
            let palettesDict = plistData["colorPalettes"] as? [String: [String: Any]]
        else {
            debugLog("❌ 无法加载 ColorPaletteConfig.plist")
            return
        }

        for (key, paletteInfo) in palettesDict {
            guard let weather = paletteInfo["weather"] as? [String],
                let timeOfDay = paletteInfo["timeOfDay"] as? String,
                let backgroundColorDict = paletteInfo["backgroundColor"] as? [String: Any],
                let overlayColorDict = paletteInfo["overlayColor"] as? [String: Any]
            else {
                debugLog("⚠️ 跳过格式错误的调色板配置: \(key)")
                continue
            }

            let backgroundColor = createColor(from: backgroundColorDict)
            let overlayColor = createColor(from: overlayColorDict)

            let palette = ColorPalette(
                weather: weather,
                timeOfDay: timeOfDay,
                backgroundColor: backgroundColor,
                overlayColor: overlayColor
            )

            colorPalettes[key] = palette
        }

        debugLog("🎨 成功加载 \(colorPalettes.count) 个调色板配置")
    }

    private func createColor(from dict: [String: Any]) -> NSColor {
        let red = (dict["red"] as? Int) ?? 0
        let green = (dict["green"] as? Int) ?? 0
        let blue = (dict["blue"] as? Int) ?? 0
        let alpha = (dict["alpha"] as? Double) ?? 1.0

        return NSColor(
            red: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: CGFloat(alpha)
        )
    }

    private func getCurrentTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 6..<18:
            return "day"
        case 18..<22:
            return "evening"
        case 22...23, 0..<6:
            return "latenight"
        default:
            return "day"
        }
    }

    func getColorPalette(for weatherString: String?) -> ColorPalette? {
        let currentTimeOfDay = getCurrentTimeOfDay()

        // 如果有天气信息，尝试模糊匹配
        if let weather = weatherString, !weather.isEmpty {
            // 查找匹配天气和时间的调色板
            for (_, palette) in colorPalettes {
                if palette.timeOfDay == currentTimeOfDay {
                    // 模糊匹配天气关键词
                    for weatherKeyword in palette.weather {
                        if weather.contains(weatherKeyword) {
                            debugLog(
                                "🎨 匹配到调色板 - 天气: \(weather) -> 关键词: \(weatherKeyword), 时间: \(currentTimeOfDay)"
                            )
                            return palette
                        }
                    }
                }
            }

            // 如果没有找到匹配的天气+时间组合，尝试只匹配天气（任意时间）
            for (_, palette) in colorPalettes {
                for weatherKeyword in palette.weather {
                    if weather.contains(weatherKeyword) {
                        debugLog("🎨 部分匹配到调色板 - 天气: \(weather) -> 关键词: \(weatherKeyword) (忽略时间)")
                        return palette
                    }
                }
            }

            debugLog("⚠️ 未找到匹配的天气调色板: \(weather)，将使用时间随机选择")
        }

        // 如果没有天气信息或未匹配到，根据当前时间随机选择一组颜色
        let matchingPalettes = colorPalettes.values.filter { $0.timeOfDay == currentTimeOfDay }

        if let randomPalette = matchingPalettes.randomElement() {
            debugLog("🎨 随机选择调色板 - 时间: \(currentTimeOfDay)")
            return randomPalette
        }

        // 如果连时间匹配都没有，返回任意一个调色板
        if let fallbackPalette = colorPalettes.values.randomElement() {
            debugLog("🎨 使用备选调色板")
            return fallbackPalette
        }

        debugLog("❌ 无法获取任何调色板")
        return nil
    }

    // 获取原始天气信息进行模糊匹配
    func getWeatherString(from weatherManager: WeatherManager) -> String? {
        // 首先尝试从API获取原始天气字符串
        if let rawWeather = weatherManager.getRawWeatherString() {
            return rawWeather
        }

        //        // 如果没有原始字符串，根据枚举返回基本描述
        //        if weatherManager.isAPIAvailable() {
        //            let weather = weatherManager.getCurrentWeather()
        //            switch weather {
        //            case .sunny:
        //                return "晴"
        //            case .rainy:
        //                return "雨"
        //            case .cloudy:
        //                return "阴"
        //            }
        //        }

        return nil
    }
}
