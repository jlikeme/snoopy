import AVFoundation
import ScreenSaver
import SpriteKit

@objc(SnoopyScreenSaverView)
class SnoopyScreenSaverView: ScreenSaverView, SKSceneDelegate {

    // 所有管理器
    private var stateManager: StateManager!
    private var sceneManager: SceneManager!
    private var playerManager: PlayerManager!
    private var playbackManager: PlaybackManager!
    private var transitionManager: TransitionManager!
    private var sequenceManager: SequenceManager!
    private var overlayManager: OverlayManager!
    private var weatherManager: WeatherManager!

    private var skView: SKView!
    private var isSetupComplete = false
    private var allClips: [SnoopyClip] = []

    // MARK: - 初始化

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        animationTimeInterval = 1.0 / 24.0

        // 在Sonoma上延迟初始化，避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.performSetup()
            }
        } else {
            performSetup()
        }

        setNotifications()
    }

    private func performSetup() {
        guard !isSetupComplete else { return }

        // 1. 设置 SpriteKit 视图
        skView = SKView(frame: bounds)
        skView.autoresizingMask = [.width, .height]
        addSubview(skView)

        // 2. 初始化基本管理器
        stateManager = StateManager()
        playerManager = PlayerManager()
        weatherManager = WeatherManager()
        sceneManager = SceneManager(bounds: bounds, weatherManager: weatherManager)

        // 3. 异步加载视频片段
        Task {
            do {
                debugLog("Loading clips...")
                self.allClips = try await SnoopyClip.loadClips()
                debugLog("Clips loaded: \(self.allClips.count)")

                guard !self.allClips.isEmpty else {
                    debugLog("No clips loaded, cannot start.")
                    return
                }

                // 现在我们有了视频片段，初始化依赖序列的管理器
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    // 初始化依赖序列的管理器
                    self.sequenceManager = SequenceManager(stateManager: self.stateManager)
                    self.stateManager.allClips = self.allClips

                    // 初始化需要视频片段的管理器
                    self.overlayManager = OverlayManager(
                        allClips: self.allClips,
                        weatherManager: self.weatherManager,
                        stateManager: self.stateManager
                    )

                    self.transitionManager = TransitionManager(
                        stateManager: self.stateManager,
                        playerManager: self.playerManager,
                        sceneManager: self.sceneManager
                    )

                    // 最后创建协调一切的播放管理器
                    self.playbackManager = PlaybackManager(
                        stateManager: self.stateManager,
                        playerManager: self.playerManager,
                        sceneManager: self.sceneManager,
                        transitionManager: self.transitionManager
                    )

                    // 设置各管理器之间的依赖关系
                    self.transitionManager.setDependencies(
                        playbackManager: self.playbackManager,
                        sequenceManager: self.sequenceManager,
                        overlayManager: self.overlayManager
                    )

                    // 设置播放管理器的序列管理器和叠加层管理器
                    self.playbackManager.setSequenceManager(self.sequenceManager)
                    self.playbackManager.setOverlayManager(self.overlayManager)

                    // 4. 设置场景并完成初始化
                    if let scene = self.sceneManager.scene {
                        scene.delegate = self
                        self.skView.presentScene(scene)
                    }

                    // 5. 在场景中设置视频节点
                    self.sceneManager.setupScene(
                        mainPlayer: self.playerManager.queuePlayer,
                        overlayPlayer: self.playerManager.overlayPlayer,
                        asPlayer: self.playerManager.asPlayer
                    )

                    // 6. 在场景中设置覆盖节点
                    if let scene = self.sceneManager.scene {
                        self.overlayManager.setupOverlayNode(in: scene)
                    }

                    // 7. 检查天气（如果适用）
                    self.weatherManager.startWeatherUpdate()

                    // 8. 标记设置为完成
                    self.isSetupComplete = true

                    // 9. 如果动画已经开始，现在开始播放
                    if self.isAnimating {
                        self.setupInitialStateAndPlay()
                    }
                }
            } catch {
                debugLog("Error loading clips: \(error)")
            }
        }
    }

    deinit {
        NSLog("SnoopyScreenSaverView 正在释放资源")
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        playerManager?.queuePlayer.pause()
        playerManager?.overlayPlayer.pause()
        playerManager?.asPlayer.pause()

        // 清理 SKView 以避免内存泄漏
        skView?.presentScene(nil)
    }

    // MARK: - ScreenSaverView 生命周期

    override func startAnimation() {
        super.startAnimation()

        if isSetupComplete && sequenceManager != nil {
            setupInitialStateAndPlay()
        }
        // 否则，完成设置后将处理
    }

    override func stopAnimation() {
        super.stopAnimation()

        // 暂停所有播放器
        playerManager?.queuePlayer.pause()
        playerManager?.overlayPlayer.pause()
        playerManager?.asPlayer.pause()
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)
    }

    // 添加此静态方法以支持现代屏幕保护程序引擎
    @objc static func isCompatibleWithModernScreenSaverEngine() -> Bool {
        return true
    }

    // 设置通知观察者
    private func setNotifications() {
        // 监听屏幕保护程序将要停止的通知
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(willStop(_:)),
            name: Notification.Name("com.apple.screensaver.willstop"),
            object: nil
        )

        // 监听屏幕保护程序将要开始的通知
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(willStart(_:)),
            name: Notification.Name("com.apple.screensaver.willstart"),
            object: nil
        )

        // 监听系统睡眠的通知
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onSleepNote(note:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    // 屏幕保护程序将要停止
    @objc private func willStop(_ notification: Notification) {
        debugLog("屏保将要停止")

        // 在Sonoma上，直接退出进程避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.async {
                exit(0)
            }
        }

        stopAnimation()
    }

    // 屏幕保护程序将要开始
    @objc private func willStart(_ notification: Notification) {
        debugLog("屏保将要开始")
    }

    // 系统将要睡眠
    @objc private func onSleepNote(note: Notification) {
        debugLog("系统将要睡眠")

        // 在Sonoma上，直接退出进程避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.async {
                exit(0)
            }
        }
    }

    // MARK: - SKSceneDelegate

    func update(_ currentTime: TimeInterval, for scene: SKScene) {
        // 目前暂不实现
    }

    private func setupInitialStateAndPlay() {
        debugLog("Setting up initial state...")
        guard let initialAS = sequenceManager.findRandomClip(ofType: .AS) else {
            debugLog("Error: No AS clips found to start.")
            return
        }
        debugLog("Initial AS: \(initialAS.fileName)")

        // 为初始AS设置随机转场编号，排除006
        let availableTransitionNumbers = allClips.compactMap { clip in
            guard clip.type == .TM_Hide else { return nil }
            return clip.number
        }.filter { $0 != "006" }  // 排除006编号

        if let randomNumber = availableTransitionNumbers.randomElement() {
            stateManager.lastTransitionNumber = randomNumber
            debugLog("🎲 为初始AS设置随机转场编号: \(randomNumber)")
        } else {
            debugLog("⚠️ 警告：无法找到可用的转场编号")
        }

        stateManager.currentStateType = .playingAS
        stateManager.currentClipsQueue = [initialAS]
        stateManager.currentClipIndex = 0
        playbackManager.playNextClipInQueue()
    }
}
