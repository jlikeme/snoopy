//
//  TransitionManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import AVFoundation
import Foundation
import SpriteKit

class TransitionManager {
    private weak var stateManager: StateManagerV2?
    private weak var playerManager: PlayerManager?
    private weak var sceneManager: SceneManager?
    private weak var playbackManager: PlaybackManagerV2?
    private weak var sequenceManager: SequenceManagerV2?
    private weak var overlayManager: OverlayManager?

    init(stateManager: StateManagerV2, playerManager: PlayerManager, sceneManager: SceneManager) {
        self.stateManager = stateManager
        self.playerManager = playerManager
        self.sceneManager = sceneManager
    }

    func setDependencies(
        playbackManager: PlaybackManagerV2, sequenceManager: SequenceManagerV2,
        overlayManager: OverlayManager
    ) {
        self.playbackManager = playbackManager
        self.sequenceManager = sequenceManager
        self.overlayManager = overlayManager
    }

    // MARK: - Masking and Transitions

    func startMaskTransitionWithHEIC(
        tmClip: SnoopyClip, contentClip: SnoopyClip?, isRevealing: Bool
    ) {
        guard let stateManager = stateManager, let playerManager = playerManager,
            let playbackManager = playbackManager
        else { return }

        let basePattern = tmClip.fileName
        debugLog("🎭 开始HEIC遮罩过渡: \(basePattern), TM片段: \(tmClip.fileName), 显示: \(isRevealing)")

        guard let heicPlayer = playerManager.heicSequencePlayer else {
            debugLog("❌ 错误：HEIC遮罩过渡缺少HEIC播放器。")
            // 安全起见，即使没有播放器也继续队列
            stateManager.currentClipIndex += 1
            playbackManager.playNextClipInQueue()
            return
        }

        // 在后台线程加载HEIC序列以避免卡顿
//        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
//            let success = heicPlayer.loadSequence(basePattern: basePattern)
//
//            DispatchQueue.main.async {
//                guard let self = self else { return }
//                // 重新获取弱引用依赖
//                guard let stateManager = self.stateManager,
//                    let playerManager = self.playerManager,
//                    let sceneManager = self.sceneManager,
//                    let playbackManager = self.playbackManager
//                else { return }
//
//                if success {
//                    debugLog("✅ HEIC序列加载成功: \(basePattern)")
//                    self.executeMaskingLogic(
//                        tmClip: tmClip,
//                        contentClip: contentClip,
//                        isRevealing: isRevealing,
//                        basePattern: basePattern,
//                        stateManager: stateManager,
//                        playerManager: playerManager,
//                        sceneManager: sceneManager,
//                        playbackManager: playbackManager,
//                        heicPlayer: heicPlayer
//                    )
//                } else {
//                    debugLog("❌ 错误：无法加载HEIC序列: \(basePattern)")
//                    stateManager.isMasking = false
//                    stateManager.currentClipIndex += 1
//                    playbackManager.playNextClipInQueue()
//                }
//            }
//        }
    }

    private func executeMaskingLogic(
        tmClip: SnoopyClip,
        contentClip: SnoopyClip?,
        isRevealing: Bool,
        basePattern: String,
        stateManager: StateManager,
        playerManager: PlayerManager,
        sceneManager: SceneManager,
        playbackManager: PlaybackManager,
        heicPlayer: HEICSequencePlayer
    ) {
        stateManager.isMasking = true

        // 创建或获取必要的节点
        if sceneManager.tmMaskSpriteNode == nil {
            sceneManager.createTMMaskNode(size: sceneManager.scene?.size ?? .zero)
        }
        guard let maskNode = sceneManager.tmMaskSpriteNode,
            let outlineNode = sceneManager.tmOutlineSpriteNode,
            let asVideoNode = sceneManager.asVideoNode,
            let cropNode = sceneManager.cropNode
        else {
            debugLog("❌ 错误：HEIC遮罩过渡缺少视频节点组件。")
            stateManager.isMasking = false
            stateManager.currentClipIndex += 1
            playbackManager.playNextClipInQueue()
            return
        }

        // 设置遮罩
        cropNode.maskNode = maskNode

        // 根据显示或隐藏执行不同逻辑
        if isRevealing {
            // --- Reveal Logic ---
            guard let contentClip = contentClip else {
                debugLog("❌ 错误：HEIC显示过渡缺少内容片段 (AS/SS)。")
                stateManager.isMasking = false
                stateManager.currentClipIndex += 1
                playbackManager.playNextClipInQueue()
                return
            }

            debugLog("🔄 准备显示内容: \(contentClip.fileName)")
            if !playerManager.prepareSyncASForTMReveal(asClip: contentClip) {
                debugLog("❌ 错误：无法准备AS同步播放")
                stateManager.isMasking = false
                stateManager.currentClipIndex += 1
                playbackManager.playNextClipInQueue()
                return
            }

            asVideoNode.isHidden = false
            if contentClip.type == .AS {
                stateManager.currentStateType = .playingTMReveal
                stateManager.lastTransitionNumber = tmClip.number
                debugLog("💾 TM_Reveal过渡期间存储转场编号: \(stateManager.lastTransitionNumber ?? "nil")")
            } else if contentClip.type == .SS_Intro {
                stateManager.currentStateType = .playingSSIntro
            }
            playerManager.startSyncASPlayback()
        } else {
            // --- Hide Logic ---
            if stateManager.currentStateType == .playingAS {
                stateManager.currentStateType = .transitioningToHalftoneHide
            }
        }

        // 对两种情况都播放HEIC序列
        heicPlayer.playDual(maskNode: maskNode, outlineNode: outlineNode) { [weak self] in
            DispatchQueue.main.async {
                self?.heicSequenceMaskCompleted(
                    isRevealing: isRevealing, tmClip: tmClip, basePattern: basePattern)
            }
        }
    }

    private func heicSequenceMaskCompleted(
        isRevealing: Bool, tmClip: SnoopyClip, basePattern: String
    ) {
        guard let stateManager = stateManager, let playerManager = playerManager,
            let sceneManager = sceneManager, let playbackManager = playbackManager,
            let sequenceManager = sequenceManager
        else { return }

        debugLog("✅ HEIC遮罩序列完成: \(basePattern), 显示: \(isRevealing), TM片段: \(tmClip.fileName)")
    }

    func handleASCompletionWithTMHide() {

    }

    func handleSSCompletionWithTMHide() {

    }

    private func startTMHideTransition(tmHide: SnoopyClip) {
    }

    private func prepareSyncSTHideForTMHide(tmHide: SnoopyClip) -> SnoopyClip? {
        return nil
    }

    // MARK: - Dual Completion Logic

    func startDelayedTMRevealAndAS(tmRevealClip: SnoopyClip, delay: TimeInterval) {
        debugLog("⏰ 延迟 \(delay) 秒后启动TM_Reveal和AS播放")

    }

    private func startTMRevealSequence(tmRevealClip: SnoopyClip, asClip: SnoopyClip) {
    }

    private func tmRevealCompletedForDualCompletion(tmClip: SnoopyClip) {

    }

    func checkDualCompletionAndContinue() {
    }
}
