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
    var heicSequencePlayer: HEICSpriteSequencePlayer?
    let maskPlayer: AVPlayer
    let outlinePlayer: AVPlayer

    // --- Player Items ---
    var playerItem: AVPlayerItem?
    var overlayPlayerItem: AVPlayerItem?
    var asPlayerItem: AVPlayerItem?
    var maskPlayerItem: AVPlayerItem?
    var outlinePlayerItem: AVPlayerItem?

    // --- Overlay State ---
    var overlayRepeatCount: Int = 0

    init() {
        self.queuePlayer = AVQueuePlayer()
        self.overlayPlayer = AVQueuePlayer()
        self.asPlayer = AVPlayer()
        self.heicSequencePlayer = HEICSpriteSequencePlayer()  // Initialize HEIC player
        self.maskPlayer = AVPlayer()
        self.outlinePlayer = AVPlayer()
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
    }

    func startPreloadedSTHidePlayback() {
        debugLog("🎬 延迟播放开始：ST_Hide 延迟0.5秒后开始播放")
        queuePlayer.play()
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
