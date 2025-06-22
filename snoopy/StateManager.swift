//
//  StateManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import Foundation

// Define ViewStateType enum
enum ViewStateType {
    case initial
    case playingAS
    case transitioningToHalftoneHide  // Playing TM_Hide
    case playingSTHide
    case playingRPH
    case playingBP  // Includes Loop
    case playingAPIntro
    case playingAPLoop
    case playingAPOutro
    case playingCM
    case decidingNextHalftoneAction  // After BP loop or AP/CM finishes
    case transitioningToASReveal  // Playing ST_Reveal
    case playingTMReveal
    case playingSSIntro
    case playingSSLoop
    case playingSSOutro
}

// Define WeatherCondition enum for shared use
enum WeatherCondition {
    case sunny  // 晴天
    case rainy  // 雨天
    case cloudy  // 阴天（默认）
}

class StateManager {
    // --- State Management Properties ---
    var allClips: [SnoopyClip] = []
    var currentClipsQueue: [SnoopyClip] = []
    var currentClipIndex: Int = 0
    var currentNode: String?  // e.g., "BP001"
    var currentStateType: ViewStateType = .initial
    var currentRepeatCount: Int = 0  // For handling loops manually
    var isMasking: Bool = false  // Flag to indicate mask transition is active

    // --- Additional State Variables ---
    var bpCycleCount: Int = 0
    var lastTransitionNumber: String?  // Stores the number (e.g., "001") of the last ST/TM Reveal (for AS flow)
    var ssTransitionNumber: String?  // Stores the number for SS flow (always "001")
    var nextAfterAS: [SnoopyClip] = []  // Stores clips to play after AS finishes
    var nextAfterSS: [SnoopyClip] = []  // Stores clips to play after SS finishes
    var isFirstASPlayback: Bool = true  // Mark if it's the first AS playback
    var isPlayingSS: Bool = false  // Mark if currently in the SS flow
    var isSTHideSyncPlaying: Bool = false  // Mark if ST_Hide is playing synchronously

    // --- Dual Completion State (for ST_Reveal and TM_Reveal) ---
    var stRevealCompleted: Bool = false
    var tmRevealCompleted: Bool = false
    var isWaitingForDualCompletion: Bool = false

    // --- Weather State ---
    var currentWeather: WeatherCondition = .cloudy  // 手动控制的天气变量

    // --- Overlay State ---
    var overlayRepeatCount: Int = 0  // For overlay loops

    init() {
        // Initial values are set above
    }

    func updateStateForStartingClip(_ clip: SnoopyClip) {
        switch clip.type {
        case .AS:
            currentStateType = .playingAS
        case .TM_Hide:
            currentStateType = .transitioningToHalftoneHide
        case .ST_Hide:
            currentStateType = .playingSTHide
        case .RPH:
            currentStateType = .playingRPH
        case .BP_Node:
            currentStateType = .playingBP
            if let rphNode = clip.from {
                self.currentNode = rphNode
                debugLog("📍 当前节点设置为: \(self.currentNode ?? "nil") 来自 RPH")
            }
        case .AP_Intro:
            currentStateType = .playingAPIntro
        case .AP_Loop:
            currentStateType = .playingAPLoop
        case .AP_Outro:
            currentStateType = .playingAPOutro
        case .CM:
            currentStateType = .playingCM
        case .ST_Reveal:
            currentStateType = .transitioningToASReveal
        case .TM_Reveal:
            currentStateType = .playingTMReveal
        case .SS_Intro:
            currentStateType = .playingSSIntro
        case .SS_Loop:
            currentStateType = .playingSSLoop
        case .SS_Outro:
            currentStateType = .playingSSOutro
        default:
            debugLog("⚠️ 未明确处理的片段类型: \(clip.type)")
        }
        debugLog("📊 当前状态更新为: \(currentStateType)")
    }

    func resetForFallback() {
        bpCycleCount = 0
        lastTransitionNumber = nil
        ssTransitionNumber = nil
        isPlayingSS = false
    }

    func resetDualCompletion() {
        isWaitingForDualCompletion = false
        stRevealCompleted = false
        tmRevealCompleted = false
    }

    func isCurrentlyInBPCycle() -> Bool {
        // 检查主序列是否仍在BP循环状态中
        let isBPLooping = (currentStateType == .playingBP || currentStateType == .playingAPLoop)

        // 额外检查：如果当前队列中包含正在循环的BP_Node或AP_Loop
        let hasLoopingClip =
            currentClipIndex < currentClipsQueue.count
            && (currentClipsQueue[currentClipIndex].type == SnoopyClip.ClipType.BP_Node
                || currentClipsQueue[currentClipIndex].type == SnoopyClip.ClipType.AP_Loop)
            && currentRepeatCount > 0

        let result = isBPLooping || hasLoopingClip
        debugLog(
            "🔍 isCurrentlyInBPCycle: \(result) (状态: \(currentStateType), 重复次数: \(currentRepeatCount))"
        )
        return result
    }

    func checkDualCompletionStatus() -> Bool {
        let isDualComplete = stRevealCompleted && tmRevealCompleted
        debugLog(
            "🔍 检查双重完成状态：ST_Reveal=\(stRevealCompleted), TM_Reveal=\(tmRevealCompleted), isWaiting=\(isWaitingForDualCompletion)"
        )
        return isDualComplete && isWaitingForDualCompletion
    }

    func markSTRevealCompleted() {
        stRevealCompleted = true
        debugLog("✅ ST_Reveal 标记为完成")
    }

    func markTMRevealCompleted() {
        tmRevealCompleted = true
        debugLog("✅ TM_Reveal 标记为完成")
    }

    func setWaitingForDualCompletion(_ waiting: Bool) {
        isWaitingForDualCompletion = waiting
        if waiting {
            debugLog("⏳ 开始等待双重完成（ST_Reveal 和 TM_Reveal）")
        } else {
            debugLog("✅ 结束等待双重完成")
        }
    }
}
