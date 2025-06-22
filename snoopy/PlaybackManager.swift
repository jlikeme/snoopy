//
//  PlaybackManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import AVFoundation
import Foundation

class PlaybackManager {
    private let stateManager: StateManager
    private let playerManager: PlayerManager
    private let sceneManager: SceneManager
    private let transitionManager: TransitionManager
    private var sequenceManager: SequenceManager!  // Will be set after initialization
    private var overlayManager: OverlayManager!  // Will be set after initialization

    init(
        stateManager: StateManager, playerManager: PlayerManager, sceneManager: SceneManager,
        transitionManager: TransitionManager
    ) {
        self.stateManager = stateManager
        self.playerManager = playerManager
        self.sceneManager = sceneManager
        self.transitionManager = transitionManager
        setupNotifications()
    }

    func setSequenceManager(_ sequenceManager: SequenceManager) {
        self.sequenceManager = sequenceManager
    }

    func setOverlayManager(_ overlayManager: OverlayManager) {
        self.overlayManager = overlayManager
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    func startInitialPlayback() {
        debugLog("Setting up initial state...")
        guard let initialAS = sequenceManager.findRandomClip(ofType: SnoopyClip.ClipType.AS) else {
            debugLog("Error: No AS clips found to start.")
            return
        }
        debugLog("Initial AS: \(initialAS.fileName)")

        let availableTransitionNumbers = stateManager.allClips.compactMap { clip -> String? in
            guard clip.type == SnoopyClip.ClipType.TM_Hide else { return nil }
            return clip.number
        }.filter { $0 != "006" }

        if let randomNumber = availableTransitionNumbers.randomElement() {
            stateManager.lastTransitionNumber = randomNumber
            debugLog("🎲 Set random transition number for initial AS: \(randomNumber)")
        } else {
            debugLog("⚠️ Warning: Could not find any available transition numbers.")
        }

        stateManager.currentStateType = .playingAS
        stateManager.currentClipsQueue = [initialAS]
        stateManager.currentClipIndex = 0
        playNextClipInQueue()
    }

    func playNextClipInQueue() {
        guard !stateManager.isMasking else {
            debugLog("⏳ Mask transition in progress, delaying next main clip playback.")
            return
        }
        guard stateManager.currentClipIndex < stateManager.currentClipsQueue.count else {
            debugLog("✅ Current queue finished. Handling end of queue...")
            handleEndOfQueue()
            return
        }

        let clipToPlay = stateManager.currentClipsQueue[stateManager.currentClipIndex]
        debugLog(
            "🎬 Processing clip (\(stateManager.currentClipIndex + 1)/\(stateManager.currentClipsQueue.count)): \(clipToPlay.fileName) (\(clipToPlay.type))"
        )
        debugLog(
            "🔍 播放前状态：currentStateType=\(stateManager.currentStateType), isMasking=\(stateManager.isMasking)"
        )

        stateManager.updateStateForStartingClip(clipToPlay)

        if clipToPlay.type == SnoopyClip.ClipType.TM_Hide
            || clipToPlay.type == SnoopyClip.ClipType.TM_Reveal
        {
            let contentClip: SnoopyClip?
            if clipToPlay.type == SnoopyClip.ClipType.TM_Reveal
                && stateManager.currentClipIndex + 1 < stateManager.currentClipsQueue.count
            {
                contentClip = stateManager.currentClipsQueue[stateManager.currentClipIndex + 1]
            } else {
                contentClip = nil
            }
            transitionManager.startMaskTransitionWithHEIC(
                tmClip: clipToPlay, contentClip: contentClip,
                isRevealing: clipToPlay.type == SnoopyClip.ClipType.TM_Reveal)
            return
        }

        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: clipToPlay.fileName, withExtension: nil)
        else {
            debugLog("❌ Error: Video file not found \(clipToPlay.fileName)")
            advanceAndPlay()
            return
        }

        // 特殊调试：如果是RPH，记录播放开始时间
        if clipToPlay.type == SnoopyClip.ClipType.RPH {
            debugLog("🎬 RPH播放开始: \(clipToPlay.fileName) - \(Date())")
            debugLog(
                "🔍 RPH详细信息：duration=\(clipToPlay.duration)s, from=\(clipToPlay.from ?? "nil"), to=\(clipToPlay.to ?? "nil")"
            )
        }

        let newItem = AVPlayerItem(url: url)
        debugLog("✅ 成功创建AVPlayerItem for \(clipToPlay.fileName)")

        if clipToPlay.type == SnoopyClip.ClipType.AS
            || clipToPlay.type == SnoopyClip.ClipType.SS_Intro
            || clipToPlay.type == SnoopyClip.ClipType.SS_Loop
            || clipToPlay.type == SnoopyClip.ClipType.SS_Outro
        {
            // 检查是否已经预加载了当前内容
            let currentAsItem = playerManager.asPlayer.currentItem
            let shouldUsePreloaded =
                clipToPlay.type == SnoopyClip.ClipType.SS_Intro && currentAsItem != nil
                && currentAsItem?.asset is AVURLAsset
                && (currentAsItem?.asset as? AVURLAsset)?.url.lastPathComponent
                    == clipToPlay.fileName

            if shouldUsePreloaded {
                // 内容已经预加载，直接使用
                debugLog("📊 使用预加载的SS_Intro内容")
                playerManager.asPlayerItem = currentAsItem
                sceneManager.asVideoNode?.isHidden = false
                playerManager.asPlayer.play()
            } else {
                // 常规加载流程
                playerManager.asPlayerItem = newItem
                playerManager.asPlayer.replaceCurrentItem(with: newItem)
                sceneManager.asVideoNode?.isHidden = false
                playerManager.asPlayer.play()
            }
            debugLog("📊 AS/SS内容使用独立播放器在顶层播放")
        } else {
            playerManager.playerItem = newItem
            sceneManager.asVideoNode?.isHidden = true
            playerManager.queuePlayer.removeAllItems()
            playerManager.queuePlayer.insert(newItem, after: nil)

            debugLog("📊 常规内容使用主播放器在Layer 3播放")
            debugLog(
                "🔍 播放器状态：items=\(playerManager.queuePlayer.items().count), rate=\(playerManager.queuePlayer.rate)"
            )

            playerManager.queuePlayer.play()

            debugLog(
                "� 播放开始后状态：rate=\(playerManager.queuePlayer.rate), timeControlStatus=\(playerManager.queuePlayer.timeControlStatus.rawValue)"
            )

            // 🎬 ST_Reveal特殊处理 - 检查下一个是否是TM_Reveal（普通AS流程）
            if clipToPlay.type == SnoopyClip.ClipType.ST_Reveal
                && stateManager.currentClipIndex + 1 < stateManager.currentClipsQueue.count
                && stateManager.currentClipsQueue[stateManager.currentClipIndex + 1].type
                    == SnoopyClip.ClipType.TM_Reveal
            {

                let tmRevealClip = stateManager.currentClipsQueue[stateManager.currentClipIndex + 1]
                debugLog("🎬 检测到ST_Reveal -> TM_Reveal序列，启动方案2（同时结束）")

                // 计算延迟启动时间
                let stDuration = clipToPlay.duration
                let tmDuration = tmRevealClip.duration
                let delayTime = max(0, stDuration - tmDuration)

                debugLog(
                    "📊 时长信息：ST_Reveal=\(stDuration)s, TM_Reveal=\(tmDuration)s, 延迟=\(delayTime)s")

                // 设置双重完成等待状态
                stateManager.isWaitingForDualCompletion = true
                stateManager.stRevealCompleted = false
                stateManager.tmRevealCompleted = false

                // 延迟启动TM_Reveal和AS
                transitionManager.startDelayedTMRevealAndAS(
                    tmRevealClip: tmRevealClip, delay: delayTime)
            }
            // 特殊处理：如果当前是ST_Reveal且下一个是SS_Intro，预加载SS_Intro到AS播放器
            else if clipToPlay.type == SnoopyClip.ClipType.ST_Reveal
                && stateManager.currentClipIndex + 1 < stateManager.currentClipsQueue.count
                && stateManager.currentClipsQueue[stateManager.currentClipIndex + 1].type
                    == SnoopyClip.ClipType.SS_Intro
            {

                let nextClip = stateManager.currentClipsQueue[stateManager.currentClipIndex + 1]
                if let nextUrl = Bundle(for: type(of: self)).url(
                    forResource: nextClip.fileName, withExtension: nil)
                {
                    let nextItem = AVPlayerItem(url: nextUrl)
                    debugLog("🔮 预加载SS_Intro到AS播放器: \(nextClip.fileName)")

                    // 预加载但不播放，确保AS视频节点隐藏
                    playerManager.asPlayer.replaceCurrentItem(with: nextItem)
                    sceneManager.asVideoNode?.isHidden = true
                } else {
                    debugLog("⚠️ 无法预加载SS_Intro: \(nextClip.fileName)")
                }
            }
        }

        // Loop handling
        if clipToPlay.type == SnoopyClip.ClipType.BP_Node
            || clipToPlay.type == SnoopyClip.ClipType.AP_Loop
        {
            let initialRepeatCount = max(1, clipToPlay.repeatCount)
            stateManager.currentRepeatCount = max(0, initialRepeatCount - 1)
            debugLog("🔁 循环片段检测到: \(clipToPlay.fileName)。剩余重复次数: \(stateManager.currentRepeatCount)")
        } else if clipToPlay.type == SnoopyClip.ClipType.SS_Loop {
            stateManager.currentRepeatCount = 0  // SS_Loop only plays once
            debugLog("🔁 循环片段检测到: \(clipToPlay.fileName)。SS_Loop 设置为播放一次。")
        } else {
            stateManager.currentRepeatCount = 0
        }

        // VI/WE overlay logic for BP and AP loops
        if clipToPlay.type == SnoopyClip.ClipType.BP_Node
            || clipToPlay.type == SnoopyClip.ClipType.AP_Loop
        {
            let overlayChance = 0.2
            if Double.random(in: 0...1) < overlayChance {
                debugLog("🎯 触发VI/WE叠加层概率检查通过")
                overlayManager?.tryPlayVIWEOverlay()
            }
        }
    }

    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        guard let finishedItem = notification.object as? AVPlayerItem else {
            debugLog("⚠️ 通知接收到的对象不是 AVPlayerItem。忽略。")
            return
        }

        // 特殊处理：在方案2双重完成等待期间，允许处理ST_Reveal完成事件
        if stateManager.isMasking && !stateManager.isWaitingForDualCompletion {
            debugLog("🔍 isMasking=true但不在双重完成等待中，忽略播放完成事件")
            return
        }

        if finishedItem == playerManager.overlayPlayerItem {
            // This will be handled by OverlayManager
            return
        }

        if finishedItem == playerManager.asPlayerItem {
            debugLog("✅ AS/SS播放器内容播放完成，直接在此处理")
            // 移除这个特定的通知观察者
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: finishedItem)
            handleASPlaybackCompletion()
            return
        }

        guard finishedItem == playerManager.playerItem else {
            debugLog("⚠️ 通知接收到意外的播放器项目。忽略。")
            return
        }
        debugLog("✅ 主播放器内容播放完成。")

        if stateManager.currentRepeatCount > 0 {
            debugLog("🔁 循环片段。剩余重复次数: \(stateManager.currentRepeatCount - 1)")
            if let url = (finishedItem.asset as? AVURLAsset)?.url {
                let newItem = AVPlayerItem(url: url)
                playerManager.playerItem = newItem
                playerManager.queuePlayer.removeAllItems()
                playerManager.queuePlayer.insert(newItem, after: nil)
                stateManager.currentRepeatCount -= 1
                playerManager.queuePlayer.play()
                return
            }
        }

        guard stateManager.currentClipIndex < stateManager.currentClipsQueue.count else {
            debugLog("❌ 错误：playerItemDidReachEnd 调用时索引超出范围。")
            return
        }

        // 特殊处理：如果ST_Hide正在同步播放且当前状态是playingSTHide，
        // 说明这是ST_Hide同步播放完成的通知，而不是队列中片段的完成
        if stateManager.isSTHideSyncPlaying && stateManager.currentStateType == .playingSTHide {
            debugLog("✅ ST_Hide同步播放完成")
            stateManager.isSTHideSyncPlaying = false
            debugLog("🔄 ST_Hide同步播放完成，重置标志，现在开始播放队列中的下一个片段")
            debugLog(
                "🔍 当前队列状态：索引=\(stateManager.currentClipIndex), 队列长度=\(stateManager.currentClipsQueue.count)"
            )
            if stateManager.currentClipIndex < stateManager.currentClipsQueue.count {
                let nextClip = stateManager.currentClipsQueue[stateManager.currentClipIndex]
                debugLog("🔍 下一个要播放的片段：\(nextClip.fileName) (\(nextClip.type))")
            }
            playNextClipInQueue()  // Now play the RPH from the queue
            return
        }

        let finishedClip = stateManager.currentClipsQueue[stateManager.currentClipIndex]

        guard
            finishedClip.type != SnoopyClip.ClipType.TM_Hide
                && finishedClip.type != SnoopyClip.ClipType.TM_Reveal
        else {
            debugLog("❌ 错误：主播放器意外完成 TM 片段。")
            advanceAndPlay()
            return
        }
        debugLog("✅ 完成主片段: \(finishedClip.fileName)")

        // 特殊调试：如果是RPH，记录播放结束时间
        if finishedClip.type == SnoopyClip.ClipType.RPH {
            debugLog("🎬 RPH播放结束: \(finishedClip.fileName) - \(Date())")
        }

        // 🎬 方案2：ST_Reveal播放完毕的处理
        if finishedClip.type == SnoopyClip.ClipType.ST_Reveal {
            debugLog("🎬 ST_Reveal 完成")

            // 检查是否是方案2（等待双重完成）
            if stateManager.isWaitingForDualCompletion {
                debugLog("🎬 ST_Reveal完成（方案2），标记并检查双重完成")
                stateManager.stRevealCompleted = true
                transitionManager.checkDualCompletionAndContinue()
                return
            }

            // 原有逻辑：如果下一个是TM_Reveal，使用TM_Reveal过渡
            if stateManager.currentClipIndex + 1 < stateManager.currentClipsQueue.count
                && stateManager.currentClipsQueue[stateManager.currentClipIndex + 1].type
                    == SnoopyClip.ClipType.TM_Reveal
            {
                // 增加索引并播放下一个片段，这将触发TM_Reveal的开始
                advanceAndPlay()
                return
            }

            debugLog("🎬 ST_Reveal 完成。继续序列。")
        }

        sequenceManager.generateNextSequence(basedOn: finishedClip)
        advanceAndPlay()
    }

    private func handleASPlaybackCompletion() {
        debugLog("✅ AS/SS视频播放完毕")
        debugLog("🔧 调试信息: handleASPlaybackCompletion被调用 - \(Date())")
        debugLog(
            "🔍 AS/SS播放完成，状态: \(stateManager.currentStateType), 是否首次: \(stateManager.isFirstASPlayback), 是否SS流程: \(stateManager.isPlayingSS)"
        )

        // 根据当前状态判断如何处理
        switch stateManager.currentStateType {
        case .playingSSIntro, .playingSSLoop:
            // SS_Intro或SS_Loop完成，继续播放下一个SS片段，不进入TM_Hide
            debugLog(
                "🔍 \(stateManager.currentStateType == .playingSSIntro ? "SS_Intro" : "SS_Loop")完成，继续播放下一个SS片段"
            )
            advanceAndPlay()
            return
        case .playingSSOutro:
            // SS_Outro完成，需要延迟后进入TM_Hide，类似原来的ssOutroPlaybackEnded逻辑
            debugLog("✅ SS_Outro视频播放完毕")
            // 设置状态为隐藏过渡
            stateManager.currentStateType = .transitioningToHalftoneHide
            transitionManager.handleSSCompletionWithTMHide()
            return
        default:  // .playingAS
            // 只有AS播放完成才立即进入TM_Hide过渡
            // 如果是首次AS播放，需要先加载背景
            if stateManager.isFirstASPlayback && !stateManager.isPlayingSS {
                //debugLog("🔍 初始AS播放完成，加载背景")
                //sceneManager.updateBackgrounds()
                stateManager.isFirstASPlayback = false  // 标记初次AS播放已完成
            }

            // AS播放完成，立即进入TM_Hide过渡
            if !stateManager.isPlayingSS {
                debugLog("🔍 AS播放完成，启动TM_Hide过渡隐藏AS内容")
                sceneManager.updateBackgrounds()
                transitionManager.handleASCompletionWithTMHide()
            }
        }
    }

    private func handleEndOfQueue() {
        debugLog("❌ Reached end of queue unexpectedly. Generating fallback sequence.")
        playerManager.queuePlayer.pause()
        playerManager.queuePlayer.removeAllItems()
        let fallbackQueue = sequenceManager.generateFallbackSequence()
        if !fallbackQueue.isEmpty {
            stateManager.currentClipsQueue = fallbackQueue
            stateManager.currentClipIndex = 0
            playNextClipInQueue()
        } else {
            debugLog("❌ CRITICAL: Could not generate fallback queue! Playback stopped.")
        }
    }

    private func advanceAndPlay() {
        stateManager.currentClipIndex += 1
        playNextClipInQueue()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
