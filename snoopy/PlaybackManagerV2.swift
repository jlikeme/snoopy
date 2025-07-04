import AVFoundation
import Foundation
// Import all required types
import SpriteKit

// MARK: - Import project types
// These are all in the snoopy module
// (If using modules, use @testable import snoopy)

// If not using modules, just ensure the files are in the same target
// and available to the compiler.

// Import debugLog
// debugLog is defined in ErrorLevel.swift
// No explicit import needed if in same target

/// PlaybackManagerV2: Handles playback using AssetClipLoader, SequenceManagerV2, and StateManagerV2
class PlaybackManagerV2 {
    private let stateManager: StateManagerV2
    private let playerManager: PlayerManager
    private let sceneManager: SceneManager
    private let transitionManager: TransitionManager
    private var sequenceManager: SequenceManagerV2!
    private var overlayManager: OverlayManager!  // Will be set after initialization

    init(stateManager: StateManagerV2, playerManager: PlayerManager, sceneManager: SceneManager, transitionManager: TransitionManager) {
        self.stateManager = stateManager
        self.playerManager = playerManager
        self.sceneManager = sceneManager
        self.transitionManager = transitionManager
        setupNotifications()
    }

    func setSequenceManager(_ sequenceManager: SequenceManagerV2) {
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

    /// Start playback from a random base pose
    func startInitialPlayback() {
        debugLog("[PlaybackManagerV2] Setting up initial state...")
        sequenceManager.reset()
        guard let clips = sequenceManager.nextStep() else {
            debugLog("[PlaybackManagerV2] Error: No valid initial sequence found.")
            return
        }
        
        stateManager.currentClipsQueue = clips
        stateManager.currentClipIndex = 0
        stateManager.setStateType(from: clips.first!.clipType.groupType)
        playNextClipInQueue()
    }

    /// Play the next clip in the queue
    func playNextClipInQueue() {
        guard stateManager.currentClipIndex < stateManager.currentClipsQueue.count else {
            debugLog("[PlaybackManagerV2] Queue finished. Generating next sequence...")
            handleEndOfQueue()
            return
        }
        let clipToPlay = stateManager.currentClipsQueue[stateManager.currentClipIndex]
        debugLog("[PlaybackManagerV2] Playing clip (\(stateManager.currentClipIndex + 1)/\(stateManager.currentClipsQueue.count)): \(clipToPlay.assetFolder) (\(clipToPlay.clipType))")
        stateManager.setStateType(from: clipToPlay.clipType.groupType)

        // 判断spriteType
        let spriteType = clipToPlay.phases.first?.sprites.first?.spriteType
        if spriteType == "frameSequence" {
            debugLog("[PlaybackManagerV2] Detected frameSequence, using HEICSpriteSequencePlayer.")
            // 停止AVPlayer
            playerManager.queuePlayer.pause()
            playerManager.queuePlayer.removeAllItems()
            // 停止上一个HEICSpriteSequencePlayer
            
            guard let videoNode = sceneManager.heicVideoNode else {
                debugLog("[PlaybackManagerV2] Error: No SKSpriteNode available for frameSequence playback.")
                advanceAndPlay()
                return
            }
            playerManager.heicSequencePlayer?.loadSequence(clip: clipToPlay) { success in
                if success {
                    self.playerManager.heicSequencePlayer?.play(on: videoNode) { [weak self] in
                        self?.advanceAndPlay()
                    }
                    self.playerManager.heicSequencePlayer?.targetNode?.isHidden = false
                    self.sceneManager.videoNode?.isHidden = true
                } else {
                    debugLog("[PlaybackManagerV2] Error: Failed to load frameSequence textures for \(clipToPlay.assetFolder)")
                    self.advanceAndPlay()
                }
            }
            return
        } else if spriteType == "video" {
            debugLog("[PlaybackManagerV2] Detected video, using AVPlayer.")
            
            // 原有 AVPlayer 方式
            let url = urlForClip(clipToPlay)
            guard let videoURL = url else {
                debugLog("[PlaybackManagerV2] Error: Video file not found for \(clipToPlay.assetFolder)")
                advanceAndPlay()
                return
            }
            let newItem = AVPlayerItem(url: videoURL)
            playerManager.playerItem = newItem
            playerManager.queuePlayer.removeAllItems()
            playerManager.queuePlayer.insert(newItem, after: nil)
            playerManager.queuePlayer.play()
            // 创建定时器
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] timer in
                if let self = self {
                    self.playerManager.heicSequencePlayer?.targetNode?.isHidden = true
                    self.sceneManager.videoNode?.isHidden = false
                }
            }
            return
        } else {
            debugLog("[PlaybackManagerV2] Unknown spriteType: \(spriteType ?? "nil") for \(clipToPlay.assetFolder), skipping.")
            advanceAndPlay()
            return
        }
    }

    /// Handle AVPlayerItemDidPlayToEndTime notification
    @objc func playerItemDidReachEnd(_ notification: Notification) {
        guard let finishedItem = notification.object as? AVPlayerItem else {
            debugLog("[PlaybackManagerV2] Notification object is not AVPlayerItem. Ignored.")
            return
        }
        guard finishedItem == playerManager.playerItem else {
            debugLog("[PlaybackManagerV2] Notification for unexpected player item. Ignored.")
            return
        }
        debugLog("[PlaybackManagerV2] Finished playing item. Advancing queue...")
        advanceAndPlay()
    }

    /// Helper: Advance the queue and play next
    private func advanceAndPlay() {
        stateManager.currentClipIndex += 1
        playNextClipInQueue()
    }

    /// Helper: When queue ends, generate next sequence
    private func handleEndOfQueue() {
        debugLog("[PlaybackManagerV2] Generating next pose/transition/pose sequence...")
        if let clips = sequenceManager.nextStep() {
            stateManager.currentClipsQueue = clips
            stateManager.currentClipIndex = 0
            playNextClipInQueue()
        } else {
            debugLog("[PlaybackManagerV2] No further sequence available. Playback stopped.")
        }
    }

    /// Helper: Get file URL for AnimationClipMetadata
    private func urlForClip(_ clip: AnimationClipMetadata) -> URL? {
        // 获取 Resources 目录路径
        guard let resourcesPath = Bundle(for: type(of: self)).resourcePath else { return nil }
        
        // 构建完整路径：resourcePath + clip.fullFolderPath
        let fullPath = (resourcesPath as NSString).appendingPathComponent(clip.fullFolderPath)

        let filePath = (fullPath as NSString).appendingPathComponent(clip.assetBaseName + ".mov")

        if FileManager.default.fileExists(atPath: filePath) {
            return URL(fileURLWithPath: filePath)
        }
        return nil

    }
}
