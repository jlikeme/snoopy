//
//  ContentView.swift
//  SKTest
//
//  Created by miuGrey on 2025/5/7.
//

import AVFoundation
import AppKit
import SpriteKit
import SwiftUI

// MaskDemoScene class to manage the masking demo
class MaskDemoScene: SKScene {
    private var asPlayer: AVPlayer?

    private var asVideoNode: SKVideoNode?  // Plays the AS video, content to be masked
    private var tmHideSpriteNode: SKSpriteNode?  // Displays HEIC image sequence as mask
    private var tmHideOutlineNode: SKSpriteNode?  // Displays HEIC outline sequence on top
    private var halftoneNode: SKSpriteNode?  // Background, visible through transparent parts of the mask
    private var cropNode: SKCropNode?  // Crops the AS video based on HEIC mask

    private var asPlayerItem: AVPlayerItem?

    // HEIC image sequence properties
    private var heicMaskTextures: [SKTexture] = []
    private var heicOutlineTextures: [SKTexture] = []
    private var currentHEICIndex: Int = 0
    private var heicAnimationTimer: Timer?
    private let heicFrameRate: Double = 24.0  // 24 fps

    // Use Bundle resources instead of absolute paths
    private var asVideoURL: URL? {
        Bundle.main.url(forResource: "101_AS002", withExtension: "mov")
    }

    override func didMove(to view: SKView) {
        size = view.bounds.size
        backgroundColor = .clear  // Scene background

        loadHEICSequence()  // 先加载 HEIC 序列
        setupNodes()  // 然后设置节点
        setupPlayers()
        startPlaybackLogic()
    }

    private func loadHEICSequence() {
        print("🖼️ Loading HEIC image sequences from Bundle...")

        heicMaskTextures.removeAll()
        heicOutlineTextures.removeAll()

        // Load mask sequence: 101_TM001_Hide_Mask_XXXXXX.heic
        let maskBaseName = "101_TM001_Hide_Mask_"
        var frameIndex = 0

        while true {
            let fileName = String(format: "%@%06d", maskBaseName, frameIndex)

            if let url = Bundle.main.url(forResource: fileName, withExtension: "heic") {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = SKTextureFilteringMode.linear
                        heicMaskTextures.append(texture)
                    } else {
                        print("❌ Failed to create mask image from: \(fileName).heic")
                        break
                    }
                } catch {
                    print(
                        "❌ Failed to load mask data from: \(fileName).heic - \(error.localizedDescription)"
                    )
                    break
                }
            } else {
                // No more mask files found, stop loading
                break
            }

            frameIndex += 1
        }

        print("🎬 Successfully loaded \(heicMaskTextures.count) HEIC mask textures")

        // Load outline sequence: 101_TM001_Hide_Outline_XXXXXX.heic
        let outlineBaseName = "101_TM001_Hide_Outline_"
        frameIndex = 0

        while true {
            let fileName = String(format: "%@%06d", outlineBaseName, frameIndex)

            if let url = Bundle.main.url(forResource: fileName, withExtension: "heic") {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = SKTextureFilteringMode.linear
                        heicOutlineTextures.append(texture)
                    } else {
                        print("❌ Failed to create outline image from: \(fileName).heic")
                        break
                    }
                } catch {
                    print(
                        "❌ Failed to load outline data from: \(fileName).heic - \(error.localizedDescription)"
                    )
                    break
                }
            } else {
                // No more outline files found, stop loading
                break
            }

            frameIndex += 1
        }

        print("🎬 Successfully loaded \(heicOutlineTextures.count) HEIC outline textures")

        if heicMaskTextures.count > 0 {
            print(
                "📊 Mask frame range: 000000 to \(String(format: "%06d", heicMaskTextures.count - 1))"
            )
        }

        if heicOutlineTextures.count > 0 {
            print(
                "📊 Outline frame range: 000000 to \(String(format: "%06d", heicOutlineTextures.count - 1))"
            )
        }

        if heicMaskTextures.isEmpty {
            print(
                "❌ No HEIC mask textures loaded. Make sure the mask HEIC files are added to the app bundle."
            )
        }

        if heicOutlineTextures.isEmpty {
            print(
                "❌ No HEIC outline textures loaded. Make sure the outline HEIC files are added to the app bundle."
            )
        }
    }

    private func setupNodes() {
        // 1. Halftone Node (底层背景) - 直接添加到场景
        halftoneNode = SKSpriteNode(color: .systemBlue, size: size)
        halftoneNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        halftoneNode?.zPosition = 0
        if let halftoneNode {
            addChild(halftoneNode)
        }

        // 初始化 AS 播放器
        asPlayer = AVPlayer()

        // 创建 AS 视频节点
        asVideoNode = SKVideoNode(avPlayer: asPlayer!)
        asVideoNode?.size = size
        asVideoNode?.position = .zero

        // 创建 HEIC mask 图片序列节点
        if !heicMaskTextures.isEmpty {
            tmHideSpriteNode = SKSpriteNode(texture: heicMaskTextures[0])
            tmHideSpriteNode?.size = size
            tmHideSpriteNode?.position = .zero
        } else {
            // 如果 HEIC mask 序列还没加载，创建一个空的节点
            tmHideSpriteNode = SKSpriteNode(color: .clear, size: size)
            tmHideSpriteNode?.position = .zero
        }

        // 创建裁剪节点 (CropNode) - 只裁剪 AS 视频
        cropNode = SKCropNode()
        cropNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cropNode?.zPosition = 1

        // 将 AS 视频作为裁剪内容
        if let asVideoNode {
            cropNode?.addChild(asVideoNode)
        }

        // 将 HEIC mask 图片序列节点作为裁剪遮罩
        cropNode?.maskNode = tmHideSpriteNode

        // 将裁剪节点添加到场景中
        if let cropNode {
            addChild(cropNode)
        }

        // 创建 HEIC outline 图片序列节点 (在最上层)
        if !heicOutlineTextures.isEmpty {
            tmHideOutlineNode = SKSpriteNode(texture: heicOutlineTextures[0])
            tmHideOutlineNode?.size = size
            tmHideOutlineNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
            tmHideOutlineNode?.zPosition = 2  // 在所有内容之上

            // 设置混合模式以确保 outline 可见
            tmHideOutlineNode?.blendMode = .alpha

            // 添加一个轻微的半透明红色背景来测试 outline 节点是否存在
            tmHideOutlineNode?.color = .red
            tmHideOutlineNode?.colorBlendFactor = 0.1

            if let tmHideOutlineNode {
                addChild(tmHideOutlineNode)
                print("✅ TM_Hide_Outline 节点已创建并添加到场景")
                print("  - Position: \(tmHideOutlineNode.position)")
                print("  - Size: \(tmHideOutlineNode.size)")
                print("  - zPosition: \(tmHideOutlineNode.zPosition)")
                print("  - Alpha: \(tmHideOutlineNode.alpha)")
            }
        } else {
            print("❌ 无法创建 TM_Hide_Outline 节点 - heicOutlineTextures 为空")
        }

        print("✅ 节点设置完成：")
        print("  - Halftone (蓝色背景) 在 zPosition=0")
        print("  - CropNode (AS 被 HEIC mask 遮罩) 在 zPosition=1")
        print("  - TM_Hide_Outline (HEIC outline 序列) 在 zPosition=2")
        print("🔍 预期效果：HEIC mask 不透明区域显示 AS，透明区域显示 halftone，outline 显示在最上层")
    }

    private func setupPlayers() {
        // Check if AS video file exists in bundle
        guard let asURL = asVideoURL else {
            print("❌ AS video file not found in bundle")
            return
        }

        print("✅ AS Video URL: \(asURL)")

        // AS Player Setup
        asPlayerItem = AVPlayerItem(url: asURL)
        asPlayer?.replaceCurrentItem(with: asPlayerItem)

        // Monitor AS player status
        asPlayerItem?.addObserver(
            self, forKeyPath: "status", options: [.new, .initial], context: nil)

        // Notification for when the AS video finishes playing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(asVideoDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: asPlayerItem)
    }

    private func startPlaybackLogic() {
        // Wait a bit for video loading, then check status
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkPlayersAndStart()
        }
    }

    private func checkPlayersAndStart() {
        print("AS Player Status: \(asPlayerItem?.status.rawValue ?? -1)")

        // Only start if AS player is ready and HEIC sequences are loaded
        guard asPlayerItem?.status == .readyToPlay else {
            print("AS Player not ready, waiting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkPlayersAndStart()
            }
            return
        }

        guard !heicMaskTextures.isEmpty else {
            print("HEIC mask sequence not loaded, waiting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkPlayersAndStart()
            }
            return
        }

        // AS player ready and HEIC sequences loaded, start the demo
        print("✅ AS player ready and HEIC sequences loaded, starting demo")

        // Start AS video from beginning
        asPlayer?.seek(to: .zero)
        asPlayer?.play()

        // Start HEIC image sequence animation
        startHEICAnimation()

        print("🎬 MaskDemo: AS 视频开始播放，HEIC 图片序列动画开始")
        print("🔍 AS Player rate: \(asPlayer?.rate ?? -1)")
        print("🔍 HEIC Mask Animation: \(heicMaskTextures.count) frames at \(heicFrameRate) fps")
        print(
            "🔍 HEIC Outline Animation: \(heicOutlineTextures.count) frames at \(heicFrameRate) fps")
        print("🔍 Expected: HEIC mask 作为实时遮罩，outline 显示在最上层，与 mask 同步播放")
    }

    private func startHEICAnimation() {
        // Stop any existing animation
        stopHEICAnimation()

        guard !heicMaskTextures.isEmpty else {
            print("❌ No HEIC mask textures to animate")
            return
        }

        currentHEICIndex = 0
        let frameInterval = 1.0 / heicFrameRate

        heicAnimationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) {
            [weak self] _ in
            self?.updateHEICFrame()
        }

        print("🎬 HEIC Animation started:")
        print("  - Mask: \(heicMaskTextures.count) frames at \(heicFrameRate) fps")
        print("  - Outline: \(heicOutlineTextures.count) frames at \(heicFrameRate) fps")
    }

    private func updateHEICFrame() {
        // Update mask texture
        guard currentHEICIndex < heicMaskTextures.count else {
            // Animation completed, loop back to start
            currentHEICIndex = 0
            print("🔄 HEIC Animation loop completed, restarting...")
            return
        }

        let maskTexture = heicMaskTextures[currentHEICIndex]
        tmHideSpriteNode?.texture = maskTexture

        // Update outline texture (if available and in sync)
        if currentHEICIndex < heicOutlineTextures.count {
            let outlineTexture = heicOutlineTextures[currentHEICIndex]
            tmHideOutlineNode?.texture = outlineTexture
        }

        currentHEICIndex += 1
    }

    private func stopHEICAnimation() {
        heicAnimationTimer?.invalidate()
        heicAnimationTimer = nil
        print("⏹️ HEIC Animation stopped")
    }

    // KVO observer for player status
    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "status" {
            if let playerItem = object as? AVPlayerItem {
                switch playerItem.status {
                case .readyToPlay:
                    if playerItem == asPlayerItem {
                        print("✅ AS Player ready to play")
                    }
                case .failed:
                    if playerItem == asPlayerItem {
                        print(
                            "❌ AS Player failed: \(playerItem.error?.localizedDescription ?? "Unknown error")"
                        )
                    }
                case .unknown:
                    print("⏳ Player status unknown")
                @unknown default:
                    print("⏳ Player status unknown default")
                }
            }
        }
    }

    @objc private func asVideoDidEnd(notification: Notification) {
        print("✅ MaskDemo: AS Video Playback Ended.")
        print("🔍 AS Player current time: \(asPlayer?.currentTime().seconds ?? -1)")

        // AS 播放结束了，但 HEIC 动画可能还在继续
        // 让 HEIC 动画继续播放，这样可以看到遮罩动画效果
        print("🎭 MaskDemo: AS ended, HEIC animation continues")
        print("🔍 Expected: 应该看到 AS 最后一帧通过 HEIC 遮罩显示，随着 HEIC 动画播放，遮罩效果继续变化")

        // 3秒后重新开始演示
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.restartDemo()
        }
    }

    private func restartDemo() {
        print("🔄 MaskDemo: Restarting demo...")

        // Reset AS player to beginning
        asPlayer?.seek(to: .zero)
        asPlayer?.play()

        // Restart HEIC animation
        startHEICAnimation()

        print("🎬 MaskDemo: Demo restarted - AS 视频和 HEIC 动画重新开始")
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        // Cleanup when the scene is removed
        NotificationCenter.default.removeObserver(self)

        // Stop HEIC animation
        stopHEICAnimation()

        // Remove KVO observers safely
        do {
            asPlayerItem?.removeObserver(self, forKeyPath: "status")
        } catch {
            print("Warning: Could not remove AS player observer")
        }

        asPlayer?.pause()
        asPlayer?.replaceCurrentItem(with: nil)
        print("🧹 MaskDemoScene willMove from view - cleanup done.")
    }

    deinit {
        // Ensure observers are removed and players are paused if not done in willMove
        NotificationCenter.default.removeObserver(self)

        stopHEICAnimation()
        asPlayer?.pause()
        print("🗑️ MaskDemoScene deinit.")
    }
}

struct ContentView: View {
    // Create an instance of the MaskDemoScene
    var scene: MaskDemoScene {
        let scene = MaskDemoScene()
        scene.scaleMode = .resizeFill
        return scene
    }

    var body: some View {
        VStack {
            // Instructions
            Text("SKCropNode 遮罩效果测试 - HEIC 双层动画")
                .font(.headline)
                .padding()

            Text(
                "• AS 视频和 HEIC 图片序列 (24fps) 同时开始\n• TM_Hide_Mask 作为实时遮罩影响 AS 显示\n• TM_Hide_Outline 显示在最上层，与 Mask 同步播放\n• 不透明区域显示 AS，透明区域显示蓝色背景"
            )
            .font(.caption)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            // SpriteKit View with the masking demo
            SpriteView(scene: scene)
                .frame(height: 400)
                .border(Color.gray, width: 1)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
