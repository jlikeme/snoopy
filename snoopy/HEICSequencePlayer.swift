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

class HEICSequencePlayer {
    private var maskTextures: [SKTexture] = []
    private var outlineTextures: [SKTexture] = []
    private var currentIndex: Int = 0
    private var animationTimer: Timer?
    private let frameRate: Double = 24.0  // 24 fps
    private var isPlaying: Bool = false
    private var completion: (() -> Void)?

    weak var targetMaskNode: SKSpriteNode?
    weak var targetOutlineNode: SKSpriteNode?

    init() {}

    deinit {
        stop()
    }

    // 加载HEIC序列 - 异步版本
    func loadSequence(basePattern: String, completion: @escaping (Bool) -> Void) {
        debugLog("🎬 HEICSequencePlayer: 正在异步加载序列 \(basePattern)")

        maskTextures.removeAll()
        outlineTextures.removeAll()

        // 清理 basePattern，移除可能的 _Mask 或 _Outline 后缀
        let cleanBasePattern = cleanBasePattern(basePattern)
        debugLog("🔧 清理后的基础模式: \(cleanBasePattern)")

        // 使用 .utility QoS 级别来避免优先级反转
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            // 加载 mask 序列的图像数据并创建纹理
            let maskTextures = self.loadMaskTexturesAsync(basePattern: cleanBasePattern)

            // 加载 outline 序列的图像数据并创建纹理
            let outlineTextures = self.loadOutlineTexturesAsync(basePattern: cleanBasePattern)

            // 回到主线程更新状态
            DispatchQueue.main.async {
                self.maskTextures = maskTextures
                self.outlineTextures = outlineTextures

                let maskLoaded = !maskTextures.isEmpty
                let outlineLoaded = !outlineTextures.isEmpty

                if maskLoaded {
                    debugLog("✅ HEICSequencePlayer: Mask 序列加载成功，\(maskTextures.count) 帧")
                    if outlineLoaded {
                        debugLog("✅ HEICSequencePlayer: Outline 序列加载成功，\(outlineTextures.count) 帧")
                    } else {
                        debugLog("ℹ️ HEICSequencePlayer: 未找到 Outline 序列，将仅播放 Mask")
                    }
                    completion(true)
                } else {
                    debugLog("❌ HEICSequencePlayer: Mask 序列加载失败")
                    completion(false)
                }
            }
        }
    }

    // 同步版本保持兼容性（内部使用异步实现）
    func loadSequence(basePattern: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        loadSequence(basePattern: basePattern) { success in
            result = success
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // 清理基础模式，移除可能的 _Mask 或 _Outline 后缀
    private func cleanBasePattern(_ pattern: String) -> String {
        if pattern.hasSuffix("_Mask") {
            return String(pattern.dropLast(5))  // 移除 "_Mask"
        } else if pattern.hasSuffix("_Outline") {
            return String(pattern.dropLast(8))  // 移除 "_Outline"
        }
        return pattern
    }

    // 加载 mask 序列纹理 - 异步版本（在后台线程执行，包含纹理创建）
    private func loadMaskTexturesAsync(basePattern: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // 构造 mask 的完整名称
        let maskBasePattern = basePattern + "_Mask"
        var frameIndex = 0

        // 首先尝试加载带帧号的格式
        while true {
            let fileName = String(format: "%@_%06d", maskBasePattern, frameIndex)

            if let url = Bundle(for: type(of: self)).url(
                forResource: fileName, withExtension: "heic")
            {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = .linear
                        textures.append(texture)
                        debugLog("📸 后台加载 mask 纹理: \(fileName).heic")
                    } else {
                        debugLog("❌ 无法从 \(fileName).heic 创建 mask 图像")
                        break
                    }
                } catch {
                    debugLog("❌ 无法从 \(fileName).heic 加载 mask 数据: \(error.localizedDescription)")
                    break
                }
            } else {
                if frameIndex == 0 {
                    debugLog("⚠️ 未找到 mask 帧序列，尝试加载单个文件 \(maskBasePattern).heic")
                    // 尝试加载单个文件
                    if let url = Bundle(for: type(of: self)).url(
                        forResource: maskBasePattern, withExtension: "heic")
                    {
                        do {
                            let imageData = try Data(contentsOf: url)
                            if let image = NSImage(data: imageData) {
                                let texture = SKTexture(image: image)
                                texture.filteringMode = .linear
                                textures.append(texture)
                                debugLog("📸 后台加载单个 mask HEIC文件: \(maskBasePattern).heic")
                            }
                        } catch {
                            debugLog(
                                "❌ 无法加载单个 mask 文件 \(maskBasePattern).heic: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        debugLog("❌ 找不到任何匹配 \(maskBasePattern) 的 mask HEIC文件")
                    }
                } else {
                    debugLog("✅ Mask 纹理后台加载完成，共 \(frameIndex) 帧")
                }
                break
            }

            frameIndex += 1
        }

        return textures
    }

    // 加载 outline 序列纹理 - 异步版本（在后台线程执行，包含纹理创建）
    private func loadOutlineTexturesAsync(basePattern: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // 构造 outline 的 basePattern
        let outlineBasePattern = basePattern + "_Outline"
        var frameIndex = 0

        // 尝试加载带帧号的格式
        while true {
            let fileName = String(format: "%@_%06d", outlineBasePattern, frameIndex)

            if let url = Bundle(for: type(of: self)).url(
                forResource: fileName, withExtension: "heic")
            {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = .linear
                        textures.append(texture)
                        debugLog("📸 后台加载 outline 纹理: \(fileName).heic")
                    } else {
                        debugLog("❌ 无法从 \(fileName).heic 创建 outline 图像")
                        break
                    }
                } catch {
                    debugLog("❌ 无法从 \(fileName).heic 加载 outline 数据: \(error.localizedDescription)")
                    break
                }
            } else {
                if frameIndex == 0 {
                    debugLog("⚠️ 未找到 outline 帧序列，尝试加载单个文件 \(outlineBasePattern).heic")
                    // 尝试加载单个文件
                    if let url = Bundle(for: type(of: self)).url(
                        forResource: outlineBasePattern, withExtension: "heic")
                    {
                        do {
                            let imageData = try Data(contentsOf: url)
                            if let image = NSImage(data: imageData) {
                                let texture = SKTexture(image: image)
                                texture.filteringMode = .linear
                                textures.append(texture)
                                debugLog("📸 后台加载单个 outline HEIC文件: \(outlineBasePattern).heic")
                            }
                        } catch {
                            debugLog(
                                "❌ 无法加载单个 outline 文件 \(outlineBasePattern).heic: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        debugLog("ℹ️ 找不到任何匹配 \(outlineBasePattern) 的 outline HEIC文件")
                    }
                } else {
                    debugLog("✅ Outline 纹理后台加载完成，共 \(frameIndex) 帧")
                }
                break
            }

            frameIndex += 1
        }

        return textures
    }

    // 开始播放序列（双层播放：mask + outline）
    func playDual(
        maskNode: SKSpriteNode, outlineNode: SKSpriteNode, completion: (() -> Void)? = nil
    ) {
        guard !maskTextures.isEmpty else {
            debugLog("❌ HEICSequencePlayer: 无法播放，mask 序列为空")
            completion?()
            return
        }

        self.targetMaskNode = maskNode
        self.targetOutlineNode = outlineNode
        self.completion = completion

        stop()  // 停止任何现有播放

        currentIndex = 0
        isPlaying = true

        // 设置第一帧
        maskNode.texture = maskTextures[0]

        // 设置 outline 第一帧
        if !outlineTextures.isEmpty {
            outlineNode.texture = outlineTextures[0]
            outlineNode.isHidden = false
            debugLog("✅ Outline 节点显示并设置第一帧")
        } else {
            outlineNode.isHidden = true
            debugLog("ℹ️ 没有 outline 纹理，隐藏 outline 节点")
        }

        let frameInterval = 1.0 / frameRate

        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) {
            [weak self] _ in
            self?.updateFrame()
        }

        debugLog("🎬 HEICSequencePlayer: 开始双层播放")
        debugLog("  - Mask: \(maskTextures.count) 帧")
        debugLog("  - Outline: \(outlineTextures.count) 帧")
        debugLog("  - 帧率: \(frameRate) fps")
    }

    // 停止播放
    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false

        debugLog("⏹️ HEICSequencePlayer: 停止播放")
    }

    // 暂停播放
    func pause() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false

        debugLog("⏸️ HEICSequencePlayer: 暂停播放")
    }

    // 恢复播放
    func resume() {
        guard !maskTextures.isEmpty && !isPlaying else { return }

        isPlaying = true
        let frameInterval = 1.0 / frameRate

        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) {
            [weak self] _ in
            self?.updateFrame()
        }

        debugLog("▶️ HEICSequencePlayer: 恢复播放")
    }

    // 跳转到指定时间
    func seek(to time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        let frameIndex = Int(seconds * frameRate)

        guard frameIndex >= 0 && frameIndex < maskTextures.count else { return }

        currentIndex = frameIndex

        // 更新当前帧
        if let maskNode = targetMaskNode {
            maskNode.texture = maskTextures[currentIndex]
        }

        // 更新 outline 节点
        if let outlineNode = targetOutlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }

        debugLog("⏭️ HEICSequencePlayer: 跳转到帧 \(frameIndex) (时间: \(seconds)s)")
    }

    // 获取当前播放状态
    var rate: Float {
        return isPlaying ? 1.0 : 0.0
    }

    // 获取总时长
    var duration: CMTime {
        guard !maskTextures.isEmpty else { return .zero }
        let totalSeconds = Double(maskTextures.count) / frameRate
        return CMTime(seconds: totalSeconds, preferredTimescale: CMTimeScale(frameRate))
    }

    // 获取当前时间
    var currentTime: CMTime {
        let currentSeconds = Double(currentIndex) / frameRate
        return CMTime(seconds: currentSeconds, preferredTimescale: CMTimeScale(frameRate))
    }

    // 私有方法：更新帧（双层播放）
    private func updateFrame() {
        guard isPlaying && !maskTextures.isEmpty else { return }

        // 检查是否播放完成
        if currentIndex >= maskTextures.count {
            // 播放完成
            stop()
            completion?()
            return
        }

        // 更新 mask 节点纹理
        if let maskNode = targetMaskNode {
            maskNode.texture = maskTextures[currentIndex]
        }

        // 更新 outline 节点纹理
        if let outlineNode = targetOutlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }

        currentIndex += 1
    }
}

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

    private func logWithTime(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        debugLog("[\(timestamp)] " + message)
    }

    // 加载 AnimationClipMetadata - 异步
    func loadSequence(clip: AnimationClipMetadata, completion: @escaping (Bool) -> Void) {
        logWithTime("🎬 HEICSpriteSequencePlayer: 开始异步加载序列 \(clip.assetFolder)")
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
                    self.logWithTime("❌ HEICSpriteSequencePlayer: 纹理加载失败 \(clip.assetFolder)")
                } else {
                    self.logWithTime("✅ HEICSpriteSequencePlayer: 纹理加载成功 \(clip.assetFolder)，共 \(loadedTextures.count) 帧")
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
