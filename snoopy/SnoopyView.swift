//  SnoopyScreenSaverView.swift

import AVFoundation
import AVKit
import ScreenSaver
import SpriteKit

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
    // ... add other states as needed
}

@objc(SnoopyScreenSaverView)
class SnoopyScreenSaverView: ScreenSaverView {
    // 常量
    private let scale: CGFloat = 720.0 / 1080.0
    private let offside: CGFloat = 180.0 / 1080.0

    // --- State Management Properties ---
    private var allClips: [SnoopyClip] = []
    private var currentClipsQueue: [SnoopyClip] = []
    private var currentClipIndex: Int = 0
    private var currentNode: String?  // e.g., "BP001"
    private var currentStateType: ViewStateType = .initial
    private var currentRepeatCount: Int = 0  // For handling loops manually
    private var isMasking: Bool = false  // Flag to indicate mask transition is active
    // --- 添加状态变量 ---
    private var bpCycleCount: Int = 0
    private var lastTransitionNumber: String?  // Stores the number (e.g., "001") of the last ST/TM Reveal (for AS flow)
    private var ssTransitionNumber: String?  // Stores the number for SS flow (always "001")
    private var nextAfterAS: [SnoopyClip] = []  // Stores clips to play after AS finishes
    private var nextAfterSS: [SnoopyClip] = []  // Stores clips to play after SS finishes
    private var isFirstASPlayback: Bool = true  // 标记是否为初次AS播放
    private var isPlayingSS: Bool = false  // 标记当前是否在播放SS流程
    private var isSTHideSyncPlaying: Bool = false  // 标记ST_Hide是否正在同步播放
    // --- 方案2：ST_Reveal和TM_Reveal同时结束 ---
    private var stRevealCompleted: Bool = false  // 标记ST_Reveal是否完成
    private var tmRevealCompleted: Bool = false  // 标记TM_Reveal是否完成
    private var isWaitingForDualCompletion: Bool = false  // 标记是否在等待ST_Reveal和TM_Reveal双重完成
    // --- 结束添加 ---

    // --- Player and Nodes ---
    private var queuePlayer: AVQueuePlayer?
    private var playerItem: AVPlayerItem?  // Keep track of the current item for notifications
    private var overlayPlayer: AVQueuePlayer?  // Player for VI/WE overlays
    private var overlayPlayerItem: AVPlayerItem?  // Track overlay item
    private var overlayRepeatCount: Int = 0  // For overlay loops

    // --- AS/SS Independent Player System ---
    private var asPlayer: AVPlayer?  // Independent player for AS/SS content
    private var asPlayerItem: AVPlayerItem?  // Track AS/SS player item
    private var asVideoNode: SKVideoNode?  // Video node for AS/SS content in cropNode

    // --- Masking Properties ---
    private var cropNode: SKCropNode?

    // --- HEIC Sequence Player Properties ---
    private var heicSequencePlayer: HEICSequencePlayer?
    private var tmMaskSpriteNode: SKSpriteNode?
    private var tmOutlineSpriteNode: SKSpriteNode?  // TM outline 层，显示在最上层

    private var skView: SKView?
    private var scene: SKScene?
    private var backgroundColorNode: SKSpriteNode?
    private var halftoneNode: SKSpriteNode?
    private var backgroundImageNode: SKSpriteNode?  // IS image
    private var videoNode: SKVideoNode?
    private var overlayNode: SKVideoNode?  // Node for VI/WE overlays

    private let colors: [NSColor] = [
        NSColor(red: 50.0 / 255.0, green: 60.0 / 255.0, blue: 47.0 / 255.0, alpha: 1.0),
        NSColor(red: 5.0 / 255.0, green: 168.0 / 255.0, blue: 157.0 / 255.0, alpha: 1.0),
        NSColor(red: 65.0 / 255.0, green: 176.0 / 255.0, blue: 246.0 / 255.0, alpha: 1.0),
        NSColor(red: 238.0 / 255.0, green: 95.0 / 255.0, blue: 167.0 / 255.0, alpha: 1.0),
        NSColor.black,
    ]

    private var backgroundImages: [String] = []

    // MARK: - Initialization and Setup

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        animationTimeInterval = 1.0 / 30.0

        // 在Sonoma上延迟初始化，避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupView()
            }
        } else {
            setupView()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        animationTimeInterval = 1.0 / 30.0

        // 在Sonoma上延迟初始化，避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupView()
            }
        } else {
            setupView()
        }
    }

    private func setupView() {
        loadBackgroundImages()  // Load IS names

        // Setup SKView and Scene first
        setupScene()

        // Asynchronously load clips and then start
        Task {
            do {
                print("Loading clips...")
                // Use SnoopyClip.loadClips() to load clips
                self.allClips = try await SnoopyClip.loadClips()
                print("Clips loaded: \(self.allClips.count)")
                guard !self.allClips.isEmpty else {
                    print("No clips loaded, cannot start.")
                    // Handle error state - maybe show a static image or message
                    return
                }
                // Setup player *after* clips are loaded
                setupPlayer()
                // Set initial state and start playback
                setupInitialStateAndPlay()
            } catch {
                print("Error loading clips: \(error)")
                // Handle error state
            }
        }

        // Setup complete
    }

    private func loadBackgroundImages() {
        guard let resourcePath = Bundle(for: type(of: self)).resourcePath else { return }
        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(atPath: resourcePath)
            // Filter for IS background images only, excluding TM animation files
            let heicFiles = files.filter { file in
                file.hasSuffix(".heic") && file.contains("_IS")
            }
            self.backgroundImages = heicFiles
            print("🖼️ Loaded \(heicFiles.count) IS background images")
        } catch {
            print("Error reading Resources directory: \(error.localizedDescription)")
        }
    }

    private func setupScene() {
        guard skView == nil else { return }  // Prevent double setup

        // --- Initialize Players FIRST ---
        self.queuePlayer = AVQueuePlayer()
        self.overlayPlayer = AVQueuePlayer()
        self.asPlayer = AVPlayer()  // Independent AS/SS player

        let skView = SKView(frame: bounds)
        skView.wantsLayer = true
        skView.layer?.backgroundColor = NSColor.clear.cgColor  // Make SKView transparent
        skView.ignoresSiblingOrder = true
        skView.allowsTransparency = true
        self.skView = skView
        addSubview(skView)

        let scene = SKScene(size: bounds.size)
        scene.scaleMode = .aspectFill
        scene.backgroundColor = .clear  // Scene background clear
        self.scene = scene

        // Layer 0: Solid Background Color
        let solidColorBGNode = SKSpriteNode(color: NSColor.black, size: scene.size)
        solidColorBGNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        solidColorBGNode.zPosition = 0
        solidColorBGNode.name = "backgroundColor"
        solidColorBGNode.alpha = 1
        scene.addChild(solidColorBGNode)
        self.backgroundColorNode = solidColorBGNode

        // Layer 1: Halftone Pattern
        if let bgImagePath = Bundle(for: type(of: self)).path(
            forResource: "halftone_pattern", ofType: "png"),
            let bgImage = NSImage(contentsOfFile: bgImagePath)
        {
            let bgtexture = SKTexture(image: bgImage)
            let halftone = SKSpriteNode(texture: bgtexture)
            halftone.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
            halftone.size = scene.size
            halftone.zPosition = 1
            halftone.alpha = 0  // 初始设置为透明，直到AS开始播放
            halftone.name = "halftonePattern"
            halftone.blendMode = .alpha
            scene.addChild(halftone)
            self.halftoneNode = halftone
        }

        // Layer 2: IS Background Image
        let imageNode = SKSpriteNode()
        imageNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        imageNode.zPosition = 2
        imageNode.name = "backgroundImage"
        imageNode.blendMode = .alpha
        imageNode.alpha = 0  // 初始设置为透明，直到AS开始播放
        scene.addChild(imageNode)
        self.backgroundImageNode = imageNode

        // Layer 3: Main Video Node - Initialize WITH player (用于播放BP、AP、CM、ST、RPH)
        guard let mainPlayer = self.queuePlayer else {
            print("Error: Main queuePlayer is nil during scene setup.")
            return
        }
        let videoNode = SKVideoNode(avPlayer: mainPlayer)
        videoNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        videoNode.size = scene.size
        videoNode.zPosition = 3  // 常规内容在Layer 3
        videoNode.name = "videoNode"
        scene.addChild(videoNode)
        self.videoNode = videoNode

        // Layer 4: Overlay Node (For VI/WE) - Initialize WITH player
        guard let ovPlayer = self.overlayPlayer else {
            print("Error: Overlay player is nil during scene setup.")
            return
        }
        let overlayNode = SKVideoNode(avPlayer: ovPlayer)
        overlayNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        overlayNode.size = scene.size  // Adjust size/position as needed for overlays
        overlayNode.zPosition = 4
        overlayNode.name = "overlayNode"
        overlayNode.isHidden = true  // Initially hidden
        scene.addChild(overlayNode)
        self.overlayNode = overlayNode

        // Layer 10: 创建cropNode专门用于AS/SS内容，始终保持在最上层以确保遮罩效果正确
        let cropNode = SKCropNode()
        cropNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        cropNode.zPosition = 10  // AS/SS内容在最上层，便于遮罩处理
        scene.addChild(cropNode)
        self.cropNode = cropNode

        // AS/SS Video Node - Initialize WITH independent AS player
        guard let asPlayer = self.asPlayer else {
            print("Error: AS player is nil during scene setup.")
            return
        }
        let asVideoNode = SKVideoNode(avPlayer: asPlayer)
        asVideoNode.position = CGPoint.zero  // Position relative to cropNode
        asVideoNode.size = scene.size
        asVideoNode.name = "asVideoNode"
        asVideoNode.isHidden = true  // Initially hidden until AS content plays
        cropNode.addChild(asVideoNode)
        self.asVideoNode = asVideoNode

        // Layer 15: TM Outline Node - 显示在所有内容之上
        let outlineNode = SKSpriteNode(color: .clear, size: scene.size)
        outlineNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        outlineNode.zPosition = 15  // 在所有内容之上
        outlineNode.name = "tmOutlineNode"
        outlineNode.isHidden = true  // 初始隐藏
        outlineNode.blendMode = .alpha
        scene.addChild(outlineNode)
        self.tmOutlineSpriteNode = outlineNode

        skView.presentScene(scene)
    }

    private func setupPlayer() {
        guard self.queuePlayer != nil, self.overlayPlayer != nil else {
            print("Error: Players not initialized before setupPlayer call.")
            return
        }

        NotificationCenter.default.removeObserver(
            self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    private func setupInitialStateAndPlay() {
        print("Setting up initial state...")
        guard let initialAS = findRandomClip(ofType: .AS) else {
            print("Error: No AS clips found to start.")
            return
        }
        print("Initial AS: \(initialAS.fileName)")

        // 为初始AS设置随机转场编号，排除006
        let availableTransitionNumbers = allClips.compactMap { clip in
            guard clip.type == .TM_Hide else { return nil }
            return clip.number
        }.filter { $0 != "006" }  // 排除006编号

        if let randomNumber = availableTransitionNumbers.randomElement() {
            self.lastTransitionNumber = randomNumber
            print("🎲 为初始AS设置随机转场编号: \(randomNumber)")
        } else {
            print("⚠️ 警告：无法找到可用的转场编号")
        }

        currentStateType = .playingAS
        currentClipsQueue = [initialAS]
        currentClipIndex = 0
        playNextClipInQueue()
    }

    // MARK: - Core Playback Logic

    private func playNextClipInQueue() {
        guard !isMasking else {
            print("⏳ 遮罩过渡正在进行中，延迟播放下一个主片段。")
            return
        }
        guard currentClipIndex < currentClipsQueue.count else {
            print("✅ 当前队列播放完毕。处理序列结束...")
            handleEndOfQueue()
            return
        }

        let clipToPlay = currentClipsQueue[currentClipIndex]
        print(
            "🎬 正在处理片段 (\(currentClipIndex + 1)/\(currentClipsQueue.count)): \(clipToPlay.fileName) (\(clipToPlay.type))"
        )

        // 首先更新当前状态，确保状态正确
        updateStateForStartingClip(clipToPlay)

        if clipToPlay.type == .TM_Hide || clipToPlay.type == .TM_Reveal {
            let basePattern = clipToPlay.fileName
            print(
                "🔍 TM片段详情: fileName=\(clipToPlay.fileName), type=\(clipToPlay.type), groupID=\(clipToPlay.groupID ?? "nil"), number=\(clipToPlay.number ?? "nil")"
            )

            // 使用HEICSequencePlayer来播放TM序列
            if self.heicSequencePlayer == nil {
                self.heicSequencePlayer = HEICSequencePlayer()
            }

            guard let player = self.heicSequencePlayer else {
                print("❌ 错误：无法创建HEIC序列播放器。跳过片段 [\(clipToPlay.fileName)]。")
                currentClipIndex += 1
                playNextClipInQueue()
                return
            }

            // 在后台线程加载TM序列以避免卡顿
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let success = player.loadSequence(basePattern: basePattern)

                DispatchQueue.main.async {
                    guard let self = self else { return }

                    if !success {
                        print("❌ 错误：无法加载HEIC序列 [\(basePattern)]。跳过片段 [\(clipToPlay.fileName)]。")
                        self.currentClipIndex += 1
                        self.playNextClipInQueue()
                        return
                    }

                    let isRevealing = (clipToPlay.type == .TM_Reveal)
                    let contentClip: SnoopyClip? =
                        isRevealing ? self.currentClipsQueue[safe: self.currentClipIndex + 1] : nil

                    self.startMaskTransitionWithHEIC(
                        basePattern: basePattern, tmClip: clipToPlay, contentClip: contentClip,
                        isRevealing: isRevealing)
                }
            }
            return
        }

        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: clipToPlay.fileName, withExtension: nil)
        else {
            print("❌ 错误：找不到视频文件 \(clipToPlay.fileName)")
            currentClipIndex += 1
            playNextClipInQueue()
            return
        }
        print("▶️ 播放片段: \(clipToPlay.fileName)")

        // 特殊调试：如果是RPH，记录播放开始时间
        if clipToPlay.type == .RPH {
            print("🎬 RPH播放开始: \(clipToPlay.fileName) - \(Date())")
        }

        let newItem = AVPlayerItem(url: url)

        // 根据内容类型选择适当的播放器
        if clipToPlay.type == .AS || clipToPlay.type == .SS_Intro || clipToPlay.type == .SS_Loop
            || clipToPlay.type == .SS_Outro
        {
            // AS/SS内容使用独立播放器在顶层播放

            // 检查是否已经预加载了当前内容
            let currentAsItem = asPlayer?.currentItem
            let shouldUsePreloaded =
                clipToPlay.type == .SS_Intro && currentAsItem != nil
                && currentAsItem?.asset is AVURLAsset
                && (currentAsItem?.asset as? AVURLAsset)?.url.lastPathComponent
                    == clipToPlay.fileName

            if shouldUsePreloaded {
                // 内容已经预加载，直接使用
                print("📊 使用预加载的SS_Intro内容")
                self.asPlayerItem = currentAsItem

                // 设置AS/SS视频节点可见性并开始播放
                if let asVideoNode = self.asVideoNode {
                    asVideoNode.isHidden = false
                }
                asPlayer?.play()
            } else {
                // 常规加载流程
                self.asPlayerItem = newItem
                asPlayer?.replaceCurrentItem(with: newItem)

                // 设置AS/SS视频节点可见性
                if let asVideoNode = self.asVideoNode {
                    asVideoNode.isHidden = false
                }
                asPlayer?.play()
            }

            print("📊 AS/SS内容使用独立播放器在顶层播放")
            print(
                "🔧 调试信息: AS播放器状态 - rate: \(asPlayer?.rate ?? -1), currentItem: \(asPlayer?.currentItem != nil)"
            )

            // 监听AS/SS播放完成事件
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(asPlaybackEnded(_:)),
                name: .AVPlayerItemDidPlayToEndTime,
                object: asPlayerItem
            )
        } else {
            // BP、AP、CM、ST、RPH等内容使用主播放器
            self.playerItem = newItem

            // 确保AS/SS视频节点隐藏
            if let asVideoNode = self.asVideoNode {
                asVideoNode.isHidden = true
            }

            queuePlayer?.removeAllItems()
            queuePlayer?.insert(newItem, after: nil)
            queuePlayer?.play()

            print("📊 常规内容使用主播放器在Layer 3播放")

            // 🎬 方案2：ST_Reveal特殊处理 - 检查下一个是否是TM_Reveal（普通AS流程）
            if clipToPlay.type == .ST_Reveal && currentClipIndex + 1 < currentClipsQueue.count
                && currentClipsQueue[currentClipIndex + 1].type == .TM_Reveal
            {

                let tmRevealClip = currentClipsQueue[currentClipIndex + 1]
                print("🎬 检测到ST_Reveal -> TM_Reveal序列，启动方案2（同时结束）")

                // 计算延迟启动时间
                let stDuration = clipToPlay.duration
                let tmDuration = tmRevealClip.duration
                let delayTime = max(0, stDuration - tmDuration)

                print(
                    "📊 时长信息：ST_Reveal=\(stDuration)s, TM_Reveal=\(tmDuration)s, 延迟=\(delayTime)s"
                )

                // 设置双重完成等待状态
                isWaitingForDualCompletion = true
                stRevealCompleted = false
                tmRevealCompleted = false

                // 延迟启动TM_Reveal和AS
                startDelayedTMRevealAndAS(tmRevealClip: tmRevealClip, delay: delayTime)
            }
            // 特殊处理：如果当前是ST_Reveal且下一个是SS_Intro，预加载SS_Intro到AS播放器
            else if clipToPlay.type == .ST_Reveal && currentClipIndex + 1 < currentClipsQueue.count
                && currentClipsQueue[currentClipIndex + 1].type == .SS_Intro
            {

                let nextClip = currentClipsQueue[currentClipIndex + 1]
                if let nextUrl = Bundle.main.url(forResource: nextClip.fileName, withExtension: nil)
                {
                    let nextItem = AVPlayerItem(url: nextUrl)
                    print("🔮 预加载SS_Intro到AS播放器: \(nextClip.fileName)")

                    // 预加载但不播放，确保AS视频节点隐藏
                    asPlayer?.replaceCurrentItem(with: nextItem)
                    if let asVideoNode = self.asVideoNode {
                        asVideoNode.isHidden = true
                    }
                } else {
                    print("⚠️ 无法预加载SS_Intro: \(nextClip.fileName)")
                }
            }
        }

        if clipToPlay.type == .BP_Node || clipToPlay.type == .AP_Loop {
            let initialRepeatCount = max(1, clipToPlay.repeatCount)
            self.currentRepeatCount = max(0, initialRepeatCount - 1)
            print(
                "🔁 循环片段检测到: \(clipToPlay.fileName)。剩余重复次数: \(self.currentRepeatCount)"
            )
        } else if clipToPlay.type == .SS_Loop {
            self.currentRepeatCount = 0  // SS_Loop only plays once
            print(
                "🔁 循环片段检测到: \(clipToPlay.fileName)。SS_Loop 设置为播放一次。"
            )
        } else {
            self.currentRepeatCount = 0
        }

        // VI/WE overlay logic for BP and AP loops
        if clipToPlay.type == .BP_Node || clipToPlay.type == .AP_Loop {
            let overlayChance = 0.9
            if Double.random(in: 0...1) < overlayChance {
                tryPlayVIWEOverlay()
            }
        }
    }

    private func updateStateForStartingClip(_ clip: SnoopyClip) {
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
                print("📍 当前节点设置为: \(self.currentNode ?? "nil") 来自 RPH")
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
            print("⚠️ 未明确处理的片段类型: \(clip.type)")
        }
        print("📊 当前状态更新为: \(currentStateType)")
    }

    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        guard let finishedItem = notification.object as? AVPlayerItem else {
            print("⚠️ 通知接收到的对象不是 AVPlayerItem。忽略。")
            return
        }

        // 特殊处理：在方案2双重完成等待期间，允许处理ST_Reveal完成事件
        if isMasking && !isWaitingForDualCompletion {
            print("🔍 isMasking=true但不在双重完成等待中，忽略播放完成事件")
            return
        }

        if finishedItem == self.overlayPlayerItem {
            handleOverlayItemFinish(finishedItem: finishedItem)
            return
        }

        // Check if this is from the AS player
        if finishedItem == self.asPlayerItem {
            print("✅ AS/SS播放器内容播放完成，直接在此处理")

            // 移除这个特定的通知观察者
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: finishedItem)

            // 直接调用AS播放完成的处理逻辑
            handleASPlaybackCompletion()
            return
        }

        guard finishedItem == self.playerItem else {
            print("⚠️ 通知接收到意外的播放器项目。忽略。")
            return
        }
        print("✅ 主播放器内容播放完成。")

        if currentRepeatCount > 0 {
            print("🔁 循环片段。剩余重复次数: \(currentRepeatCount - 1)")
            if let url = (finishedItem.asset as? AVURLAsset)?.url {
                let newItem = AVPlayerItem(url: url)
                self.playerItem = newItem

                queuePlayer?.removeAllItems()
                queuePlayer?.insert(newItem, after: nil)
                currentRepeatCount -= 1
                queuePlayer?.play()
                return
            }
        }

        guard currentClipIndex < currentClipsQueue.count else {
            print("❌ 错误：playerItemDidReachEnd 调用时索引超出范围。")
            return
        }

        // 特殊处理：如果ST_Hide正在同步播放且当前状态是playingSTHide，
        // 说明这是ST_Hide同步播放完成的通知，而不是队列中片段的完成
        if isSTHideSyncPlaying && currentStateType == .playingSTHide {
            print("✅ ST_Hide同步播放完成")
            isSTHideSyncPlaying = false
            print("🔄 ST_Hide同步播放完成，重置标志，现在开始播放队列中的RPH")

            // 现在开始播放队列中的第一个片段（RPH）
            playNextClipInQueue()
            return
        }

        let finishedClip = currentClipsQueue[currentClipIndex]

        guard finishedClip.type != .TM_Hide && finishedClip.type != .TM_Reveal else {
            print("❌ 错误：主播放器意外完成 TM 片段。")
            currentClipIndex += 1
            playNextClipInQueue()
            return
        }
        print("✅ 完成主片段: \(finishedClip.fileName)")

        // 特殊调试：如果是RPH，记录播放结束时间
        if finishedClip.type == .RPH {
            print("🎬 RPH播放结束: \(finishedClip.fileName) - \(Date())")
        }

        // BP_To_RPH播放完毕，预加载TM_Reveal和AS以便在ST_Reveal播放完成后立即使用
        if finishedClip.type == .BP_To && finishedClip.to?.starts(with: "RPH") ?? false {
            print("🎬 BP_To_RPH 完成。预加载TM_Reveal和AS。")

            // 检查下一个是否是ST_Reveal
            if currentClipIndex + 1 < currentClipsQueue.count
                && currentClipsQueue[currentClipIndex + 1].type == .ST_Reveal
            {
                // TM_Reveal preloading removed - now handled by HEIC sequence player
                print(
                    "🔄 Next clip is ST_Reveal - TM transitions now handled by HEIC sequence player")
            }
        }

        // 🎬 方案2：ST_Reveal播放完毕的处理
        if finishedClip.type == .ST_Reveal {
            print("🎬 ST_Reveal 完成")

            // 检查是否是方案2（等待双重完成）
            if isWaitingForDualCompletion {
                print("🎬 ST_Reveal完成（方案2），标记并检查双重完成")
                stRevealCompleted = true
                checkDualCompletionAndContinue()
                return
            }

            // 原有逻辑：如果下一个是TM_Reveal，使用TM_Reveal过渡
            if currentClipIndex + 1 < currentClipsQueue.count
                && currentClipsQueue[currentClipIndex + 1].type == .TM_Reveal
            {
                // 第一次调用playerItemDidReachEnd时，我们已经预加载TM_Reveal和AS
                // 增加索引并播放下一个片段，这将触发TM_Reveal的开始
                currentClipIndex += 1
                playNextClipInQueue()
                return
            }

            print("🎬 ST_Reveal 完成。继续序列。")
        }

        // 根据需求文档：只有初次AS播放完成后才加载背景
        // 后续从BP跳转到AS的不需要重新加载背景，因为背景在首次AS后已经加载了
        if finishedClip.type == .AS && isFirstASPlayback {
            print("🎬 初次AS播放完成，现在加载背景")
            updateBackgrounds()
            isFirstASPlayback = false  // 标记初次AS播放已完成
        } else if finishedClip.type == .SS_Outro {
            updateBackgrounds()
        }

        // 特殊处理：如果AS是通过TM_Reveal过渡显示的，不调用generateNextSequence
        // 因为后续序列會由HEIC完成回调处理
        if finishedClip.type == .AS && currentStateType == .playingTMReveal {
            print("🔍 AS通过TM_Reveal过渡显示，跳过generateNextSequence，等待HEIC完成回调处理")
            currentClipIndex += 1
            // 不调用playNextClipInQueue，因为TM_Hide会由HEIC系统处理
            return
        }

        generateNextSequence(basedOn: finishedClip)

        currentClipIndex += 1
        playNextClipInQueue()
    }

    @objc private func asPlaybackEnded(_ notification: Notification) {
        // 这个函数现在可能不会被调用，因为AS播放完成在playerItemDidReachEnd中处理
        print("⚠️ asPlaybackEnded被调用（这不应该发生）")
        handleASPlaybackCompletion()
    }

    private func handleASPlaybackCompletion() {
        print("✅ AS/SS视频播放完毕")
        print("🔧 调试信息: handleASPlaybackCompletion被调用 - \(Date())")

        print(
            "🔍 AS/SS播放完成，状态: \(currentStateType), 是否首次: \(isFirstASPlayback), 是否SS流程: \(isPlayingSS)"
        )

        // 根据当前状态判断如何处理
        if currentStateType == .playingSSIntro || currentStateType == .playingSSLoop {
            // SS_Intro或SS_Loop完成，继续播放下一个SS片段，不进入TM_Hide
            print("🔍 \(currentStateType == .playingSSIntro ? "SS_Intro" : "SS_Loop")完成，继续播放下一个SS片段")
            currentClipIndex += 1
            playNextClipInQueue()
            return
        } else if currentStateType == .playingSSOutro {
            // SS_Outro完成，需要延迟后进入TM_Hide，类似原来的ssOutroPlaybackEnded逻辑
            print("✅ SS_Outro视频播放完毕，延迟2秒后将开始播放TM_Hide")

            // 设置状态为隐藏过渡
            currentStateType = .transitioningToHalftoneHide

            // 延迟2秒后启动TM_Hide（根据AnimationLogic.md）
            handleSSCompletionWithTMHide()
            return
        }

        // 只有AS播放完成才立即进入TM_Hide过渡
        // 如果是首次AS播放，需要先加载背景
        if isFirstASPlayback && !isPlayingSS {
            print("🔍 初始AS播放完成，加载背景")
            updateBackgrounds()
            isFirstASPlayback = false  // 标记初次AS播放已完成
        }

        // AS播放完成，立即进入TM_Hide过渡
        if !isPlayingSS {
            print("🔍 AS播放完成，启动TM_Hide过渡隐藏AS内容")
            print("🔍 Debug: lastTransitionNumber = \(lastTransitionNumber ?? "nil")")
            handleASCompletionWithTMHide()
        } else {
            print("🔍 SS流程播放完成，不启动TM_Hide")
        }
    }

    private func handleSSCompletionWithTMHide() {
        // 设置状态为隐藏过渡
        currentStateType = .transitioningToHalftoneHide

        // SS流程：使用预存储的随机TM_Hide
        if !nextAfterSS.isEmpty && nextAfterSS[0].type == .TM_Hide {
            let tmHide = nextAfterSS[0]
            print("🔍 SS播放完成，使用预存储的随机TM_Hide: \(tmHide.fileName)")
            startTMHideTransition(tmHide: tmHide)
        } else {
            // 回退：使用随机TM_Hide
            print("🔍 SS流程没有预存储TM_Hide，使用随机TM_Hide")
            if let randomTMHide = findRandomClip(ofType: .TM_Hide) {
                print("✅ 找到随机TM_Hide: \(randomTMHide.fileName)")
                startTMHideTransition(tmHide: randomTMHide)
            } else {
                print("❌ 错误：找不到任何TM_Hide片段")
            }
        }
    }

    private func handleASCompletionWithTMHide() {
        // 设置状态为隐藏过渡
        currentStateType = .transitioningToHalftoneHide

        // 检查是否有有效的lastTransitionNumber用于匹配TM_Hide
        if let transitionNumber = self.lastTransitionNumber {
            print("🔍 AS播放完成，使用保存的转场编号 \(transitionNumber) 来启动匹配的TM_Hide")

            // 找到匹配的TM_Hide并直接启动HEIC播放器
            if let tmHide = findRandomClip(ofType: .TM_Hide, matchingNumber: transitionNumber) {
                print("✅ 找到匹配的TM_Hide: \(tmHide.fileName)")
                startTMHideTransition(tmHide: tmHide)
            } else {
                print("❌ 错误：找不到匹配转场编号 \(transitionNumber) 的TM_Hide")
                // 回退：使用随机TM_Hide
                if let randomTMHide = findRandomClip(ofType: .TM_Hide) {
                    print("🔄 回退：使用随机TM_Hide: \(randomTMHide.fileName)")
                    startTMHideTransition(tmHide: randomTMHide)
                }
            }
        } else {
            // 没有存储的转场编号，使用随机TM_Hide
            print("🔍 没有存储的转场编号，使用随机TM_Hide")
            if let randomTMHide = findRandomClip(ofType: .TM_Hide) {
                print("✅ 找到随机TM_Hide: \(randomTMHide.fileName)")
                startTMHideTransition(tmHide: randomTMHide)
            } else {
                print("❌ 错误：找不到任何TM_Hide片段")
            }
        }
    }

    private func startTMHideTransition(tmHide: SnoopyClip) {
        // 直接播放TM_Hide，而不是通过队列系统
        if self.heicSequencePlayer == nil {
            self.heicSequencePlayer = HEICSequencePlayer()
        }

        guard let player = self.heicSequencePlayer else {
            print("❌ 错误：无法创建HEIC序列播放器")
            return
        }

        // 在后台线程加载TM_Hide序列以避免卡顿
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = player.loadSequence(basePattern: tmHide.fileName)

            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    print("🎭 直接启动TM_Hide HEIC序列: \(tmHide.fileName)")
                    self.isMasking = true

                    // 创建mask sprite node如果不存在
                    if self.tmMaskSpriteNode == nil {
                        guard let scene = self.scene else {
                            print("❌ 错误：缺少场景组件")
                            return
                        }
                        let maskNode = SKSpriteNode(color: .clear, size: scene.size)
                        maskNode.position = .zero  // 相对于cropNode的位置
                        self.tmMaskSpriteNode = maskNode
                    }

                    // 🎬 新增：准备ST_Hide同步播放
                    let stHideClip = self.prepareSyncSTHideForTMHide(tmHide: tmHide)

                    // 设置遮罩并播放
                    if let maskNode = self.tmMaskSpriteNode,
                        let outlineNode = self.tmOutlineSpriteNode,
                        let asVideoNode = self.asVideoNode,
                        let cropNode = self.cropNode
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

                        print("🔧 调试信息: ")
                        print("  - cropNode.zPosition: \(cropNode.zPosition)")
                        print("  - asVideoNode.isHidden: \(asVideoNode.isHidden)")
                        print("  - maskNode.size: \(maskNode.size)")
                        print("  - cropNode.maskNode设置完成: \(cropNode.maskNode != nil)")

                        // 🎬 修改：TM_Hide开始播放时，预先加载ST_Hide，然后延迟0.5秒开始播放
                        if let stHide = stHideClip {
                            // 立即预加载ST_Hide
                            self.preloadSyncSTHideForDelayedPlayback(stHide: stHide)

                            // 延迟0.5秒开始播放（不是加载）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                                self?.startPreloadedSTHidePlayback()
                            }
                        }

                        player.playDual(maskNode: maskNode, outlineNode: outlineNode) {
                            [weak self] in
                            self?.heicSequenceMaskCompleted(
                                isRevealing: false,
                                tmClip: tmHide,
                                basePattern: tmHide.fileName
                            )
                        }
                    } else {
                        print("❌ 错误：缺少必要的节点来启动TM_Hide过渡")
                    }
                } else {
                    print("❌ 错误：无法加载TM_Hide HEIC序列: \(tmHide.fileName)")
                }
            }
        }
    }

    // MARK: - 同步播放功能

    /// 为TM_Hide准备匹配的ST_Hide片段
    private func prepareSyncSTHideForTMHide(tmHide: SnoopyClip) -> SnoopyClip? {
        // 根据流程类型选择ST_Hide的编号
        let stHideNumber: String
        if isPlayingSS {
            // SS流程：固定使用001编号的ST_Hide
            stHideNumber = "001"
            print("🎬 SS流程同步播放：准备编号001的ST_Hide与TM_Hide同步")
        } else {
            // AS流程：使用TM_Hide的编号
            stHideNumber = tmHide.number ?? "001"
            print("🎬 AS流程同步播放：准备编号 \(stHideNumber) 的ST_Hide与TM_Hide同步")
        }

        guard let stHide = findMatchingST(forNumber: stHideNumber, type: .ST_Hide) else {
            print("❌ 同步播放失败：找不到编号为 \(stHideNumber) 的ST_Hide")
            return nil
        }

        print("✅ 同步播放准备：找到ST_Hide: \(stHide.fileName) 将预加载并延迟0.5秒与TM_Hide: \(tmHide.fileName) 播放")
        return stHide
    }

    /// 预加载ST_Hide（用于延迟播放）
    private func preloadSyncSTHideForDelayedPlayback(stHide: SnoopyClip) {
        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: stHide.fileName, withExtension: nil)
        else {
            print("❌ 预加载失败：找不到ST_Hide视频文件 \(stHide.fileName)")
            return
        }

        let playerItem = AVPlayerItem(url: url)

        // 重要：更新playerItem跟踪，以便播放完成通知能被正确识别
        self.playerItem = playerItem

        queuePlayer?.removeAllItems()
        queuePlayer?.insert(playerItem, after: nil)

        // 🎬 关键修复：确保播放器暂停，这样延迟播放才能生效
        queuePlayer?.pause()

        // 更新状态和标志（但不开始播放）
        currentStateType = .playingSTHide
        isSTHideSyncPlaying = true  // 标记ST_Hide正在同步播放

        print("🎬 预加载完成：ST_Hide (\(stHide.fileName)) 已加载并暂停，等待延迟播放")
    }

    /// 开始播放预加载的ST_Hide
    private func startPreloadedSTHidePlayback() {
        print("🎬 延迟播放开始：ST_Hide 延迟0.5秒后开始播放")

        // 🆕 在 ST_Hide 开始播放时，检查是否有活跃的 VI/WE loop 需要中断
        checkAndInterruptActiveOverlayLoop()

        queuePlayer?.play()
    }

    /// 为TM_Reveal准备AS内容的同步播放
    private func prepareSyncASForTMReveal(asClip: SnoopyClip) -> Bool {
        guard
            let contentUrl = Bundle(for: type(of: self)).url(
                forResource: asClip.fileName, withExtension: nil)
        else {
            print("❌ 同步播放失败：找不到AS视频文件 \(asClip.fileName)")
            return false
        }

        let newItem = AVPlayerItem(url: contentUrl)
        self.asPlayerItem = newItem
        asPlayer?.replaceCurrentItem(with: newItem)

        // 确保AS视频节点可见但暂停播放，等待TM_Reveal开始
        if let asVideoNode = self.asVideoNode {
            asVideoNode.isHidden = false
        }
        asPlayer?.pause()

        print("✅ 同步播放准备：AS (\(asClip.fileName)) 已加载，等待与TM_Reveal同步播放")
        return true
    }

    /// 开始同步播放AS（与TM_Reveal同时）
    private func startSyncASPlayback() {
        print("🎬 同步播放开始：AS与TM_Reveal同时播放")
        print(
            "🔧 调试信息: AS播放器开始前状态 - rate: \(asPlayer?.rate ?? -1), currentItem: \(asPlayer?.currentItem != nil)"
        )
        asPlayer?.play()
        print("🔧 调试信息: AS播放器开始后状态 - rate: \(asPlayer?.rate ?? -1)")
    }

    // MARK: - 方案2：ST_Reveal和TM_Reveal同时结束

    /// 延迟启动TM_Reveal和AS播放（方案2）
    private func startDelayedTMRevealAndAS(tmRevealClip: SnoopyClip, delay: TimeInterval) {
        print("⏰ 延迟 \(delay) 秒后启动TM_Reveal和AS播放")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            print("🎬 延迟时间到，开始TM_Reveal和AS播放")

            // 检查下一个AS片段
            guard self.currentClipIndex + 2 < self.currentClipsQueue.count,
                self.currentClipsQueue[self.currentClipIndex + 2].type == .AS
            else {
                print("❌ 错误：找不到AS片段")
                return
            }

            let asClip = self.currentClipsQueue[self.currentClipIndex + 2]

            // 启动TM_Reveal HEIC序列（AS的准备和播放将在HEIC加载完成后进行）
            self.startTMRevealSequence(tmRevealClip: tmRevealClip, asClip: asClip)
        }
    }

    /// 启动TM_Reveal HEIC序列（方案2专用）
    private func startTMRevealSequence(tmRevealClip: SnoopyClip, asClip: SnoopyClip) {
        if self.heicSequencePlayer == nil {
            self.heicSequencePlayer = HEICSequencePlayer()
        }

        guard let player = self.heicSequencePlayer else {
            print("❌ 错误：无法创建HEIC序列播放器")
            return
        }

        // 在后台线程加载HEIC序列以避免卡顿
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = player.loadSequence(basePattern: tmRevealClip.fileName)

            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    print("🎭 HEIC序列加载完成: \(tmRevealClip.fileName)")

                    // 现在准备AS同步播放
                    let syncPrepared = self.prepareSyncASForTMReveal(asClip: asClip)
                    if !syncPrepared {
                        print("❌ 错误：无法准备AS同步播放")
                        return
                    }

                    print("🎭 启动TM_Reveal HEIC序列: \(tmRevealClip.fileName)")
                    self.isMasking = true

                    // 创建mask sprite node如果不存在
                    if self.tmMaskSpriteNode == nil {
                        guard let scene = self.scene else {
                            print("❌ 错误：缺少场景组件")
                            return
                        }
                        let maskNode = SKSpriteNode(color: .clear, size: scene.size)
                        maskNode.position = .zero
                        self.tmMaskSpriteNode = maskNode
                    }
                    // 设置遮罩并播放
                    if let maskNode = self.tmMaskSpriteNode,
                        let outlineNode = self.tmOutlineSpriteNode,
                        let asVideoNode = self.asVideoNode,
                        let cropNode = self.cropNode
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

                        // 设置状态
                        self.currentStateType = .playingTMReveal
                        self.lastTransitionNumber = tmRevealClip.number
                        print("💾 TM_Reveal过渡期间存储转场编号: \(self.lastTransitionNumber ?? "nil")")

                        // 同步开始AS播放
                        self.startSyncASPlayback()

                        // 播放双层HEIC序列
                        player.playDual(maskNode: maskNode, outlineNode: outlineNode) {
                            [weak self] in
                            self?.tmRevealCompletedForDualCompletion(tmClip: tmRevealClip)
                        }
                    } else {
                        print("❌ 错误：缺少必要的节点来启动TM_Reveal过渡")
                    }
                } else {
                    print("❌ 错误：无法加载TM_Reveal HEIC序列: \(tmRevealClip.fileName)")
                }
            }
        }
    }

    /// TM_Reveal完成回调（方案2专用）
    private func tmRevealCompletedForDualCompletion(tmClip: SnoopyClip) {
        print("✅ TM_Reveal播放完成（方案2）")
        tmRevealCompleted = true
        checkDualCompletionAndContinue()
    }

    // MARK: - Overlay Management

    private func generateNextSequence(basedOn finishedClip: SnoopyClip) {
        print(
            "📊 基于完成的片段生成下一个序列: \(finishedClip.fileName) (类型: \(finishedClip.type), 状态: \(currentStateType))"
        )
        var nextQueue: [SnoopyClip] = []

        switch finishedClip.type {
        case .AS:
            print("🎬 AS 完成。队列 Halftone 过渡。")

            let requiredNumber = self.lastTransitionNumber
            print("🔍 Debug: lastTransitionNumber = \(requiredNumber ?? "nil")")

            guard let tmHide = findRandomClip(ofType: .TM_Hide, matchingNumber: requiredNumber)
            else {
                print("❌ Guard Failed: 找不到编号为 \(requiredNumber ?? "any") 的 TM_Hide")
                // Don't reset lastTransitionNumber here, keep it for potential retry
                break
            }

            // Only reset lastTransitionNumber after successful finding of TM_Hide
            self.lastTransitionNumber = nil
            print("✅ Guard OK: Found TM_Hide: \(tmHide.fileName)")

            guard let stHide = findMatchingST(for: tmHide, type: .ST_Hide) else {
                print("❌ Guard Failed: 找不到匹配 TM \(tmHide.number ?? "") 的 ST_Hide")
                break
            }
            print("✅ Guard OK: Found ST_Hide: \(stHide.fileName)")

            guard let randomRPH = findRandomClip(ofType: .RPH) else {
                print("❌ Guard Failed: 找不到随机 RPH")
                break
            }
            print("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

            guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: randomRPH.to) else {
                print(
                    "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")"
                )
                break
            }
            print("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

            // 检查是否已经存储了nextAfterAS，如果存储了就使用它
            if !nextAfterAS.isEmpty {
                print(
                    "🎬 AS完成，使用已存储的后续片段: \(nextAfterAS.map { $0.fileName }.joined(separator: ", "))")
                nextQueue = nextAfterAS
                nextAfterAS = []  // 清空存储，防止重复使用
            } else {
                // 🎬 修复：如果没有存储，生成序列时跳过TM_Hide和ST_Hide
                // TM_Hide通过直接调用处理，ST_Hide通过同步播放处理
                nextQueue = [randomRPH, targetBPNode]
                print("🎬 AS完成，使用新生成的后续片段（TM_Hide和ST_Hide通过其他机制处理）")
            }

        case .BP_Node:
            print("🎬 BP 节点完成循环。当前节点: \(currentNode ?? "nil"), 周期计数: \(bpCycleCount)")
            currentStateType = .decidingNextHalftoneAction

            if bpCycleCount >= 1 {
                print("🔄 已完成 \(bpCycleCount) 个 BP 周期，随机选择 AS, SS 或 Halftone 序列。")
                bpCycleCount = 0

                let choice = Double.random(in: 0..<1)
                let asProbability = 0.9
                let ssProbability = 0.0

                if choice < asProbability {
                    print("  选择生成 AS 序列。")
                    // 特殊处理：BP001有概率进入AS序列（使用固定006编号）
                    if currentNode == "BP001" {
                        print("🎯 BP001选择进入AS序列（使用固定006编号）")
                        nextQueue = generateBP001ASSequence()
                    } else {
                        nextQueue = generateASSequence(fromNode: currentNode)
                    }
                } else if choice < asProbability + ssProbability {
                    print("  选择生成 SS 序列。")
                    isPlayingSS = true  // 标记进入SS流程
                    nextQueue = generateSSSequenceNew(fromNode: currentNode)
                } else {
                    print("  选择生成 Halftone 转换序列 (继续)。")
                    guard let nodeName = currentNode else {
                        print("❌ 错误：BP_Node 完成时 currentNode 为 nil。回退。")
                        nextQueue = generateFallbackSequence()
                        break
                    }
                    let nextSequenceFileNames = SnoopyClip.generatePlaySequence(
                        currentNode: nodeName, clips: allClips)
                    nextQueue = nextSequenceFileNames.compactMap { findClip(byFileName: $0) }
                    if nextQueue.isEmpty {
                        print("⚠️ 未找到合适的 AP/CM/BP_To 转换。回退。")
                        nextQueue = generateFallbackSequence()
                    }
                }
            } else {
                print("  周期数未达 5 的倍数 (当前: \(bpCycleCount))，选择下一个 Halftone 动作。")

                guard let nodeName = currentNode else {
                    print("❌ 错误：BP_Node 完成时 currentNode 为 nil。回退。")
                    nextQueue = generateFallbackSequence()
                    break
                }
                let nextSequenceFileNames = SnoopyClip.generatePlaySequence(
                    currentNode: nodeName, clips: allClips)
                nextQueue = nextSequenceFileNames.compactMap { findClip(byFileName: $0) }
                if nextQueue.isEmpty {
                    print("⚠️ 未找到合适的 AP/CM/BP_To 转换。回退。")
                    nextQueue = generateFallbackSequence()
                }
            }

        case .AP_Outro, .CM, .BP_To, .RPH:
            print("🎬 \(finishedClip.type) 完成。转到节点: \(finishedClip.to ?? "nil")")

            if finishedClip.type == .RPH {
                // RPH完成，整个AS/SS → TM_Hide → ST_Hide → RPH序列结束，重置转场编号
                print("🔄 RPH完成，重置AS/SS转场编号")
                self.lastTransitionNumber = nil
                self.ssTransitionNumber = nil
                self.isPlayingSS = false

                // 检查RPH是否在预构建的序列中（下一个应该是BP_Node）
                if let nextClipInQueue = currentClipsQueue[safe: currentClipIndex + 1],
                    nextClipInQueue.type == .BP_Node
                {
                    print("🎬 RPH (part of sequence) 完成。继续序列到 BP_Node: \(nextClipInQueue.fileName)")
                    // 更新当前节点
                    self.currentNode = finishedClip.to
                    return
                } else {
                    // RPH不在预构建的序列中，需要生成新的BP_Node队列
                    self.currentNode = finishedClip.to
                    guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: self.currentNode)
                    else {
                        print("❌ 错误：找不到目标 BP 节点 \(self.currentNode ?? "nil")。回退。")
                        nextQueue = generateFallbackSequence()
                        break
                    }
                    print("✅ RPH 完成，队列目标 BP 节点: \(targetBPNode.fileName)")
                    nextQueue = [targetBPNode]
                    bpCycleCount += 1
                    print("🔄 增加 BP 周期计数至: \(bpCycleCount)")
                }
            } else if finishedClip.type == .BP_To {
                if finishedClip.to?.starts(with: "RPH") ?? false {
                    if let nextClipInQueue = currentClipsQueue[safe: currentClipIndex + 1],
                        nextClipInQueue.type == .ST_Reveal
                    {
                        print("🎬 BP_To_RPH (part of AS sequence) 完成。继续序列 (ST_Reveal)。")

                        // 清除所有存储的跳转后序列，防止循环
                        if !nextAfterAS.isEmpty || !nextAfterSS.isEmpty {
                            print("⚠️ BP_To_RPH序列开始，清除已存储的nextAfterAS/nextAfterSS防止循环")
                            nextAfterAS = []
                            nextAfterSS = []
                        }
                        return
                    } else {
                        guard let randomRPH = findRandomClip(ofType: .RPH) else {
                            print("❌ 错误：找不到任何 RPH 片段来处理 BP_To_RPH 完成。回退。")
                            nextQueue = generateFallbackSequence()
                            break
                        }
                        print("✅ BP_To_RPH 完成，队列随机 RPH: \(randomRPH.fileName)")
                        nextQueue = [randomRPH]
                    }
                } else {
                    self.currentNode = finishedClip.to
                    guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: self.currentNode)
                    else {
                        print("❌ 错误：找不到目标 BP 节点 \(self.currentNode ?? "nil")。回退。")
                        nextQueue = generateFallbackSequence()
                        break
                    }
                    print("✅ BP_To_BP 完成，队列目标 BP 节点: \(targetBPNode.fileName)")
                    nextQueue = [targetBPNode]
                    bpCycleCount += 1
                    print("🔄 增加 BP 周期计数至: \(bpCycleCount)")
                }
            } else {
                // 处理其他类型(.AP_Outro, .CM)
                self.currentNode = finishedClip.to
                guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: self.currentNode)
                else {
                    print("❌ 错误：找不到目标 BP 节点 \(self.currentNode ?? "nil")。回退。")
                    nextQueue = generateFallbackSequence()
                    break
                }
                print("✅ \(finishedClip.type) 完成，队列目标 BP 节点: \(targetBPNode.fileName)")
                nextQueue = [targetBPNode]
                bpCycleCount += 1
                print("🔄 增加 BP 周期计数至: \(bpCycleCount)")
            }

        case .ST_Hide, .ST_Reveal:
            print("🎬 \(finishedClip.type) 完成。继续序列。")
            return

        case .TM_Hide:
            print("🎬 TM_Hide 完成。生成 ST_Hide → RPH → BP_Node 序列。")

            guard let transitionNumber = finishedClip.number else {
                print("❌ Guard Failed: TM_Hide 没有有效的转场编号")
                break
            }

            guard let stHide = findMatchingST(forNumber: transitionNumber, type: .ST_Hide) else {
                print("❌ Guard Failed: 找不到匹配 TM \(transitionNumber) 的 ST_Hide")
                break
            }
            print("✅ Guard OK: Found ST_Hide: \(stHide.fileName)")

            guard let randomRPH = findRandomClip(ofType: .RPH) else {
                print("❌ Guard Failed: 找不到随机 RPH")
                break
            }
            print("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

            guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: randomRPH.to) else {
                print(
                    "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")"
                )
                break
            }
            print("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

            // 🎬 修复：ST_Hide通过同步播放处理，不应在队列中
            // 注意：这个分支理论上不应该被调用，因为TM_Hide通过heicSequenceMaskCompleted处理
            nextQueue = [randomRPH, targetBPNode]
            print(
                "🎬 TM_Hide完成（意外路径），跳过ST_Hide，序列: \(nextQueue.map { $0.fileName }.joined(separator: ", "))"
            )

        case .TM_Reveal:
            print("❌ 错误：TM 片段在主播放器序列生成中完成。")
            break

        case .SS_Outro:
            print("🎬 SS 完成。队列 Halftone 过渡。")

            let requiredNumber = self.lastTransitionNumber
            print("🔍 Debug: lastTransitionNumber = \(requiredNumber ?? "nil")")

            guard let tmHide = findRandomClip(ofType: .TM_Hide, matchingNumber: requiredNumber)
            else {
                print("❌ Guard Failed: 找不到编号为 \(requiredNumber ?? "any") 的 TM_Hide")
                // Don't reset lastTransitionNumber here, keep it for potential retry
                break
            }

            // Only reset lastTransitionNumber after successful finding of TM_Hide
            self.lastTransitionNumber = nil
            print("✅ Guard OK: Found TM_Hide: \(tmHide.fileName)")

            guard let stHide = findMatchingST(for: tmHide, type: .ST_Hide) else {
                print("❌ Guard Failed: 找不到匹配 TM \(tmHide.number ?? "") 的 ST_Hide")
                break
            }
            print("✅ Guard OK: Found ST_Hide: \(stHide.fileName)")

            guard let randomRPH = findRandomClip(ofType: .RPH) else {
                print("❌ Guard Failed: 找不到随机 RPH")
                break
            }
            print("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

            guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: randomRPH.to) else {
                print(
                    "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")"
                )
                break
            }
            print("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

            // 检查是否已经存储了nextAfterAS，如果存储了就使用它
            if !nextAfterAS.isEmpty {
                print(
                    "🎬 SS完成，使用已存储的后续片段: \(nextAfterAS.map { $0.fileName }.joined(separator: ", "))")
                nextQueue = nextAfterAS
                nextAfterAS = []  // 清空存储，防止重复使用
            } else {
                // 🎬 修复：如果没有存储，生成序列时跳过TM_Hide和ST_Hide
                // TM_Hide通过直接调用处理，ST_Hide通过同步播放处理
                nextQueue = [randomRPH, targetBPNode]
                print("🎬 SS完成，使用新生成的后续片段（TM_Hide和ST_Hide通过其他机制处理）")
            }

        case .SS_Intro, .SS_Loop, .AP_Intro, .AP_Loop:
            print("🎬 \(finishedClip.type) 完成。继续序列。")
            return

        default:
            print("⚠️ 未处理的片段类型完成: \(finishedClip.type)。使用随机 AS 重新开始。")
            nextQueue = generateFallbackSequence()
            bpCycleCount = 0
        }

        if !nextQueue.isEmpty {
            print("✅ 生成新队列，包含 \(nextQueue.count) 个片段。")
            self.currentClipsQueue = nextQueue
            self.currentClipIndex = -1
        } else if finishedClip.type != .ST_Hide && finishedClip.type != .ST_Reveal
            && finishedClip.type != .RPH && finishedClip.type != .SS_Outro
            && finishedClip.type != .SS_Intro && finishedClip.type != .SS_Loop
            && finishedClip.type != .AP_Intro && finishedClip.type != .AP_Loop
        {
            print(
                "❌ 无法为 \(finishedClip.fileName) 生成下一个序列。处理队列结束。"
            )
            handleEndOfQueue()
        }
    }

    private func handleEndOfQueue() {
        print(
            "❌ 意外到达队列末尾或序列生成失败。回退到随机 BP_Node。"
        )
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        let fallbackQueue = generateFallbackSequence()
        if !fallbackQueue.isEmpty {
            self.currentClipsQueue = fallbackQueue
            self.currentClipIndex = 0
            playNextClipInQueue()
        } else {
            print("❌ 严重错误：无法生成回退队列！停止播放。")
        }
    }

    // MARK: - Sequence Generation Helpers

    private func generateASSequence(fromNode: String? = nil) -> [SnoopyClip] {
        var sequence: [SnoopyClip] = []
        var transitionNumber: String? = nil

        if let nodeName = fromNode {
            let bpToRphCandidates = allClips.filter { clip in
                guard clip.type == .BP_To, clip.to?.starts(with: "RPH") ?? false else {
                    return false
                }
                let pattern = "_BP\(nodeName.suffix(3))_To_"
                return clip.fileName.contains(pattern)
            }

            if let bpToRph = bpToRphCandidates.randomElement() {
                print("  Prepending BP_To_RPH: \(bpToRph.fileName) to AS sequence.")
                sequence.append(bpToRph)
            } else {
                print(
                    "⚠️ Warning: Could not find BP_To_RPH for node \(nodeName) to prepend to AS sequence."
                )
            }
        }

        guard let randomTMReveal = findRandomClip(ofType: .TM_Reveal) else {
            print("❌ Error: Could not find random TM_Reveal for AS sequence.")
            return generateFallbackSequence()
        }
        transitionNumber = randomTMReveal.number
        print(
            "  Selected TM_Reveal: \(randomTMReveal.fileName) (Number: \(transitionNumber ?? "nil"))"
        )

        guard let matchingSTReveal = findMatchingST(for: randomTMReveal, type: .ST_Reveal) else {
            print(
                "❌ Error: Could not find matching ST_Reveal for TM number \(transitionNumber ?? "nil")."
            )
            return generateFallbackSequence()
        }
        print("  Selected ST_Reveal: \(matchingSTReveal.fileName)")

        guard let randomAS = findRandomClip(ofType: .AS) else {
            print("❌ Error: Could not find random AS clip.")
            return generateFallbackSequence()
        }
        print("  Selected AS: \(randomAS.fileName)")

        // 在此存储转场编号，以便AS播放完成后可以找到匹配的TM_Hide
        self.lastTransitionNumber = transitionNumber
        print("💾 Stored lastTransitionNumber: \(self.lastTransitionNumber ?? "nil")")

        // 找到匹配的TM_Hide，但不加入序列 - 这将在AS播放完成时使用
        guard let tmHide = findRandomClip(ofType: .TM_Hide, matchingNumber: transitionNumber)
        else {
            print("❌ Guard Failed: 找不到编号为 \(transitionNumber ?? "any") 的 TM_Hide")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found TM_Hide: \(tmHide.fileName) - 将在AS完成后使用")

        guard let stHide = findMatchingST(for: tmHide, type: .ST_Hide) else {
            print("❌ Guard Failed: 找不到匹配 TM \(tmHide.number ?? "") 的 ST_Hide")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found ST_Hide: \(stHide.fileName) - 将在TM_Hide完成后使用")

        guard let randomRPH = findRandomClip(ofType: .RPH) else {
            print("❌ Guard Failed: 找不到随机 RPH")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

        guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: randomRPH.to) else {
            print(
                "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

        // 关键修改: 序列中只包含ST_Reveal, TM_Reveal和AS
        // 其他部分(TM_Hide, ST_Hide, RPH, BP_Node)将在AS播放完成后单独处理
        sequence += [matchingSTReveal, randomTMReveal, randomAS]

        // 🎬 修复重复播放问题：nextAfterAS中不包含TM_Hide和ST_Hide
        // TM_Hide通过直接调用startTMHideTransition处理，ST_Hide通过同步播放处理
        // 为后续使用存储需要播放的部分（只包含RPH -> BP_Node）
        nextAfterAS = [randomRPH, targetBPNode]

        print(
            "✅ Generated AS sequence with \(sequence.count) clips. Stored \(nextAfterAS.count) clips for after AS (TM_Hide and ST_Hide excluded - handled separately)."
        )
        return sequence
    }

    private func generateBP001ASSequence() -> [SnoopyClip] {
        var sequence: [SnoopyClip] = []
        let fixedTransitionNumber: String = "006"  // 固定使用006编号

        print("🎯 生成BP001专用AS序列，使用固定转场编号: \(fixedTransitionNumber)")

        // 找到编号为006的TM_Reveal
        guard
            let tmReveal006 = findRandomClip(
                ofType: .TM_Reveal, matchingNumber: fixedTransitionNumber)
        else {
            print("❌ Error: 找不到编号为006的TM_Reveal")
            return generateFallbackSequence()
        }
        print("✅ 找到TM_Reveal: \(tmReveal006.fileName)")

        // 随机选择AS片段
        guard let randomAS = findRandomClip(ofType: .AS) else {
            print("❌ Error: 找不到AS片段")
            return generateFallbackSequence()
        }
        print("✅ 找到AS: \(randomAS.fileName)")

        // 存储转场编号，用于AS播放完成后找到匹配的TM_Hide
        self.lastTransitionNumber = fixedTransitionNumber
        print("💾 存储转场编号: \(self.lastTransitionNumber ?? "nil")")

        // 找到编号为006的TM_Hide
        guard
            let tmHide006 = findRandomClip(ofType: .TM_Hide, matchingNumber: fixedTransitionNumber)
        else {
            print("❌ Error: 找不到编号为006的TM_Hide")
            return generateFallbackSequence()
        }
        print("✅ 找到TM_Hide: \(tmHide006.fileName)")

        // 找到匹配的ST_Hide (A或B变体)
        guard let stHide = findMatchingST(for: tmHide006, type: .ST_Hide) else {
            print("❌ Error: 找不到匹配006编号的ST_Hide")
            return generateFallbackSequence()
        }
        print("✅ 找到ST_Hide: \(stHide.fileName) (变体: \(stHide.variant ?? "default"))")

        // 随机选择RPH
        guard let randomRPH = findRandomClip(ofType: .RPH) else {
            print("❌ Error: 找不到RPH片段")
            return generateFallbackSequence()
        }
        print("✅ 找到RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

        // 找到目标BP节点
        guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: randomRPH.to) else {
            print("❌ Error: 找不到RPH指向的BP节点 \(randomRPH.to ?? "nil")")
            return generateFallbackSequence()
        }
        print("✅ 找到目标BP节点: \(targetBPNode.fileName)")

        // 构建序列 TM_Reveal -> AS
        sequence = [tmReveal006, randomAS]

        // 🎬 修复BP001重复播放问题：nextAfterAS中不包含TM_Hide和ST_Hide
        // TM_Hide通过直接调用startTMHideTransition处理，ST_Hide通过同步播放处理
        // 存储后续片段：只包含 RPH -> BP_Node
        nextAfterAS = [randomRPH, targetBPNode]

        print(
            "🎯 BP001 AS序列生成完成: \(sequence.count)个片段，后续\(nextAfterAS.count)个片段（已跳过TM_Hide和ST_Hide）")
        print("  序列: \(sequence.map { $0.fileName }.joined(separator: " -> "))")
        print("  后续: \(nextAfterAS.map { $0.fileName }.joined(separator: " -> "))")
        print(
            "  注意: TM_Hide (\(tmHide006.fileName)) 通过直接调用处理，ST_Hide (\(stHide.fileName)) 通过同步播放处理")

        return sequence
    }

    private func generateSSSequenceNew(fromNode: String? = nil) -> [SnoopyClip] {
        var sequence: [SnoopyClip] = []
        let transitionNumber: String = "001"  // SS流程固定使用001编号

        print("🎬 生成SS序列，固定使用转场编号: \(transitionNumber)")

        if let nodeName = fromNode {
            let bpToRphCandidates = allClips.filter { clip in
                guard clip.type == .BP_To, clip.to?.starts(with: "RPH") ?? false else {
                    return false
                }

                let pattern = "_BP\(nodeName.suffix(3))_To_"
                return clip.fileName.contains(pattern)
            }

            if let bpToRph = bpToRphCandidates.randomElement() {
                print("  Prepending BP_To_RPH: \(bpToRph.fileName) to SS sequence.")
                sequence.append(bpToRph)
            } else {
                print(
                    "⚠️ Warning: Could not find BP_To_RPH for node \(nodeName) to prepend to SS sequence."
                )
            }
        }

        // 固定找到编号为001的ST_Reveal
        guard let stReveal001 = findMatchingST(forNumber: transitionNumber, type: .ST_Reveal)
        else {
            print(
                "❌ Error: Could not find ST001_Reveal for SS sequence."
            )
            return generateFallbackSequence()
        }
        print("  Selected ST_Reveal: \(stReveal001.fileName)")

        // 找到SS序列的三部分：Intro, Loop, Outro
        guard let ssIntro = findRandomClip(ofType: .SS_Intro) else {
            print("❌ Error: Could not find random ssIntro.")
            return generateFallbackSequence()
        }
        print("  Selected ssIntro: \(ssIntro.fileName)")

        guard let ssLoop = findRandomClip(ofType: .SS_Loop) else {
            print("❌ Error: Could not find random ssLoop.")
            return generateFallbackSequence()
        }
        print("  Selected ssLoop: \(ssLoop.fileName)")

        guard let ssOutro = findRandomClip(ofType: .SS_Outro) else {
            print("❌ Error: Could not find random ssOutro.")
            return generateFallbackSequence()
        }
        print("  Selected ssOutro: \(ssOutro.fileName)")

        // 存储SS专用编号，用于找到匹配的TM_Hide
        self.ssTransitionNumber = transitionNumber
        print("💾 Stored ssTransitionNumber: \(self.ssTransitionNumber ?? "nil")")

        print("🎬 SS 序列生成。规划SS完成后的Halftone过渡。")

        // SS流程：TM_Hide可以随机使用，但ST_Hide固定使用001编号
        guard let randomTMHide = findRandomClip(ofType: .TM_Hide) else {
            print("❌ Guard Failed: 找不到随机 TM_Hide")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found random TM_Hide: \(randomTMHide.fileName) - 将在SS完成后使用")

        // ST_Hide固定使用001编号
        guard let stHide001 = findMatchingST(forNumber: "001", type: .ST_Hide) else {
            print("❌ Guard Failed: 找不到编号为001的 ST_Hide")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found ST_Hide: \(stHide001.fileName) - 将在TM_Hide完成后使用")

        guard let randomRPH = findRandomClip(ofType: .RPH) else {
            print("❌ Guard Failed: 找不到随机 RPH")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found RPH: \(randomRPH.fileName) (to: \(randomRPH.to ?? "nil"))")

        guard let targetBPNode = findClip(ofType: .BP_Node, nodeName: randomRPH.to) else {
            print(
                "❌ Guard Failed: 找不到 RPH \(randomRPH.fileName) 指向的 BP 节点 \(randomRPH.to ?? "nil")")
            return generateFallbackSequence()
        }
        print("✅ Guard OK: Found Target BP_Node: \(targetBPNode.fileName)")

        // 当前序列只包括ST_Reveal和SS三部分
        sequence += [stReveal001, ssIntro, ssLoop, ssOutro]

        // 🎬 修复重复播放问题：nextAfterSS中不包含TM_Hide和ST_Hide
        // TM_Hide通过直接调用startTMHideTransition处理，ST_Hide通过同步播放处理
        // 为后续使用存储需要播放的部分（只包含RPH -> BP_Node） - 这将在SS_Outro播放完成后的延迟结束时使用
        nextAfterSS = [randomRPH, targetBPNode]

        print(
            "✅ Generated SS sequence with \(sequence.count) clips. Stored \(nextAfterSS.count) clips for after SS_Outro (TM_Hide and ST_Hide excluded - handled separately)."
        )
        return sequence
    }

    private func generateFallbackSequence() -> [SnoopyClip] {
        print("⚠️ 生成回退序列 (随机 BP_Node)。")
        guard let randomBPNode = findRandomClip(ofType: .BP_Node) else {
            print("❌ 严重错误：无法找到任何 BP_Node 片段进行回退！")
            return []
        }
        bpCycleCount = 0
        lastTransitionNumber = nil
        ssTransitionNumber = nil  // 重置SS转场编号
        isPlayingSS = false  // 重置SS标志
        currentNode = randomBPNode.node
        print("  回退到: \(randomBPNode.fileName)")
        return [randomBPNode]
    }

    // MARK: - Clip Finding Helpers

    private func findClip(byFileName fileName: String) -> SnoopyClip? {
        return allClips.first { $0.fileName == fileName }
    }

    private func findClip(
        ofType type: SnoopyClip.ClipType, nodeName: String? = nil, groupID: String? = nil
    ) -> SnoopyClip? {
        return allClips.first { clip in
            var match = clip.type == type
            if let targetNodeName = nodeName {
                match =
                    match
                    && (clip.node == targetNodeName || clip.from == targetNodeName
                        || clip.to == targetNodeName)
            }
            if let group = groupID {
                match = match && clip.groupID == group
            }
            return match
        }
    }

    private func findRandomClip(ofType type: SnoopyClip.ClipType, matchingNumber: String? = nil)
        -> SnoopyClip?
    {
        let candidates = allClips.filter { $0.type == type }

        // Add debugging for TM clips
        if type == .TM_Hide || type == .TM_Reveal {
            print("🔍 Debug TM clips:")
            for clip in candidates {
                print("  - \(clip.fileName) (number: \(clip.number ?? "nil"))")
            }
        }

        if let number = matchingNumber {
            let filteredByNumber = candidates.filter { $0.number == number }
            if !filteredByNumber.isEmpty {
                print("🔍 找到匹配编号 \(number) 的 \(type) 片段。")
                return filteredByNumber.randomElement()
            } else {
                print("⚠️ 警告: 未找到编号为 \(number) 的 \(type) 片段，将随机选择。")
                print(
                    "🔍 Available candidates: \(candidates.map { "\($0.fileName)(num:\($0.number ?? "nil"))" })"
                )

                // 对于TM类型，随机选择时排除006编号
                if type == .TM_Hide || type == .TM_Reveal {
                    let filteredCandidates = candidates.filter { $0.number != "006" }
                    if !filteredCandidates.isEmpty {
                        print("🔍 排除006编号后，从 \(filteredCandidates.count) 个候选中随机选择")
                        return filteredCandidates.randomElement()
                    } else {
                        print("⚠️ 排除006后没有可用的TM片段，使用原始候选")
                        return candidates.randomElement()
                    }
                } else {
                    return candidates.randomElement()
                }
            }
        } else {
            // 对于TM类型，随机选择时排除006编号
            if type == .TM_Hide || type == .TM_Reveal {
                let filteredCandidates = candidates.filter { $0.number != "006" }
                if !filteredCandidates.isEmpty {
                    print("🔍 排除006编号后，从 \(filteredCandidates.count) 个TM候选中随机选择")
                    return filteredCandidates.randomElement()
                } else {
                    print("⚠️ 排除006后没有可用的TM片段，使用原始候选")
                    return candidates.randomElement()
                }
            } else {
                return candidates.randomElement()
            }
        }
    }

    private func findMatchingST(
        for tmClip: SnoopyClip? = nil, forNumber number: String? = nil, type: SnoopyClip.ClipType
    ) -> SnoopyClip? {
        guard type == .ST_Hide || type == .ST_Reveal else { return nil }
        let targetNumber = tmClip?.number ?? number
        guard let num = targetNumber else { return nil }

        let matchingSTs = allClips.filter { $0.type == type && $0.number == num }

        if matchingSTs.isEmpty {
            print("⚠️ 警告：未找到匹配的 \(type) 片段，编号为 \(num)")
            return nil
        }

        let variants = matchingSTs.filter { $0.variant != nil }
        if !variants.isEmpty {
            return variants.randomElement()
        } else {
            return matchingSTs.first
        }
    }

    private func findClipForPlayerItem(_ item: AVPlayerItem) -> SnoopyClip? {
        guard let url = (item.asset as? AVURLAsset)?.url else { return nil }
        return allClips.first { clip in
            if let clipUrl = Bundle(for: type(of: self)).url(
                forResource: clip.fileName, withExtension: nil)
            {
                return clipUrl == url
            }
            return false
        }
    }

    // MARK: - Background Update Functions

    private func updateBackgrounds() {
        print("🔄 更新背景...")

        // 检查并确保半色调层可见
        if let halftoneNode = self.halftoneNode {
            halftoneNode.alpha = 0.3  // 设置适当的透明度
        }

        updateBackgroundColor()
        updateBackgroundImage()
    }

    private func updateBackgroundColor() {
        guard let bgNode = self.backgroundColorNode else { return }
        let randomColor = colors.randomElement() ?? .black
        bgNode.color = randomColor
        bgNode.alpha = 1  // 显示背景颜色
        print("🎨 背景颜色更新为: \(randomColor)")
    }

    private func updateBackgroundImage() {
        guard let imageNode = self.backgroundImageNode, !backgroundImages.isEmpty else { return }

        let randomImageName = backgroundImages.randomElement()!
        guard
            let imagePath = Bundle(for: type(of: self)).path(
                forResource: randomImageName, ofType: nil),
            let image = NSImage(contentsOfFile: imagePath)
        else {
            print("❌ 无法加载背景图片: \(randomImageName)")
            return
        }

        let texture = SKTexture(image: image)
        imageNode.texture = texture

        guard let scene = self.scene else { return }

        let imageAspect = image.size.height / scene.size.height
        guard imageAspect > 0 else {
            print("❌ 错误: IS 图片高度或场景高度为零，无法计算 imageAspect。")
            return
        }
        imageNode.size = CGSize(
            width: image.size.width / imageAspect * scale,
            height: scene.size.height * scale)
        imageNode.position = CGPoint(
            x: scene.size.width / 2,
            y: scene.size.height / 2 - scene.size.height * offside)
        imageNode.alpha = 1  // 显示背景图片

        print("🖼️ 背景图片更新为: \(randomImageName)")
    }

    // MARK: - Overlay (VI/WE) Functions

    private func tryPlayVIWEOverlay() {
        guard overlayPlayerItem == nil else {
            print("🚫 叠加层已在播放，跳过新的触发。")
            return
        }

        let viClips = allClips.filter { $0.type == .VI_Single || $0.type == .VI_Intro }
        let weClips = allClips.filter { $0.type == .WE_Single || $0.type == .WE_Intro }
        let candidates = viClips + weClips

        guard let clipToPlay = candidates.randomElement() else {
            print("🤷 没有可用的 VI/WE 片段可供播放。")
            return
        }

        print("✨ 触发叠加效果: \(clipToPlay.fileName)")
        playOverlayClip(clipToPlay)
    }

    private func playOverlayClip(_ clip: SnoopyClip) {
        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: clip.fileName, withExtension: nil)
        else {
            print("❌ 错误：找不到叠加片段文件 \(clip.fileName)")
            cleanupOverlay()
            return
        }

        let newItem = AVPlayerItem(url: url)
        self.overlayPlayerItem = newItem

        // 不再需要设置overlayRepeatCount，Loop的继续由主序列状态决定
        self.overlayRepeatCount = 0
        print("📽️ 播放叠加片段: \(clip.fileName)，Loop控制由主序列状态决定")

        overlayPlayer?.removeAllItems()
        overlayPlayer?.insert(newItem, after: nil)
        overlayNode?.isHidden = false
        overlayPlayer?.play()
        print("▶️ 播放叠加片段: \(clip.fileName)")
    }

    private func cleanupOverlay() {
        print("🧹 清理叠加层。")
        overlayPlayer?.pause()
        overlayPlayer?.removeAllItems()
        overlayPlayerItem = nil
        overlayNode?.isHidden = true
        overlayRepeatCount = 0
    }

    private func isCurrentlyInBPCycle() -> Bool {
        // 检查主序列是否仍在BP循环状态中
        let isBPLooping = (currentStateType == .playingBP || currentStateType == .playingAPLoop)

        // 额外检查：如果当前队列中包含正在循环的BP_Node或AP_Loop
        let hasLoopingClip =
            currentClipIndex < currentClipsQueue.count
            && (currentClipsQueue[currentClipIndex].type == .BP_Node
                || currentClipsQueue[currentClipIndex].type == .AP_Loop)
            && currentRepeatCount > 0

        let result = isBPLooping || hasLoopingClip
        print(
            "🔍 isCurrentlyInBPCycle: \(result) (状态: \(currentStateType), 重复次数: \(currentRepeatCount))"
        )
        return result
    }

    private func handleOverlayItemFinish(finishedItem: AVPlayerItem) {
        print("✅ 叠加片段播放完成。")

        var lastPlayedClip: SnoopyClip? = nil
        if let finishedUrl = (finishedItem.asset as? AVURLAsset)?.url {
            lastPlayedClip = allClips.first(where: { clip in
                if let clipUrl = Bundle(for: type(of: self)).url(
                    forResource: clip.fileName, withExtension: nil)
                {
                    return clipUrl == finishedUrl
                }
                return false
            })
        }

        guard let finishedClip = lastPlayedClip else {
            print("❌ 无法找到完成的叠加项目的 SnoopyClip。清理。")
            cleanupOverlay()
            return
        }

        print(
            "🔍 完成的overlay片段: \(finishedClip.fileName) (类型: \(finishedClip.type), groupID: \(finishedClip.groupID ?? "nil"))"
        )
        print("🔍 主序列状态: \(currentStateType)")

        var nextOverlayClip: SnoopyClip? = nil
        let groupID = finishedClip.groupID

        if finishedClip.type == SnoopyClip.ClipType.VI_Intro
            || finishedClip.type == SnoopyClip.ClipType.WE_Intro
        {
            let loopType: SnoopyClip.ClipType =
                (finishedClip.type == .VI_Intro) ? .VI_Loop : .WE_Loop
            nextOverlayClip = findClip(ofType: loopType, groupID: groupID)
            if let nextClip = nextOverlayClip {
                print("✅ 叠加 Intro 完成，队列 Loop: \(nextClip.fileName)")
            } else {
                print(
                    "❌ 叠加 Intro 完成，但未找到组 \(groupID ?? "nil") 的 Loop。清理。"
                )
            }
        } else if finishedClip.type == SnoopyClip.ClipType.VI_Loop
            || finishedClip.type == SnoopyClip.ClipType.WE_Loop
        {
            // 检查主序列是否仍在BP循环中，而不是使用overlayRepeatCount
            if isCurrentlyInBPCycle() {
                // 主序列仍在BP循环中，继续播放Loop
                nextOverlayClip = finishedClip
                print("🔁 叠加 Loop 完成，主序列仍在BP循环中，继续播放Loop")
            } else {
                // 主序列已退出BP循环，强制进入Outro
                let outroType: SnoopyClip.ClipType =
                    (finishedClip.type == .VI_Loop) ? .VI_Outro : .WE_Outro
                nextOverlayClip = findClip(ofType: outroType, groupID: groupID)
                print(
                    "✅ 叠加 Loop 完成，主序列已退出BP循环，强制进入Outro: \(nextOverlayClip?.fileName ?? "未找到")"
                )
            }
        }

        if let nextClip = nextOverlayClip {
            playOverlayClip(nextClip)
        } else {
            print(
                "✅ 叠加序列完成或未找到组 \(groupID ?? "nil") 的下一个片段。清理。"
            )
            cleanupOverlay()
        }
    }

    private func interruptOverlayLoopAndPlayOutro(groupID: String) {
        print("💥 请求中断overlay Loop，groupID: \(groupID)")

        let outroType: SnoopyClip.ClipType?
        if findClip(ofType: .VI_Loop, groupID: groupID) != nil {
            outroType = .VI_Outro
        } else if findClip(ofType: .WE_Loop, groupID: groupID) != nil {
            outroType = .WE_Outro
        } else {
            outroType = nil
        }

        guard let type = outroType, let outroClip = findClip(ofType: type, groupID: groupID) else {
            print("⚠️ 无法找到组 \(groupID) 的 Outro 来打断 Loop。")
            cleanupOverlay()
            return
        }

        print("💥 打断叠加 Loop，播放 Outro: \(outroClip.fileName)")
        overlayRepeatCount = 0  // 重置重复计数，强制结束Loop
        playOverlayClip(outroClip)
    }

    /// 检查并中断当前活跃的 VI/WE loop（用于 BP→AS 流程中的 ST_Hide 播放）
    private func checkAndInterruptActiveOverlayLoop() {
        // 检查是否有活跃的 overlay 播放
        guard let currentItem = overlayPlayerItem else {
            print("🔍 没有活跃的 overlay 播放，无需中断")
            return
        }

        // 通过当前播放的 item 找到对应的 clip
        guard let currentUrl = (currentItem.asset as? AVURLAsset)?.url else {
            print("❌ 无法获取当前 overlay 播放的 URL")
            return
        }

        let currentClip = allClips.first { clip in
            if let clipUrl = Bundle(for: type(of: self)).url(
                forResource: clip.fileName, withExtension: nil)
            {
                return clipUrl == currentUrl
            }
            return false
        }

        guard let clip = currentClip else {
            print("❌ 无法找到当前播放的 overlay clip")
            return
        }

        // 检查是否为 VI/WE loop
        if clip.type == .VI_Loop || clip.type == .WE_Loop {
            print("🎯 检测到活跃的 \(clip.type) loop: \(clip.fileName)，准备中断")
            if let groupID = clip.groupID {
                interruptOverlayLoopAndPlayOutro(groupID: groupID)
            } else {
                print("⚠️ VI/WE loop 缺少 groupID，强制清理 overlay")
                cleanupOverlay()
            }
        } else {
            print("🔍 当前 overlay (\(clip.fileName)) 不是 loop 类型，无需中断")
        }
    }

    // MARK: - Masking Functions

    private func startMaskTransitionWithHEIC(
        basePattern: String, tmClip: SnoopyClip, contentClip: SnoopyClip?, isRevealing: Bool
    ) {
        print("🎭 开始HEIC遮罩过渡: \(basePattern), TM片段: \(tmClip.fileName), 显示: \(isRevealing)")
        guard let scene = self.scene else {
            print("❌ 错误：HEIC遮罩过渡缺少场景组件。")
            currentClipIndex += 1
            playNextClipInQueue()
            return
        }

        isMasking = true

        // 创建mask sprite node如果不存在
        if self.tmMaskSpriteNode == nil {
            let maskNode = SKSpriteNode(color: .clear, size: scene.size)
            maskNode.position = .zero  // 相对于cropNode的位置
            self.tmMaskSpriteNode = maskNode
        }

        guard let maskNode = self.tmMaskSpriteNode,
            let outlineNode = self.tmOutlineSpriteNode,
            let asVideoNode = self.asVideoNode,  // Use AS video node instead of main video node
            let heicPlayer = self.heicSequencePlayer
        else {
            print("❌ 错误：HEIC遮罩过渡缺少视频节点组件。")
            isMasking = false
            currentClipIndex += 1
            playNextClipInQueue()
            return
        }

        // 设置maskNode尺寸
        maskNode.size = scene.size
        maskNode.position = .zero  // 相对于cropNode

        // 创建或重用cropNode来应用遮罩效果
        guard let cropNode = self.cropNode else {
            print("❌ 错误：cropNode应该在初始化时已创建")
            isMasking = false
            currentClipIndex += 1
            playNextClipInQueue()
            return
        }

        // cropNode始终保持在zPosition=10，不需要调整层级

        // 移除旧的子节点和父节点关系 - AS video node is already in cropNode
        // No need to move asVideoNode since it's already positioned correctly in cropNode

        // 将maskNode设置为cropNode的mask
        cropNode.maskNode = maskNode

        if isRevealing {
            // TM_Reveal: 显示AS/SS
            guard let contentClip = contentClip else {
                print("❌ 错误：HEIC显示过渡缺少内容片段 (AS/SS)。")
                isMasking = false
                currentClipIndex += 1
                playNextClipInQueue()
                return
            }

            print("🔄 准备显示内容: \(contentClip.fileName)")

            // 🎬 新增：准备AS同步播放
            let syncPrepared = prepareSyncASForTMReveal(asClip: contentClip)
            if !syncPrepared {
                print("❌ 错误：无法准备AS同步播放")
                isMasking = false
                currentClipIndex += 1
                playNextClipInQueue()
                return
            }

            // 确保AS视频节点可见
            asVideoNode.isHidden = false

            if contentClip.type == .AS {
                // 更新当前状态
                currentStateType = .playingTMReveal
                // 使用TM_Reveal的编号而不是AS的编号，因为AS通常没有编号
                self.lastTransitionNumber = tmClip.number
                print("💾 TM_Reveal过渡期间存储转场编号: \(self.lastTransitionNumber ?? "nil")")
            } else if contentClip.type == .SS_Intro {
                currentStateType = .playingSSIntro
            }

            // 🎬 新增：TM_Reveal开始播放时，同步开始AS播放
            startSyncASPlayback()

            // 开始播放双层HEIC序列（mask + outline）
            heicPlayer.playDual(maskNode: maskNode, outlineNode: outlineNode) { [weak self] in
                DispatchQueue.main.async {
                    self?.heicSequenceMaskCompleted(
                        isRevealing: true, tmClip: tmClip, basePattern: basePattern)
                }
            }
        } else {
            // TM_Hide: 隐藏当前内容
            if self.currentStateType == .playingAS {
                currentStateType = .transitioningToHalftoneHide
            }

            // 播放双层HEIC序列（mask + outline）
            heicPlayer.playDual(maskNode: maskNode, outlineNode: outlineNode) { [weak self] in
                DispatchQueue.main.async {
                    self?.heicSequenceMaskCompleted(
                        isRevealing: false, tmClip: tmClip, basePattern: basePattern)
                }
            }
        }
    }

    private func heicSequenceMaskCompleted(
        isRevealing: Bool, tmClip: SnoopyClip, basePattern: String
    ) {
        print("✅ HEIC遮罩序列完成: \(basePattern), 显示: \(isRevealing), TM片段: \(tmClip.fileName)")

        if isRevealing {
            // TM_Reveal完成：AS/SS内容已经在同步播放
            print("▶️ TM_Reveal完成，AS/SS内容已通过同步播放开始")

            // AS已经在同步播放，不需要再次启动
            // asPlayer?.play()  // 注释掉，因为AS已经在同步播放

            // 如果当前播放的是AS，跳过队列中的AS，等待AS播放完成
            if currentStateType == .playingTMReveal
                && currentClipIndex + 1 < currentClipsQueue.count
                && currentClipsQueue[currentClipIndex + 1].type == .AS
            {
                print("🔄 AS通过同步播放显示，跳过队列中的AS片段")
                currentClipIndex += 1  // 移到AS
                // 不调用playNextClipInQueue()，等待AS播放完成
                // AS播放完成时会触发asPlaybackEnded，那时再处理后续逻辑
            } else {
                // 其他情况（如SS_Intro），继续队列处理
                print("▶️ 继续队列处理")
                playNextClipInQueue()
            }
        } else {
            // TM_Hide完成：隐藏AS/SS内容并继续到下一个序列
            print("▶️ TM_Hide完成，隐藏AS/SS内容并继续到下一个序列")

            // 隐藏AS视频节点
            if let asVideoNode = self.asVideoNode {
                asVideoNode.isHidden = true
            }

            // 暂停AS播放器
            asPlayer?.pause()

            // 使用当前TM_Hide片段的编号来生成ST_Hide序列
            let transitionNumber = tmClip.number
            print("🔍 使用TM_Hide编号生成序列: \(transitionNumber ?? "nil")")

            // 根据是AS还是SS流程使用不同的预存队列
            let nextQueue = isPlayingSS ? nextAfterSS : nextAfterAS

            if !nextQueue.isEmpty {
                print("🔄 使用预存队列: \(nextQueue.count) 片段 (来源: \(isPlayingSS ? "SS" : "AS"))")

                // 🎬 关键简化：由于ST_Hide总是通过同步播放处理，始终跳过队列中的ST_Hide
                let queueToUse: [SnoopyClip]
                if nextQueue.count >= 1 && nextQueue[0].type == .ST_Hide {
                    print("⏭️ ST_Hide通过同步播放处理，跳过队列中的ST_Hide，直接使用后续片段")
                    queueToUse = Array(nextQueue.dropFirst())  // 跳过第一个ST_Hide
                } else {
                    queueToUse = nextQueue
                }

                currentClipsQueue = queueToUse
                currentClipIndex = 0

                // 清空相应的预存队列
                if isPlayingSS {
                    nextAfterSS = []
                } else {
                    nextAfterAS = []
                }
            } else {
                print("🔄 没有预存队列，生成RPH → BP_Node序列（ST_Hide通过同步播放处理）")

                // 🎬 简化逻辑：ST_Hide总是通过同步播放处理，直接生成RPH → BP_Node序列
                if let randomRPH = findRandomClip(ofType: .RPH),
                    let targetBPNode = findClip(ofType: .BP_Node, nodeName: randomRPH.to)
                {

                    currentClipsQueue = [randomRPH, targetBPNode]
                    currentClipIndex = 0
                    print("✅ 生成RPH → BP_Node序列，ST_Hide通过同步播放处理")
                } else {
                    print("❌ 无法生成RPH → BP_Node序列，使用回退序列")
                    let fallbackQueue = generateFallbackSequence()
                    if !fallbackQueue.isEmpty {
                        currentClipsQueue = fallbackQueue
                        currentClipIndex = 0
                    }
                }
            }

            // 如果刚完成SS流程，重置SS标志并清理SS相关变量
            if isPlayingSS {
                print("🎬 SS流程完成，重置SS标志")
                isPlayingSS = false
                ssTransitionNumber = nil
            }
        }

        // 清理cropNode遮罩效果和outline显示
        if let cropNode = self.cropNode {
            // 清除遮罩效果
            cropNode.maskNode = nil
            print("🧹 清理cropNode遮罩效果")

            // AS视频节点始终保持在cropNode中，不需要移动
            // cropNode will be reused for future AS/SS content with masking
        }

        // 隐藏outline节点
        if let outlineNode = self.tmOutlineSpriteNode {
            outlineNode.isHidden = true
            print("🧹 隐藏TM outline节点")
        }

        // 重置状态
        isMasking = false

        // TM_Reveal的情况已经在上面处理过了，这里只处理TM_Hide的情况
        if !isRevealing {
            // 🎬 简化逻辑：ST_Hide总是通过同步播放处理，等待其完成再继续队列
            print("⏸️ TM_Hide完成，等待ST_Hide同步播放完成再继续队列")
            // 不调用playNextClipInQueue()，等待ST_Hide播放完成
        }
        // TM_Reveal的情况在上面已经处理，这里不需要额外的队列处理
    }

    /// 检查ST_Reveal和TM_Reveal是否都完成，如果是则继续播放（方案2）
    private func checkDualCompletionAndContinue() {
        print("🔍 检查双重完成状态：ST_Reveal=\(stRevealCompleted), TM_Reveal=\(tmRevealCompleted)")

        guard isWaitingForDualCompletion else {
            print("⚠️ 不在等待双重完成状态，忽略")
            return
        }

        if stRevealCompleted && tmRevealCompleted {
            print("✅ ST_Reveal和TM_Reveal都已完成，继续播放序列")

            // 重置状态
            isWaitingForDualCompletion = false
            stRevealCompleted = false
            tmRevealCompleted = false
            isMasking = false

            // 清理cropNode遮罩效果和outline显示
            if let cropNode = self.cropNode {
                cropNode.maskNode = nil
                print("🧹 清理cropNode遮罩效果")
            }

            // 隐藏outline节点
            if let outlineNode = self.tmOutlineSpriteNode {
                outlineNode.isHidden = true
                print("🧹 隐藏TM outline节点")
            }

            // 方案2中AS已经通过同步播放开始，不需要重新播放
            // 只需要跳过ST_Reveal和TM_Reveal的索引，等待AS自然完成
            currentClipIndex += 2  // 跳过ST_Reveal和TM_Reveal
            print("🔍 方案2：AS已通过同步播放开始，等待其自然完成，当前索引跳转到: \(currentClipIndex)")
            // 不调用playNextClipInQueue()，让AS自然播放完成
        } else {
            print("⏳ 等待另一个播放完成...")
        }
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
