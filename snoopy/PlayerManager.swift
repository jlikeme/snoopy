//
//  PlayerManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import AVFoundation
import SpriteKit

class PlayerManager {
    // --- Players ---
    let queuePlayer: AVQueuePlayer
    let overlayPlayer: AVQueuePlayer
    let asPlayer: AVPlayer
    var heicSequencePlayer: HEICSequencePlayer?

    // --- Player Items ---
    var playerItem: AVPlayerItem?
    var overlayPlayerItem: AVPlayerItem?
    var asPlayerItem: AVPlayerItem?

    // --- Overlay State ---
    var overlayRepeatCount: Int = 0

    init() {
        self.queuePlayer = AVQueuePlayer()
        self.overlayPlayer = AVQueuePlayer()
        self.asPlayer = AVPlayer()
        self.heicSequencePlayer = HEICSequencePlayer()  // Initialize HEIC player
        setupPlayerNotifications()
    }

    private func setupPlayerNotifications() {
        // The notification observer will be added in the main view or a dedicated playback manager
        // to have access to the full context needed for handling playback completion.
    }

    func cleanupOverlay() {
        debugLog("🧹 清理叠加层。")
        overlayPlayer.pause()
        overlayPlayer.removeAllItems()
        overlayPlayerItem = nil
        overlayRepeatCount = 0
        // Note: overlayNode.isHidden will be handled by OverlayManager since PlayerManager doesn't have direct access to scene nodes
    }

    func preloadSyncSTHideForDelayedPlayback(stHide: SnoopyClip) {
        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: stHide.fileName, withExtension: nil)
        else {
            debugLog("❌ 预加载失败：找不到ST_Hide视频文件 \(stHide.fileName)")
            return
        }

        let newItem = AVPlayerItem(url: url)
        // 重要：更新playerItem跟踪，以便播放完成通知能被正确识别
        self.playerItem = newItem

        queuePlayer.removeAllItems()
        queuePlayer.insert(newItem, after: nil)
        // 🎬 关键修复：确保播放器暂停，这样延迟播放才能生效
        queuePlayer.pause()

        debugLog("🎬 预加载完成：ST_Hide (\(stHide.fileName)) 已加载并暂停，等待延迟播放")
    }

    func startPreloadedSTHidePlayback() {
        debugLog("🎬 延迟播放开始：ST_Hide 延迟0.5秒后开始播放")
        queuePlayer.play()
    }

    func prepareSyncASForTMReveal(asClip: SnoopyClip) -> Bool {
        guard
            let contentUrl = Bundle(for: type(of: self)).url(
                forResource: asClip.fileName, withExtension: nil)
        else {
            debugLog("❌ 同步播放失败：找不到AS视频文件 \(asClip.fileName)")
            return false
        }

        let newItem = AVPlayerItem(url: contentUrl)
        self.asPlayerItem = newItem
        asPlayer.replaceCurrentItem(with: newItem)
        // 暂停播放，等待TM_Reveal开始
        asPlayer.pause()

        debugLog("✅ 同步播放准备：AS (\(asClip.fileName)) 已加载，等待与TM_Reveal同步播放")
        return true
    }

    func startSyncASPlayback() {
        debugLog("🎬 同步播放开始：AS与TM_Reveal同时播放")
        debugLog(
            "🔧 调试信息: AS播放器开始前状态 - rate: \(asPlayer.rate), currentItem: \(asPlayer.currentItem != nil)"
        )
        asPlayer.play()
        debugLog("🔧 调试信息: AS播放器开始后状态 - rate: \(asPlayer.rate)")
    }
}
