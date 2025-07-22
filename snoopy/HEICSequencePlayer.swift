//
//  HEICSequencePlayer.swift
//  snoopy
//
//  Created by miuGrey on 2025/01/07.
//

import AVFoundation
import AppKit
import Foundation
import SpriteKit
 
// MARK: - 新的基于 AnimationClipMetadata 的序列播放器

class HEICSpriteSequencePlayer {
    private var textures: [SKTexture] = []
    private var currentIndex: Int = 0
    private var animationTimer: Timer?
    private let frameRate: Double = 24.0  // 24 fps
    private var isPlaying: Bool = false
    private var completion: (() -> Void)?

    weak var targetNode: SKSpriteNode?
    private var sprites: [AnimationSprite] = []
    private var assetFolder: String = ""
    private var fullFolderPath: String = ""

    init() {}

    deinit {
        stop()
    }

    // 加载 AnimationClipMetadata - 异步
    func loadSequence(clip: AnimationClipMetadata, completion: @escaping (Bool) -> Void) {
        debugLog("🎬 HEICSpriteSequencePlayer: 开始异步加载序列 \(clip.assetFolder)")
        self.sprites = clip.phases.first?.sprites ?? []
        self.assetFolder = clip.assetFolder
        self.fullFolderPath = clip.fullFolderPath
        textures.removeAll()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let loadedTextures = self.loadTexturesAsync()
            DispatchQueue.main.async {
                self.textures = loadedTextures
                if loadedTextures.isEmpty {
                    debugLog("❌ HEICSpriteSequencePlayer: 纹理加载失败 \(clip.assetFolder)")
                } else {
                    debugLog("✅ HEICSpriteSequencePlayer: 纹理加载成功 \(clip.assetFolder)，共 \(loadedTextures.count) 帧")
                }
                completion(!loadedTextures.isEmpty)
            }
        }
    }

    // 同步版本
    func loadSequence(clip: AnimationClipMetadata) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        loadSequence(clip: clip) { success in
            result = success
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // 加载所有帧纹理
    private func loadTexturesAsync() -> [SKTexture] {
        var textures: [SKTexture] = []
        for sprite in sprites {
            let baseName = sprite.assetBaseName
            let digitCount = sprite.frameIndexDigitCount
            let startFrame = sprite.customTiming?.start ?? 0
            let endFrame = sprite.customTiming?.end ?? 0
            for frameIndex in startFrame...endFrame {
                let fileName = String(format: "%@_%0*d", baseName, digitCount, frameIndex)
                let resourcePath = (fullFolderPath as NSString).appendingPathComponent(fileName)
                if let url = Bundle.main.url(forResource: resourcePath, withExtension: "heic") ??
                    Bundle(for: type(of: self)).url(forResource: resourcePath, withExtension: "heic") {
                    do {
                        let imageData = try Data(contentsOf: url)
                        if let image = NSImage(data: imageData) {
                            let texture = SKTexture(image: image)
                            texture.filteringMode = .linear
                            textures.append(texture)
                        }
                    } catch {
                        debugLog("❌ HEICSpriteSequencePlayer: 加载帧失败 \(fileName).heic: \(error.localizedDescription)")
                    }
                } else {
                    debugLog("❌ HEICSpriteSequencePlayer: 找不到帧文件 \(resourcePath).heic")
                }
            }
        }
        return textures
    }

    // 播放序列
    func play(on node: SKSpriteNode, completion: (() -> Void)? = nil) {
        guard !textures.isEmpty else {
            debugLog("❌ HEICSpriteSequencePlayer: 无法播放，纹理序列为空")
            completion?()
            return
        }
        self.targetNode = node
        self.completion = completion
        stop()
        currentIndex = 0
        isPlaying = true
        node.texture = textures[0]
        let frameInterval = 1.0 / frameRate
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        debugLog("▶️ HEICSpriteSequencePlayer: 开始播放，共 \(textures.count) 帧，帧率 \(frameRate) fps")
    }

    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false
        debugLog("⏹️ HEICSpriteSequencePlayer: 停止播放")
    }

    func pause() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false
        debugLog("⏸️ HEICSpriteSequencePlayer: 暂停播放")
    }

    func resume() {
        guard !textures.isEmpty && !isPlaying else { return }
        isPlaying = true
        let frameInterval = 1.0 / frameRate
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        debugLog("▶️ HEICSpriteSequencePlayer: 恢复播放")
    }

    func seek(to time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        let frameIndex = Int(seconds * frameRate)
        guard frameIndex >= 0 && frameIndex < textures.count else { return }
        currentIndex = frameIndex
        if let node = targetNode {
            node.texture = textures[currentIndex]
        }
        debugLog("⏭️ HEICSpriteSequencePlayer: 跳转到帧 \(frameIndex) (时间: \(seconds)s)")
    }

    var rate: Float {
        return isPlaying ? 1.0 : 0.0
    }

    var duration: CMTime {
        guard !textures.isEmpty else { return .zero }
        let totalSeconds = Double(textures.count) / frameRate
        return CMTime(seconds: totalSeconds, preferredTimescale: CMTimeScale(frameRate))
    }

    var currentTime: CMTime {
        let currentSeconds = Double(currentIndex) / frameRate
        return CMTime(seconds: currentSeconds, preferredTimescale: CMTimeScale(frameRate))
    }
    
    private func updateFrame() {
        guard isPlaying && !textures.isEmpty else { return }
        if currentIndex >= textures.count {
            stop()
            debugLog("✅ HEICSpriteSequencePlayer: 播放完成")
            completion?()
            return
        }
        if let node = targetNode {
            node.texture = textures[currentIndex]
//            debugLog("🎬 HEICSpriteSequencePlayer: 更新帧 \(currentIndex) (时间: \(currentTime.seconds)s)")
        }
        currentIndex += 1
    }
}



// MARK: - 新的基于 AnimationClipMetadata 的序列播放器

class HEICSpriteSequenceMaskPlayer {
    private var maskTextures: [SKTexture] = []
    private var outlineTextures: [SKTexture] = []
    private var currentIndex: Int = 0
    private var animationTimer: Timer?
    private let frameRate: Double = 24.0  // 24 fps
    private var isPlaying: Bool = false
    private var completion: (() -> Void)?

    private var maskNode: SKSpriteNode?
    private var outlineNode: SKSpriteNode?

    private var clip: AnimationClipMetadata?

    init(maskNode: SKSpriteNode, outlineNode: SKSpriteNode) {
        self.maskNode = maskNode
        self.outlineNode = outlineNode
    }

    deinit {
        stop()
    }

    // 加载 AnimationClipMetadata - 异步
    func loadSequence(clip: AnimationClipMetadata, completion: @escaping (Bool) -> Void) {
        debugLog("🎬 HEICSpriteSequenceMaskPlayer: 开始异步加载序列 \(clip.assetFolder)")
        self.clip = clip
        maskTextures.removeAll()
        outlineTextures.removeAll()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let loadedMaskTextures = self.loadTexturesAsync(spritePlaneType: "mask")
            let loadedOutlineTextures = self.loadTexturesAsync(spritePlaneType: "foregroundEffect")
            DispatchQueue.main.async {
                self.maskTextures = loadedMaskTextures
                self.outlineTextures = loadedOutlineTextures
                if loadedMaskTextures.isEmpty || loadedOutlineTextures.isEmpty {
                    debugLog("❌ HEICSpriteSequenceMaskPlayer: 纹理加载失败 \(clip.assetFolder)")
                } else {
                    debugLog("✅ HEICSpriteSequenceMaskPlayer: 纹理加载成功 \(clip.assetFolder)，共 \(loadedMaskTextures.count) 帧")
                }
                completion(!loadedMaskTextures.isEmpty)
            }
        }
    }

    // 同步版本
    func loadSequence(clip: AnimationClipMetadata) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        loadSequence(clip: clip) { success in
            result = success
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // 加载所有帧纹理
    private func loadTexturesAsync(spritePlaneType: String) -> [SKTexture] {
        var textures: [SKTexture] = []
        for sprite in self.clip?.phases.first?.sprites ?? [] {
            let fullFolderPath = self.clip?.fullFolderPath ?? ""
            if sprite.plane != spritePlaneType {
                continue
            }
            let baseName = sprite.assetBaseName
            let digitCount = sprite.frameIndexDigitCount
            let startFrame = sprite.customTiming?.start ?? 0
            let endFrame = sprite.customTiming?.end ?? 0
            for frameIndex in startFrame...endFrame {
                let fileName = String(format: "%@_%0*d", baseName, digitCount, frameIndex)
                let resourcePath = (fullFolderPath as NSString).appendingPathComponent(fileName)
                if let url = Bundle.main.url(forResource: resourcePath, withExtension: "heic") ??
                    Bundle(for: type(of: self)).url(forResource: resourcePath, withExtension: "heic") {
                    do {
                        let imageData = try Data(contentsOf: url)
                        if let image = NSImage(data: imageData) {
                            let texture = SKTexture(image: image)
                            texture.filteringMode = .linear
                            textures.append(texture)
                        }
                    } catch {
                        debugLog("❌ HEICSpriteSequenceMaskPlayer: 加载帧失败 \(fileName).heic: \(error.localizedDescription)")
                    }
                } else {
                    debugLog("❌ HEICSpriteSequenceMaskPlayer: 找不到帧文件 \(resourcePath).heic")
                }
            }
        }
        return textures
    }

    // 播放序列
    func play(completion: (() -> Void)? = nil) {
        guard !maskTextures.isEmpty && !outlineTextures.isEmpty else {
            debugLog("❌ HEICSpriteSequenceMaskPlayer: 无法播放，纹理序列为空")
            completion?()
            return
        }
        self.completion = completion
        stop()
        currentIndex = 0
        isPlaying = true
        self.maskNode?.texture = maskTextures[0]
        self.outlineNode?.texture = outlineTextures[0]
        let frameInterval = 1.0 / frameRate
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        debugLog("▶️ HEICSpriteSequenceMaskPlayer: 开始播放，共 \(maskTextures.count) 帧，帧率 \(frameRate) fps")
    }

    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false
        debugLog("⏹️ HEICSpriteSequenceMaskPlayer: 停止播放")
    }

    func pause() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false
        debugLog("⏸️ HEICSpriteSequenceMaskPlayer: 暂停播放")
    }

    func resume() {
        guard !maskTextures.isEmpty && !outlineTextures.isEmpty && !isPlaying else { return }
        isPlaying = true
        let frameInterval = 1.0 / frameRate
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        debugLog("▶️ HEICSpriteSequenceMaskPlayer: 恢复播放")
    }

    func seek(to time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        let frameIndex = Int(seconds * frameRate)
        guard frameIndex >= 0 && frameIndex < maskTextures.count else { return }
        currentIndex = frameIndex
        if let node = self.maskNode {
            node.texture = maskTextures[currentIndex]
        }
        if let outlineNode = self.outlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }
        debugLog("⏭️ HEICSpriteSequenceMaskPlayer: 跳转到帧 \(frameIndex) (时间: \(seconds)s)")
    }

    var rate: Float {
        return isPlaying ? 1.0 : 0.0
    }

    var duration: CMTime {
        guard !maskTextures.isEmpty else { return .zero }
        let totalSeconds = Double(maskTextures.count) / frameRate
        return CMTime(seconds: totalSeconds, preferredTimescale: CMTimeScale(frameRate))
    }

    var currentTime: CMTime {
        let currentSeconds = Double(currentIndex) / frameRate
        return CMTime(seconds: currentSeconds, preferredTimescale: CMTimeScale(frameRate))
    }
    
    private func updateFrame() {
        guard isPlaying && !maskTextures.isEmpty && !outlineTextures.isEmpty else { return }
        if currentIndex >= maskTextures.count {
            stop()
            debugLog("✅ HEICSpriteSequenceMaskPlayer: 播放完成")
            completion?()
            return
        }
        if let node = self.maskNode {
            node.texture = maskTextures[currentIndex]
        }
        if let outlineNode = self.outlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }
        currentIndex += 1
    }

    /// 边加载边播放：每一帧mask/outline都并发异步加载，加载完后再显示并进入下一帧，保证帧率稳定
    func playStreaming(clip: AnimationClipMetadata, frameInterval: TimeInterval = 1.0/24.0, completion: (() -> Void)? = nil) {
        self.clip = clip
        maskTextures.removeAll()
        outlineTextures.removeAll()
        currentIndex = 0
        isPlaying = true
        let maskSprite = clip.phases.first?.sprites.first { $0.plane == "mask" }
        let outlineSprite = clip.phases.first?.sprites.first { $0.plane == "foregroundEffect" }
        let frameStart = maskSprite?.customTiming?.start ?? 0
        let frameEnd = maskSprite?.customTiming?.end ?? 0
        let fullFolderPath = clip.fullFolderPath
        let digitCount = maskSprite?.frameIndexDigitCount ?? 6
        let maskBaseName = maskSprite?.assetBaseName ?? ""
        let outlineBaseName = outlineSprite?.assetBaseName ?? ""

        func loadAndShowFrame(frameIdx: Int) {
            guard isPlaying, frameIdx < frameEnd else {
                isPlaying = false
                completion?()
                return
            }
            let start = CACurrentMediaTime()
            let group = DispatchGroup()
            var maskTexture: SKTexture?
            var outlineTexture: SKTexture?
            // mask
            group.enter()
            DispatchQueue.global().async {
                let fileName = String(format: "%@_%0*d", maskBaseName, digitCount, frameIdx)
                let resourcePath = (fullFolderPath as NSString).appendingPathComponent(fileName)
                if let url = Bundle.main.url(forResource: resourcePath, withExtension: "heic") ??
                    Bundle(for: type(of: self)).url(forResource: resourcePath, withExtension: "heic"),
                   let imageData = try? Data(contentsOf: url), let image = NSImage(data: imageData) {
                    maskTexture = SKTexture(image: image)
                    maskTexture?.filteringMode = .linear
                }
                group.leave()
            }
            // outline
            group.enter()
            DispatchQueue.global().async {
                let fileName = String(format: "%@_%0*d", outlineBaseName, digitCount, frameIdx)
                let resourcePath = (fullFolderPath as NSString).appendingPathComponent(fileName)
                if let url = Bundle.main.url(forResource: resourcePath, withExtension: "heic") ??
                    Bundle(for: type(of: self)).url(forResource: resourcePath, withExtension: "heic"),
                   let imageData = try? Data(contentsOf: url), let image = NSImage(data: imageData) {
                    outlineTexture = SKTexture(image: image)
                    outlineTexture?.filteringMode = .linear
                }
                group.leave()
            }
            group.notify(queue: .main) {
                if let maskNode = self.maskNode, let maskTexture = maskTexture {
                    maskNode.texture = maskTexture
                }
                if let outlineNode = self.outlineNode, let outlineTexture = outlineTexture {
                    outlineNode.texture = outlineTexture
                }
                let elapsed = CACurrentMediaTime() - start
                let delay = max(0, frameInterval - elapsed)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    loadAndShowFrame(frameIdx: frameIdx + 1)
                }
            }
        }
        loadAndShowFrame(frameIdx: frameStart)
    }
}
