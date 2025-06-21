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

    // 加载HEIC序列
    func loadSequence(basePattern: String) -> Bool {
        print("🎬 HEICSequencePlayer: 正在加载序列 \(basePattern)")

        maskTextures.removeAll()
        outlineTextures.removeAll()

        // 清理 basePattern，移除可能的 _Mask 或 _Outline 后缀
        let cleanBasePattern = cleanBasePattern(basePattern)
        print("🔧 清理后的基础模式: \(cleanBasePattern)")

        // 首先加载 mask 序列
        let maskLoaded = loadMaskSequence(basePattern: cleanBasePattern)

        // 然后尝试加载 outline 序列
        let outlineLoaded = loadOutlineSequence(basePattern: cleanBasePattern)

        if maskLoaded {
            print("✅ HEICSequencePlayer: Mask 序列加载成功，\(maskTextures.count) 帧")
            if outlineLoaded {
                print("✅ HEICSequencePlayer: Outline 序列加载成功，\(outlineTextures.count) 帧")
            } else {
                print("ℹ️ HEICSequencePlayer: 未找到 Outline 序列，将仅播放 Mask")
            }
            return true
        } else {
            print("❌ HEICSequencePlayer: Mask 序列加载失败")
            return false
        }
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

    // 加载 mask 序列
    private func loadMaskSequence(basePattern: String) -> Bool {
        // 构造 mask 的完整名称
        // 例如：101_TM001_Hide -> 101_TM001_Hide_Mask
        let maskBasePattern = basePattern + "_Mask"

        var frameIndex = 0
        var loadedAnyFrames = false

        // 首先尝试加载带帧号的格式
        while true {
            let fileName = String(format: "%@_%06d", maskBasePattern, frameIndex)

            if let url = Bundle.main.url(forResource: fileName, withExtension: "heic") {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = .linear
                        maskTextures.append(texture)
                        loadedAnyFrames = true
                        print("📸 加载 mask 帧: \(fileName).heic")
                    } else {
                        print("❌ 无法从 \(fileName).heic 创建 mask 图像")
                        break
                    }
                } catch {
                    print("❌ 无法从 \(fileName).heic 加载 mask 数据: \(error.localizedDescription)")
                    break
                }
            } else {
                if frameIndex == 0 {
                    print("⚠️ 未找到 mask 帧序列，尝试加载单个文件 \(maskBasePattern).heic")
                    // 尝试加载单个文件
                    if let url = Bundle.main.url(
                        forResource: maskBasePattern, withExtension: "heic")
                    {
                        do {
                            let imageData = try Data(contentsOf: url)
                            if let image = NSImage(data: imageData) {
                                let texture = SKTexture(image: image)
                                texture.filteringMode = .linear
                                maskTextures.append(texture)
                                loadedAnyFrames = true
                                print("📸 加载单个 mask HEIC文件: \(maskBasePattern).heic")
                            }
                        } catch {
                            print(
                                "❌ 无法加载单个 mask 文件 \(maskBasePattern).heic: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        print("❌ 找不到任何匹配 \(maskBasePattern) 的 mask HEIC文件")
                    }
                } else {
                    print("✅ Mask 序列加载完成，共 \(frameIndex) 帧")
                }
                break
            }

            frameIndex += 1
        }

        return loadedAnyFrames
    }

    // 加载 outline 序列
    private func loadOutlineSequence(basePattern: String) -> Bool {
        // 构造 outline 的 basePattern
        // 例如：101_TM001_Hide -> 101_TM001_Hide_Outline
        let outlineBasePattern = basePattern + "_Outline"

        var frameIndex = 0
        var loadedAnyFrames = false

        // 尝试加载带帧号的格式
        while true {
            let fileName = String(format: "%@_%06d", outlineBasePattern, frameIndex)

            if let url = Bundle.main.url(forResource: fileName, withExtension: "heic") {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = .linear
                        outlineTextures.append(texture)
                        loadedAnyFrames = true
                        print("📸 加载 outline 帧: \(fileName).heic")
                    } else {
                        print("❌ 无法从 \(fileName).heic 创建 outline 图像")
                        break
                    }
                } catch {
                    print("❌ 无法从 \(fileName).heic 加载 outline 数据: \(error.localizedDescription)")
                    break
                }
            } else {
                if frameIndex == 0 {
                    print("⚠️ 未找到 outline 帧序列，尝试加载单个文件 \(outlineBasePattern).heic")
                    // 尝试加载单个文件
                    if let url = Bundle.main.url(
                        forResource: outlineBasePattern, withExtension: "heic")
                    {
                        do {
                            let imageData = try Data(contentsOf: url)
                            if let image = NSImage(data: imageData) {
                                let texture = SKTexture(image: image)
                                texture.filteringMode = .linear
                                outlineTextures.append(texture)
                                loadedAnyFrames = true
                                print("📸 加载单个 outline HEIC文件: \(outlineBasePattern).heic")
                            }
                        } catch {
                            print(
                                "❌ 无法加载单个 outline 文件 \(outlineBasePattern).heic: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        print("ℹ️ 找不到任何匹配 \(outlineBasePattern) 的 outline HEIC文件")
                    }
                } else {
                    print("✅ Outline 序列加载完成，共 \(frameIndex) 帧")
                }
                break
            }

            frameIndex += 1
        }

        return loadedAnyFrames
    }

    // 开始播放序列（兼容性方法，仅播放 mask）
    func play(on node: SKSpriteNode, completion: (() -> Void)? = nil) {
        guard !maskTextures.isEmpty else {
            print("❌ HEICSequencePlayer: 无法播放，序列为空")
            completion?()
            return
        }

        self.targetMaskNode = node
        self.targetOutlineNode = nil
        self.completion = completion

        stop()  // 停止任何现有播放

        currentIndex = 0
        isPlaying = true

        // 设置第一帧
        if !maskTextures.isEmpty {
            node.texture = maskTextures[0]
        }

        let frameInterval = 1.0 / frameRate

        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) {
            [weak self] _ in
            self?.updateFrame()
        }

        print("🎬 HEICSequencePlayer: 开始播放 \(maskTextures.count) 帧，帧率 \(frameRate) fps")
    }

    // 开始播放序列（支持双层）
    func playDual(
        maskNode: SKSpriteNode, outlineNode: SKSpriteNode? = nil, completion: (() -> Void)? = nil
    ) {
        guard !maskTextures.isEmpty else {
            print("❌ HEICSequencePlayer: 无法播放，mask 序列为空")
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

        // 如果有 outline 节点且有 outline 纹理，设置 outline 第一帧
        if let outlineNode = outlineNode, !outlineTextures.isEmpty {
            outlineNode.texture = outlineTextures[0]
            outlineNode.isHidden = false
            print("✅ Outline 节点显示并设置第一帧")
        } else if let outlineNode = outlineNode {
            outlineNode.isHidden = true
            print("ℹ️ 没有 outline 纹理，隐藏 outline 节点")
        }

        let frameInterval = 1.0 / frameRate

        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) {
            [weak self] _ in
            self?.updateDualFrame()
        }

        print("🎬 HEICSequencePlayer: 开始双层播放")
        print("  - Mask: \(maskTextures.count) 帧")
        print("  - Outline: \(outlineTextures.count) 帧")
        print("  - 帧率: \(frameRate) fps")
    }

    // 停止播放
    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false

        print("⏹️ HEICSequencePlayer: 停止播放")
    }

    // 暂停播放
    func pause() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false

        print("⏸️ HEICSequencePlayer: 暂停播放")
    }

    // 恢复播放
    func resume() {
        guard !maskTextures.isEmpty && !isPlaying else { return }

        isPlaying = true
        let frameInterval = 1.0 / frameRate

        // 根据是否有 outline 节点使用不同的更新方法
        if targetOutlineNode != nil {
            animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) {
                [weak self] _ in
                self?.updateDualFrame()
            }
        } else {
            animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) {
                [weak self] _ in
                self?.updateFrame()
            }
        }

        print("▶️ HEICSequencePlayer: 恢复播放")
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

        // 如果有 outline 节点且有纹理，也更新 outline
        if let outlineNode = targetOutlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }

        print("⏭️ HEICSequencePlayer: 跳转到帧 \(frameIndex) (时间: \(seconds)s)")
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

    // 私有方法：更新帧（兼容性方法，仅更新 mask）
    private func updateFrame() {
        guard isPlaying && !maskTextures.isEmpty else { return }

        // 检查是否播放完成
        if currentIndex >= maskTextures.count {
            // 播放完成
            stop()
            completion?()
            return
        }

        // 更新节点纹理
        if let targetNode = targetMaskNode {
            targetNode.texture = maskTextures[currentIndex]
        }

        currentIndex += 1
    }

    // 私有方法：更新双层帧
    private func updateDualFrame() {
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

        // 更新 outline 节点纹理（如果存在且有纹理）
        if let outlineNode = targetOutlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }

        currentIndex += 1
    }
}
