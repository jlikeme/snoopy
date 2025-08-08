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
    private var sequenceManager: SequenceManager!
    private var weatherManager: WeatherManager!

    private var skView: SKView!
    private var isSetupComplete = false
    private var allClips: [AnimationClipMetadata] = []

    // MARK: - 初始化

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit(frame: bounds)
    }

    private func commonInit(frame: NSRect) {
        animationTimeInterval = 1.0 / 24.0

        // 在Sonoma上延迟初始化，避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.performSetup(frame: frame)
            }
        } else {
            performSetup(frame: frame)
        }

        setNotifications()
    }

    private func performSetup(frame: NSRect) {
        guard !isSetupComplete else { return }

        debugLog("Performing setup bounds: \(bounds), frame: \(frame)")
        // 1. 设置 SpriteKit 视图
        var skViewFrame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        if bounds.width < frame.width && bounds.height < frame.height {
            // 如果 bounds 小于 frame，使用 bounds 的大小，适配SnoopyPreview app
            skViewFrame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        }
        
        skView = SKView(frame: skViewFrame)
        skView.autoresizingMask = [.width, .height]
        addSubview(skView)

        // 2. 初始化基本管理器
        stateManager = StateManager()
        playerManager = PlayerManager()
        weatherManager = WeatherManager()
        sceneManager = SceneManager(bounds: skViewFrame, weatherManager: weatherManager)

        // 3. 异步加载视频片段
        Task {
            do {
                debugLog("Loading clips...")
                let assetClips = AssetClipLoader.loadAllClips()
                self.allClips = assetClips
                debugLog("Clips loaded: \(self.allClips.count)")

                guard !self.allClips.isEmpty else {
                    debugLog("No clips loaded, cannot start.")
                    return
                }

                // 现在我们有了视频片段，初始化依赖序列的管理器
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    // 初始化依赖序列的管理器
                    self.sequenceManager = SequenceManager(stateManager: self.stateManager, sceneManager: sceneManager, allClips: self.allClips)
                    self.stateManager.allClips = self.allClips

                    // 最后创建协调一切的播放管理器
                    self.playbackManager = PlaybackManager(
                        stateManager: self.stateManager,
                        playerManager: self.playerManager,
                        sceneManager: self.sceneManager
                    )

                    // 设置播放管理器的序列管理器和叠加层管理器
                    self.playbackManager.setSequenceManager(self.sequenceManager)

                    // 4. 设置场景并完成初始化
                    if let scene = self.sceneManager.scene {
                        scene.delegate = self
                        self.skView.presentScene(scene)
                    }

                    // 5. 在场景中设置视频节点
                    self.sceneManager.setupScene(
                        playerManager: self.playerManager,
                        allClips: assetClips
                    )

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
        playbackManager.startInitialPlayback()
    }
}
