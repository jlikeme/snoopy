import AVFoundation
import SpriteKit

class OverlayManager {
    private var overlayPlayer: AVQueuePlayer?
    private var overlayPlayerItem: AVPlayerItem?
    private var overlayNode: SKVideoNode?
    private var overlayRepeatCount: Int = 0  // For overlay loops

    private var allClips: [AnimationClipMetadata] = []
    private weak var weatherManager: WeatherManager?
    private weak var stateManager: StateManagerV2?

    init(allClips: [AnimationClipMetadata], weatherManager: WeatherManager, stateManager: StateManagerV2) {
        self.allClips = allClips
        self.weatherManager = weatherManager
        self.stateManager = stateManager
        setupOverlayPlayer()
    }

    func setupOverlayNode(in scene: SKScene) {
        guard let player = self.overlayPlayer else {
            debugLog("Error: Overlay player is nil during scene setup.")
            return
        }
        let overlayNode = SKVideoNode(avPlayer: player)
        overlayNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        overlayNode.size = scene.size
        overlayNode.zPosition = 4
        overlayNode.name = "overlayNode"
        overlayNode.isHidden = true
        scene.addChild(overlayNode)
        self.overlayNode = overlayNode
    }

    private func setupOverlayPlayer() {
        self.overlayPlayer = AVQueuePlayer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(overlayItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    func tryPlayVIWEOverlay() {
        guard overlayPlayerItem == nil else {
            debugLog("🚫 叠加层已在播放，跳过新的触发。")
            return
        }

        let candidates = getFilteredVIWECandidates()
        guard let clipToPlay = candidates.randomElement() else {
            debugLog("🤷 没有可用的 VI/WE 片段可供播放。")
            return
        }

        debugLog("✨ 触发叠加效果: \(clipToPlay.fileName)")
        playOverlayClip(clipToPlay)
    }

    /// 根据时间和天气条件过滤 VI/WE 候选片段
    private func getFilteredVIWECandidates() -> [SnoopyClip] {
        guard let weatherManager = self.weatherManager else {
            debugLog("⚠️ WeatherManager not available.")
            return []
        }

        var candidates: [SnoopyClip] = []

        // 更新天气信息
        weatherManager.updateWeatherFromAPI()

        let currentWeather = weatherManager.getCurrentWeather()
        let weatherAPIAvailable = weatherManager.isAPIAvailable()

        // 获取当前时间
        let currentHour = Calendar.current.component(.hour, from: Date())
        let isNightTime = currentHour >= 18 || currentHour < 5  // 18:00-05:00 为夜晚
        let isDayTime = currentHour >= 5 && currentHour < 18  // 05:00-18:00 为白天

        debugLog("🕐 当前时间: \(currentHour):xx, 夜晚模式: \(isNightTime), 白天模式: \(isDayTime)")
        debugLog("🌤️ 当前天气: \(currentWeather), API可用: \(weatherAPIAvailable)")

        debugLog("🎯 最终候选片段: \(candidates.map { $0.fileName })")
        return candidates
    }

    private func playOverlayClip(_ clip: SnoopyClip) {
        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: clip.fileName, withExtension: nil)
        else {
            debugLog("❌ 错误：找不到叠加片段文件 \(clip.fileName)")
            cleanupOverlay()
            return
        }

        let newItem = AVPlayerItem(url: url)
        self.overlayPlayerItem = newItem

        // 不再需要设置overlayRepeatCount，Loop的继续由主序列状态决定
        self.overlayRepeatCount = 0
        debugLog("📽️ 播放叠加片段: \(clip.fileName)，Loop控制由主序列状态决定")

        overlayPlayer?.removeAllItems()
        overlayPlayer?.insert(newItem, after: nil)
        overlayNode?.isHidden = false
        overlayPlayer?.play()
        debugLog("▶️ 播放叠加片段: \(clip.fileName)")
    }

    func cleanupOverlay() {
        debugLog("🧹 清理叠加层。")
        overlayPlayer?.pause()
        overlayPlayer?.removeAllItems()
        overlayPlayerItem = nil
        overlayNode?.isHidden = true
        overlayRepeatCount = 0
    }

    @objc private func overlayItemDidReachEnd(_ notification: Notification) {
        guard let finishedItem = notification.object as? AVPlayerItem,
            finishedItem == self.overlayPlayerItem
        else {
            return
        }
        handleOverlayItemFinish(finishedItem: finishedItem)
    }

    private func handleOverlayItemFinish(finishedItem: AVPlayerItem) {
        debugLog("✅ 叠加片段播放完成。")

        guard let finishedClip = findClipForPlayerItem(finishedItem) else {
            debugLog("❌ 无法找到完成的叠加项目的 SnoopyClip。清理。")
            cleanupOverlay()
            return
        }

        debugLog(
            "🔍 完成的overlay片段: \(finishedClip.fileName) (类型: \(finishedClip.type), groupID: \(finishedClip.groupID ?? "nil"))"
        )
        debugLog("🔍 主序列状态: \(stateManager?.currentStateType ?? .initial)")

        var nextOverlayClip: SnoopyClip? = nil
        let groupID = finishedClip.groupID

        if finishedClip.type == SnoopyClip.ClipType.VI_Intro
            || finishedClip.type == SnoopyClip.ClipType.WE_Intro
        {
            let loopType: SnoopyClip.ClipType =
                (finishedClip.type == SnoopyClip.ClipType.VI_Intro) ? .VI_Loop : .WE_Loop
            nextOverlayClip = findClip(ofType: loopType, groupID: groupID)
            if let nextClip = nextOverlayClip {
                debugLog("✅ 叠加 Intro 完成，队列 Loop: \(nextClip.fileName)")
            } else {
                debugLog("❌ 叠加 Intro 完成，但未找到组 \(groupID ?? "nil") 的 Loop。清理。")
            }
        } else if finishedClip.type == SnoopyClip.ClipType.VI_Loop
            || finishedClip.type == SnoopyClip.ClipType.WE_Loop
        {
//            // 检查主序列是否仍在BP循环中，而不是使用overlayRepeatCount
//            if stateManager?.isCurrentlyInBPCycle() == true {
//                // 主序列仍在BP循环中，继续播放Loop
//                nextOverlayClip = finishedClip
//                debugLog("🔁 叠加 Loop 完成，主序列仍在BP循环中，继续播放Loop")
//            } else {
//                // 主序列已退出BP循环，强制进入Outro
//                let outroType: SnoopyClip.ClipType =
//                    (finishedClip.type == SnoopyClip.ClipType.VI_Loop) ? .VI_Outro : .WE_Outro
//                nextOverlayClip = findClip(ofType: outroType, groupID: groupID)
//                debugLog("✅ 叠加 Loop 完成，主序列已退出BP循环，强制进入Outro: \(nextOverlayClip?.fileName ?? "未找到")")
//            }
        }

        if let nextClip = nextOverlayClip {
            playOverlayClip(nextClip)
        } else {
            debugLog("✅ 叠加序列完成或未找到组 \(groupID ?? "nil") 的下一个片段。清理。")
            cleanupOverlay()
        }
    }

    func checkAndInterruptActiveOverlayLoop() {
        // 检查是否有活跃的 overlay 播放
        guard let currentItem = overlayPlayerItem else {
            debugLog("🔍 没有活跃的 overlay 播放，无需中断")
            return
        }

        // 通过当前播放的 item 找到对应的 clip
        guard let currentClip = findClipForPlayerItem(currentItem) else {
            debugLog("❌ 无法找到当前播放的 overlay clip")
            return
        }

        if currentClip.type == SnoopyClip.ClipType.VI_Loop
            || currentClip.type == SnoopyClip.ClipType.WE_Loop
        {
            debugLog("🎯 检测到活跃的 \(currentClip.type) loop: \(currentClip.fileName)，准备中断")
            if let groupID = currentClip.groupID {
                interruptOverlayLoopAndPlayOutro(groupID: groupID)
            } else {
                debugLog("❌ 无法获取当前 overlay clip 的 groupID")
                cleanupOverlay()
            }
        }
    }

    private func interruptOverlayLoopAndPlayOutro(groupID: String) {
        debugLog("💥 请求中断overlay Loop，groupID: \(groupID)")

        let outroType: SnoopyClip.ClipType?
        if findClip(ofType: SnoopyClip.ClipType.VI_Loop, groupID: groupID) != nil {
            outroType = .VI_Outro
        } else if findClip(ofType: SnoopyClip.ClipType.WE_Loop, groupID: groupID) != nil {
            outroType = .WE_Outro
        } else {
            outroType = nil
        }

        guard let type = outroType, let outroClip = findClip(ofType: type, groupID: groupID) else {
            debugLog("⚠️ 无法找到组 \(groupID) 的 Outro 来打断 Loop。")
            cleanupOverlay()
            return
        }

        debugLog("💥 打断叠加 Loop，播放 Outro: \(outroClip.fileName)")
        overlayRepeatCount = 0  // 重置重复计数，强制结束Loop
        playOverlayClip(outroClip)
    }

    private func findClip(ofType type: SnoopyClip.ClipType, groupID: String?) -> SnoopyClip? {
//        return allClips.first { $0.type == type && $0.groupID == groupID }
        return nil
    }

    private func findClipForPlayerItem(_ item: AVPlayerItem) -> SnoopyClip? {
        return nil
//        guard let url = (item.asset as? AVURLAsset)?.url else { return nil }
//        return allClips.first { clip in
//            if let clipUrl = Bundle(for: type(of: self)).url(
//                forResource: clip.fileName, withExtension: nil)
//            {
//                return clipUrl == url
//            }
//            return false
//        }
    }

    func getPlayer() -> AVQueuePlayer? {
        return overlayPlayer
    }
}
