//
//  StateManagerV2.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import Foundation
import SpriteKit

// ViewStateType based on AnimationClipGroupType
enum ViewStateTypeV2 {
    case pose
    case transition
    case other
    case initial
}

enum WeatherConditionV2 {
    case sunny  // 晴天
    case rainy  // 雨天
    case cloudy  // 阴天（默认）
}

class StateManagerV2 {
    // --- State Management Properties ---
    var allClips: [AnimationClipMetadata] = []
    var currentClipsQueue: [AnimationClipMetadata] = []
    var currentClipIndex: Int = 0
    var currentNode: String?  // e.g., "BP001"
    var currentStateType: ViewStateTypeV2 = .other
    var currentRepeatCount: Int = 0  // For handling loops manually
    var isMasking: Bool = false  // Flag to indicate mask transition is active

    // --- Additional State Variables ---
    var bpCycleCount: Int = 0
    var lastTransitionNumber: String?  // Stores the number (e.g., "001") of the last ST/TM Reveal (for AS flow)
    var ssTransitionNumber: String?  // Stores the number for SS flow (always "001")
    var nextAfterAS: [AnimationClipMetadata] = []  // Stores clips to play after AS finishes
    var nextAfterSS: [AnimationClipMetadata] = []  // Stores clips to play after SS finishes
    var isFirstASPlayback: Bool = true  // Mark if it's the first AS playback
    var isPlayingSS: Bool = false  // Mark if currently in the SS flow
    var isSTHideSyncPlaying: Bool = false  // Mark if ST_Hide is playing synchronously

    // --- Dual Completion State (for ST_Reveal and TM_Reveal) ---
    var stRevealCompleted: Bool = false
    var tmRevealCompleted: Bool = false
    var isWaitingForDualCompletion: Bool = false

    // --- Weather State ---
    var currentWeather: WeatherConditionV2 = .cloudy  // 手动控制的天气变量

    // --- Overlay State ---
    var overlayRepeatCount: Int = 0  // For overlay loops

    // Set state type based on AnimationClipGroupType
    func setStateType(from groupType: AnimationClipGroupType) {
        switch groupType {
        case .pose:
            currentStateType = .pose
        case .transition:
            currentStateType = .transition
        case .other:
            currentStateType = .other
        }
    }
} 
