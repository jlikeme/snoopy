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
    private weak var stateManager: StateManager?
    private weak var playerManager: PlayerManager?
    private weak var sceneManager: SceneManager?
    private weak var playbackManager: PlaybackManager?
    private weak var sequenceManager: SequenceManager?
    private weak var overlayManager: OverlayManager?

    init(stateManager: StateManager, playerManager: PlayerManager, sceneManager: SceneManager) {
        self.stateManager = stateManager
        self.playerManager = playerManager
        self.sceneManager = sceneManager
    }

    func setDependencies(
        playbackManager: PlaybackManager, sequenceManager: SequenceManager,
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
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let success = heicPlayer.loadSequence(basePattern: basePattern)

            DispatchQueue.main.async {
                guard let self = self else { return }
                // 重新获取弱引用依赖
                guard let stateManager = self.stateManager,
                    let playerManager = self.playerManager,
                    let sceneManager = self.sceneManager,
                    let playbackManager = self.playbackManager
                else { return }

                if success {
                    debugLog("✅ HEIC序列加载成功: \(basePattern)")
                    self.executeMaskingLogic(
                        tmClip: tmClip,
                        contentClip: contentClip,
                        isRevealing: isRevealing,
                        basePattern: basePattern,
                        stateManager: stateManager,
                        playerManager: playerManager,
                        sceneManager: sceneManager,
                        playbackManager: playbackManager,
                        heicPlayer: heicPlayer
                    )
                } else {
                    debugLog("❌ 错误：无法加载HEIC序列: \(basePattern)")
                    stateManager.isMasking = false
                    stateManager.currentClipIndex += 1
                    playbackManager.playNextClipInQueue()
                }
            }
        }
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

        if isRevealing {
            // TM_Reveal完成：AS/SS内容已经在同步播放
            debugLog("▶️ TM_Reveal完成，AS/SS内容已通过同步播放开始")

            // AS已经在同步播放，不需要再次启动
            // asPlayer?.play()  // 注释掉，因为AS已经在同步播放

            // 如果当前播放的是AS，跳过队列中的AS，等待AS播放完成
            if stateManager.currentStateType == .playingTMReveal
                && stateManager.currentClipIndex + 1 < stateManager.currentClipsQueue.count
                && stateManager.currentClipsQueue[stateManager.currentClipIndex + 1].type
                    == SnoopyClip.ClipType.AS
            {
                debugLog("🔄 AS通过同步播放显示，跳过队列中的AS片段")
                stateManager.currentClipIndex += 1  // 移到AS
                // 不调用playNextClipInQueue()，等待AS播放完成
                // AS播放完成时会触发asPlaybackEnded，那时再处理后续逻辑
            } else {
                // 其他情况（如SS_Intro），继续队列处理
                debugLog("▶️ 继续队列处理")
                playbackManager.playNextClipInQueue()
            }
        } else {
            // TM_Hide完成：隐藏AS/SS内容并继续到下一个序列
            debugLog("▶️ TM_Hide完成，隐藏AS/SS内容并继续到下一个序列")

            // 隐藏AS视频节点
            if let asVideoNode = sceneManager.asVideoNode {
                asVideoNode.isHidden = true
            }

            // 暂停AS播放器
            playerManager.asPlayer.pause()

            // 使用当前TM_Hide片段的编号来生成ST_Hide序列
            let transitionNumber = tmClip.number
            debugLog("🔍 使用TM_Hide编号生成序列: \(transitionNumber ?? "nil")")

            // 根据是AS还是SS流程使用不同的预存队列
            let nextQueue =
                stateManager.isPlayingSS ? stateManager.nextAfterSS : stateManager.nextAfterAS

            if !nextQueue.isEmpty {
                debugLog(
                    "🔄 使用预存队列: \(nextQueue.count) 片段 (来源: \(stateManager.isPlayingSS ? "SS" : "AS"))"
                )

                // 🎬 关键简化：由于ST_Hide总是通过同步播放处理，始终跳过队列中的ST_Hide
                let queueToUse: [SnoopyClip]
                if nextQueue.count >= 1 && nextQueue[0].type == SnoopyClip.ClipType.ST_Hide {
                    debugLog("⏭️ ST_Hide通过同步播放处理，跳过队列中的ST_Hide，直接使用后续片段")
                    queueToUse = Array(nextQueue.dropFirst())  // 跳过第一个ST_Hide
                } else {
                    queueToUse = nextQueue
                }

                stateManager.currentClipsQueue = queueToUse
                stateManager.currentClipIndex = 0

                // 清空相应的预存队列
                if stateManager.isPlayingSS {
                    stateManager.nextAfterSS = []
                } else {
                    stateManager.nextAfterAS = []
                }
            } else {
                debugLog("🔄 没有预存队列，生成RPH → BP_Node序列（ST_Hide通过同步播放处理）")

                // 🎬 简化逻辑：ST_Hide总是通过同步播放处理，直接生成RPH → BP_Node序列
                if let randomRPH = sequenceManager.findRandomClip(ofType: SnoopyClip.ClipType.RPH),
                    let targetBPNode = sequenceManager.findClip(
                        ofType: SnoopyClip.ClipType.BP_Node, nodeName: randomRPH.to)
                {
                    stateManager.currentClipsQueue = [randomRPH, targetBPNode]
                    stateManager.currentClipIndex = 0
                    debugLog("✅ 生成RPH → BP_Node序列，ST_Hide通过同步播放处理")
                } else {
                    debugLog("❌ 无法生成RPH → BP_Node序列，使用回退序列")
                    let fallbackQueue = sequenceManager.generateFallbackSequence()
                    if !fallbackQueue.isEmpty {
                        stateManager.currentClipsQueue = fallbackQueue
                        stateManager.currentClipIndex = 0
                    }
                }
            }

            // 如果刚完成SS流程，重置SS标志并清理SS相关变量
            if stateManager.isPlayingSS {
                debugLog("🎬 SS流程完成，重置SS标志")
                stateManager.isPlayingSS = false
                stateManager.ssTransitionNumber = nil
            }
        }

        // 清理cropNode遮罩效果和outline显示
        if let cropNode = sceneManager.cropNode {
            // 清除遮罩效果
            cropNode.maskNode = nil
            debugLog("🧹 清理cropNode遮罩效果")

            // AS视频节点始终保持在cropNode中，不需要移动
            // cropNode will be reused for future AS/SS content with masking
        }

        // 隐藏outline节点
        if let outlineNode = sceneManager.tmOutlineSpriteNode {
            outlineNode.isHidden = true
            debugLog("🧹 隐藏TM outline节点")
        }

        // 重置状态
        stateManager.isMasking = false

        // TM_Reveal的情况已经在上面处理过了，这里只处理TM_Hide的情况
        if !isRevealing {
            // 🎬 简化逻辑：ST_Hide总是通过同步播放处理，等待其完成再继续队列
            debugLog("⏸️ TM_Hide完成，等待ST_Hide同步播放完成再继续队列")
            // 不调用playNextClipInQueue()，等待ST_Hide播放完成
        }
        // TM_Reveal的情况在上面已经处理，这里不需要额外的队列处理
    }

    func handleASCompletionWithTMHide() {
        guard let stateManager = stateManager, let sequenceManager = sequenceManager else { return }
        stateManager.currentStateType = .transitioningToHalftoneHide
        let tmHide =
            sequenceManager.findRandomClip(
                ofType: .TM_Hide, matchingNumber: stateManager.lastTransitionNumber)
            ?? sequenceManager.findRandomClip(ofType: .TM_Hide)
        if let tmHide = tmHide {
            startTMHideTransition(tmHide: tmHide)
        } else {
            debugLog("❌ Error: Could not find any TM_Hide clip.")
        }
    }

    func handleSSCompletionWithTMHide() {
        guard let stateManager = stateManager, let sequenceManager = sequenceManager else { return }
        stateManager.currentStateType = .transitioningToHalftoneHide
        if let randomTMHide = sequenceManager.findRandomClip(ofType: .TM_Hide) {
            startTMHideTransition(tmHide: randomTMHide)
        } else {
            debugLog("❌ Error: Could not find any TM_Hide clip for SS completion.")
        }
    }

    private func startTMHideTransition(tmHide: SnoopyClip) {
        // 直接播放TM_Hide，而不是通过队列系统
        guard let playerManager = playerManager else { return }

        if playerManager.heicSequencePlayer == nil {
            // heicSequencePlayer should be initialized in PlayerManager init, but just in case
            debugLog("⚠️ heicSequencePlayer为nil，这不应该发生")
            return
        }

        guard let player = playerManager.heicSequencePlayer else {
            debugLog("❌ 错误：无法获取HEIC序列播放器")
            return
        }

        // 在后台线程加载TM_Hide序列以避免卡顿
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let success = player.loadSequence(basePattern: tmHide.fileName)

            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let stateManager = self.stateManager, let sceneManager = self.sceneManager
                else { return }

                if success {
                    debugLog("🎭 直接启动TM_Hide HEIC序列: \(tmHide.fileName)")
                    stateManager.isMasking = true

                    // 创建mask sprite node如果不存在
                    if sceneManager.tmMaskSpriteNode == nil {
                        guard let scene = sceneManager.scene else {
                            debugLog("❌ 错误：缺少场景组件")
                            return
                        }
                        sceneManager.createTMMaskNode(size: scene.size)
                    }

                    // 🎬 新增：准备ST_Hide同步播放
                    let stHideClip = self.prepareSyncSTHideForTMHide(tmHide: tmHide)

                    // 设置遮罩并播放
                    if let maskNode = sceneManager.tmMaskSpriteNode,
                        let outlineNode = sceneManager.tmOutlineSpriteNode,
                        let asVideoNode = sceneManager.asVideoNode,
                        let cropNode = sceneManager.cropNode
                    {

                        // 确保AS视频节点在cropNode中
                        if asVideoNode.parent != cropNode {
                            asVideoNode.removeFromParent()
                            asVideoNode.position = .zero
                            cropNode.addChild(asVideoNode)
                        }

                        // 确保AS视频节点可见
                        asVideoNode.isHidden = false

                        // 设置cropNode的遮罩节点
                        cropNode.maskNode = maskNode

                        debugLog("🔧 调试信息: ")
                        debugLog("  - cropNode.zPosition: \(cropNode.zPosition)")
                        debugLog("  - asVideoNode.isHidden: \(asVideoNode.isHidden)")
                        debugLog("  - maskNode.size: \(maskNode.size)")
                        debugLog("  - cropNode.maskNode设置完成: \(cropNode.maskNode != nil)")

                        // 🎬 修改：TM_Hide开始播放时，预先加载ST_Hide，然后延迟0.5秒开始播放
                        if let stHide = stHideClip {
                            // 立即预加载ST_Hide
                            playerManager.preloadSyncSTHideForDelayedPlayback(stHide: stHide)

                            // 设置状态管理器的同步播放标志
                            stateManager.currentStateType = .playingSTHide
                            stateManager.isSTHideSyncPlaying = true
                            print("🎬 设置ST_Hide同步播放状态标志")

                            // 延迟0.5秒开始播放（不是加载）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                playerManager.startPreloadedSTHidePlayback()
                                self?.overlayManager?.checkAndInterruptActiveOverlayLoop()
                            }
                        }

                        player.playDual(maskNode: maskNode, outlineNode: outlineNode) {
                            [weak self] in
                            DispatchQueue.main.async {
                                self?.heicSequenceMaskCompleted(
                                    isRevealing: false,
                                    tmClip: tmHide,
                                    basePattern: tmHide.fileName
                                )
                            }
                        }
                    } else {
                        debugLog("❌ 错误：缺少必要的节点来启动TM_Hide过渡")
                    }
                } else {
                    debugLog("❌ 错误：无法加载TM_Hide HEIC序列: \(tmHide.fileName)")
                }
            }
        }
    }

    private func prepareSyncSTHideForTMHide(tmHide: SnoopyClip) -> SnoopyClip? {
        guard let stateManager = stateManager, let sequenceManager = sequenceManager else {
            return nil
        }

        // 根据流程类型选择ST_Hide的编号
        let stHideNumber: String
        if stateManager.isPlayingSS {
            // SS流程：固定使用001编号的ST_Hide
            stHideNumber = "001"
            debugLog("🎬 SS流程同步播放：准备编号001的ST_Hide与TM_Hide同步")
        } else {
            // AS流程：使用TM_Hide的编号
            stHideNumber = tmHide.number ?? "001"
            debugLog("🎬 AS流程同步播放：准备编号 \(stHideNumber) 的ST_Hide与TM_Hide同步")
        }

        guard
            let stHide = sequenceManager.findMatchingST(
                forNumber: stHideNumber, type: SnoopyClip.ClipType.ST_Hide)
        else {
            debugLog("❌ 同步播放失败：找不到编号为 \(stHideNumber) 的ST_Hide")
            return nil
        }

        debugLog(
            "✅ 同步播放准备：找到ST_Hide: \(stHide.fileName) 将预加载并延迟0.5秒与TM_Hide: \(tmHide.fileName) 播放")
        return stHide
    }

    // MARK: - Dual Completion Logic

    func startDelayedTMRevealAndAS(tmRevealClip: SnoopyClip, delay: TimeInterval) {
        debugLog("⏰ 延迟 \(delay) 秒后启动TM_Reveal和AS播放")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self,
                let stateManager = self.stateManager,
                stateManager.currentClipIndex + 2 < stateManager.currentClipsQueue.count,
                stateManager.currentClipsQueue[stateManager.currentClipIndex + 2].type == .AS
            else {
                debugLog("❌ 错误：找不到AS片段")
                return
            }

            debugLog("🎬 延迟时间到，开始TM_Reveal和AS播放")

            let asClip = stateManager.currentClipsQueue[stateManager.currentClipIndex + 2]
            self.startTMRevealSequence(tmRevealClip: tmRevealClip, asClip: asClip)
        }
    }

    private func startTMRevealSequence(tmRevealClip: SnoopyClip, asClip: SnoopyClip) {
        guard let stateManager = stateManager, let playerManager = playerManager,
            let sceneManager = sceneManager, let heicPlayer = playerManager.heicSequencePlayer
        else { return }

        DispatchQueue.global(qos: .userInteractive).async {
            let success = heicPlayer.loadSequence(basePattern: tmRevealClip.fileName)
            DispatchQueue.main.async {
                if success {
                    debugLog("🎭 HEIC序列加载完成: \(tmRevealClip.fileName)")

                    if !playerManager.prepareSyncASForTMReveal(asClip: asClip) {
                        debugLog("❌ 错误：无法准备AS同步播放")
                        return
                    }

                    debugLog("🎭 启动TM_Reveal HEIC序列: \(tmRevealClip.fileName)")
                    stateManager.isMasking = true

                    if let maskNode = sceneManager.tmMaskSpriteNode,
                        let outlineNode = sceneManager.tmOutlineSpriteNode,
                        let asVideoNode = sceneManager.asVideoNode,
                        let cropNode = sceneManager.cropNode
                    {
                        // 确保AS视频节点在cropNode中
                        if asVideoNode.parent != cropNode {
                            asVideoNode.removeFromParent()
                            asVideoNode.position = .zero
                            cropNode.addChild(asVideoNode)
                        }

                        asVideoNode.isHidden = false
                        cropNode.maskNode = maskNode
                        stateManager.currentStateType = .playingTMReveal
                        stateManager.lastTransitionNumber = tmRevealClip.number
                        debugLog(
                            "💾 TM_Reveal过渡期间存储转场编号: \(stateManager.lastTransitionNumber ?? "nil")")
                        playerManager.startSyncASPlayback()
                        heicPlayer.playDual(maskNode: maskNode, outlineNode: outlineNode) {
                            [weak self] in
                            self?.tmRevealCompletedForDualCompletion(tmClip: tmRevealClip)
                        }
                    } else {
                        debugLog("❌ 错误：缺少必要的节点来启动TM_Reveal过渡")
                    }
                } else {
                    debugLog("❌ 错误：无法加载TM_Reveal HEIC序列: \(tmRevealClip.fileName)")
                }
            }
        }
    }

    private func tmRevealCompletedForDualCompletion(tmClip: SnoopyClip) {
        guard let stateManager = stateManager else { return }
        debugLog("✅ TM_Reveal播放完成（方案2）")
        stateManager.tmRevealCompleted = true
        checkDualCompletionAndContinue()
    }

    func checkDualCompletionAndContinue() {
        guard let stateManager = stateManager, let sceneManager = sceneManager else { return }

        debugLog(
            "🔍 检查双重完成状态：ST_Reveal=\(stateManager.stRevealCompleted), TM_Reveal=\(stateManager.tmRevealCompleted)"
        )

        guard stateManager.isWaitingForDualCompletion else {
            debugLog("⚠️ 不在等待双重完成状态，忽略")
            return
        }

        if stateManager.stRevealCompleted && stateManager.tmRevealCompleted {
            debugLog("✅ ST_Reveal和TM_Reveal都已完成，继续播放序列")

            // 重置状态
            stateManager.resetDualCompletion()
            stateManager.isMasking = false

            // 清理cropNode遮罩效果和outline显示
            if let cropNode = sceneManager.cropNode {
                cropNode.maskNode = nil
                debugLog("🧹 清理cropNode遮罩效果")
            }

            // 隐藏outline节点
            if let outlineNode = sceneManager.tmOutlineSpriteNode {
                outlineNode.isHidden = true
                debugLog("🧹 隐藏TM outline节点")
            }

            // 方案2中AS已经通过同步播放开始，不需要重新播放
            // 只需要跳过ST_Reveal和TM_Reveal的索引，等待AS自然完成
            stateManager.currentClipIndex += 2  // 跳过ST_Reveal和TM_Reveal
            debugLog("🔍 方案2：AS已通过同步播放开始，等待其自然完成，当前索引跳转到: \(stateManager.currentClipIndex)")
            // 不调用playNextClipInQueue()，让AS自然播放完成
        } else {
            debugLog("⏳ 等待另一个播放完成...")
        }
    }
}
