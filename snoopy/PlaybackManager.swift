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

/// PlaybackManager: Handles playback using AssetClipLoader, SequenceManagerV2, and StateManagerV2
class PlaybackManager {
    private let stateManager: StateManager
    private let playerManager: PlayerManager
    private let sceneManager: SceneManager
    private var sequenceManager: SequenceManager!
    private var asVideoNodeNeedHide = false
    private var currentMaskPlayer: HEICSpriteSequenceMaskPlayer?

    init(stateManager: StateManager, playerManager: PlayerManager, sceneManager: SceneManager) {
        self.stateManager = stateManager
        self.playerManager = playerManager
        self.sceneManager = sceneManager
        setupNotifications()
    }

    func setSequenceManager(_ sequenceManager: SequenceManager) {
        self.sequenceManager = sequenceManager
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

        stateManager.setStateType(from: stateManager.currentClipsQueue.first!.groupType)
        playNextClipInQueue()
    }

    /// Play the next clip in the queue
    func playNextClipInQueue() {
        guard stateManager.currentClipsQueue.count > 0 else {
            debugLog("[PlaybackManagerV2] Queue finished. Generating next sequence...")
            handleEndOfQueue()
            return
        }
        let clipToPlay = stateManager.currentClipsQueue.removeFirst()
        debugLog("[PlaybackManagerV2] Playing clip: \(clipToPlay.assetFolder) (\(clipToPlay.clipType))")
        stateManager.setStateType(from: clipToPlay.groupType)

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

            // 播放activeScene时，延迟1s，更新背景，activeScene肯定是个视频
            switch clipToPlay.clipType {
            case .transitionMask:
                debugLog("[PlaybackManagerV2] Masking sequence loaded for \(clipToPlay.assetFolder)")
                self.sceneManager.assignMaskNode()
                let maskPlayer = HEICSpriteSequenceMaskPlayer(maskNode: sceneManager.tmMaskSpriteNode!, outlineNode: sceneManager.tmOutlineSpriteNode!)
                self.currentMaskPlayer = maskPlayer
                maskPlayer.playStreaming(clip: clipToPlay) { [weak self] in
                    debugLog("[PlaybackManagerV2] Masking sequence completed for \(clipToPlay.assetFolder)")
                    self?.sceneManager.unassignMaskNode()
                    if self?.asVideoNodeNeedHide == true {
                        // Outline播放完成后，隐藏AS视频节点
                        self?.sceneManager.asVideoNode?.isHidden = true
                    }
                    self?.currentMaskPlayer = nil
                    // 不执行self.advanceAndPlay()，但最好是执行sequenceManager.nextStepAsync()
                    self?.sequenceManager.nextStepAsync()
                }
                // 立马播放下一个clip
                self.advanceAndPlay()

                debugLog("[PlaybackManagerV2] Masking sequence started for \(clipToPlay.assetFolder)")

            case .idleSceneVisitor:
                let newItem = AVPlayerItem(url: videoURL)
                playerManager.overlayPlayerItem = newItem
                playerManager.overlayPlayer.removeAllItems()
                playerManager.overlayPlayer.insert(newItem, after: nil)
                playerManager.overlayPlayer.play()
                // 创建定时器
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] timer in
                    if let self = self {
                        self.sceneManager.overlayNode?.isHidden = false
                    }
                }

                // 立马播放下一个clip
                self.advanceAndPlay()

            case .activeScene:

                let newItem = AVPlayerItem(url: videoURL)
                playerManager.asPlayerItem = newItem
                playerManager.asPlayer.replaceCurrentItem(with:newItem)
                playerManager.asPlayer.play()
                self.asVideoNodeNeedHide = false
                // 创建定时器
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] timer in
                    if let self = self {
                        self.sceneManager.asVideoNode?.isHidden = false
                    }
                }
                
                Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] timer in
                    if let self = self {
                        self.sceneManager.updateBackgrounds()
                    }
                }
            default:
                let newItem = AVPlayerItem(url: videoURL)
                playerManager.playerItem = newItem
                playerManager.queuePlayer.removeAllItems()
                playerManager.queuePlayer.insert(newItem, after: nil)
                playerManager.queuePlayer.play()
                // 创建定时器
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] timer in
                    if let self = self {
                        self.sceneManager.heicVideoNode?.isHidden = true
                        self.sceneManager.videoNode?.isHidden = false
                    }
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
        
        if finishedItem == playerManager.asPlayerItem {
            debugLog("[PlaybackManagerV2] ✅ AS/SS播放器内容播放完成")
            // 移除这个特定的通知观察者
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: finishedItem)
            self.asVideoNodeNeedHide = true // 标记需要隐藏AS视频节点，下一次outline播放完后将会隐藏
            advanceAndPlay()
            return
        } else if finishedItem == playerManager.outlinePlayerItem {
            debugLog("[PlaybackManagerV2] ✅ Outline播放器内容播放完成")
            // 移除这个特定的通知观察者
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: finishedItem)
            self.sceneManager.unassignMaskNode()
            if self.asVideoNodeNeedHide {
                // Outline播放完成后，隐藏AS视频节点
                self.sceneManager.asVideoNode?.isHidden = true
            }
            return
        } else if finishedItem == playerManager.overlayPlayerItem {
            debugLog("[PlaybackManagerV2] ✅ Overlay播放器内容播放完成")
            // 移除这个特定的通知观察者
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: finishedItem)
            self.sceneManager.overlayNode?.isHidden = true
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
        sequenceManager.nextStepAsync()
        playNextClipInQueue()
    }

    /// Helper: When queue ends, generate next sequence
    private func handleEndOfQueue() {
        debugLog("[PlaybackManagerV2] Generating next pose/transition/pose sequence...")
        sequenceManager.reset()
        playNextClipInQueue()
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

    /// Helper: Get file URL for AnimationClipMetadata
    private func urlForMaskClip(_ clip: AnimationClipMetadata) -> (URL?, URL?) {
        // 获取 Resources 目录路径
        guard let resourcesPath = Bundle(for: type(of: self)).resourcePath else { return (nil, nil) }
        
        // 构建完整路径：resourcePath + clip.fullFolderPath
        let fullPath = (resourcesPath as NSString).appendingPathComponent(clip.fullFolderPath)

        var maskURL: URL?
        var outlineURL: URL?
        // 遍历clip下的所有spirtes
        for sprite in clip.phases.first?.sprites ?? [] {
                
            let filePath = (fullPath as NSString).appendingPathComponent(sprite.assetBaseName + ".mov")
            if FileManager.default.fileExists(atPath: filePath) {
                if sprite.plane == "mask" {
                    maskURL = URL(fileURLWithPath: filePath)
                } else if sprite.plane == "foregroundEffect" {
                    outlineURL = URL(fileURLWithPath: filePath)
                }
            }
        }
        return (maskURL, outlineURL)

    }
}
