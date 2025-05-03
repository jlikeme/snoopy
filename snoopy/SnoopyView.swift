// SnoopyScreenSaverView.swift

import ScreenSaver
import AVFoundation
import AVKit
import SpriteKit

@objc(SnoopyScreenSaverView)
class SnoopyScreenSaverView: ScreenSaverView {
    // 常量
    private let scale: CGFloat = 720.0 / 1080.0
    private let offside: CGFloat = 180.0 / 1080.0
    
    // 属性
    private var queuePlayer: AVQueuePlayer?
    private var skView: SKView?
    private var scene: SKScene?
    private var index: Int = 0
    private var videoURLs: [String] = []
    
    private let colors: [NSColor] = [
        NSColor(red: 50.0/255.0, green: 60.0/255.0, blue: 47.0/255.0, alpha: 1.0),
        NSColor(red: 5.0/255.0, green: 168.0/255.0, blue: 157.0/255.0, alpha: 1.0),
        NSColor(red: 65.0/255.0, green: 176.0/255.0, blue: 246.0/255.0, alpha: 1.0),
        NSColor(red: 238.0/255.0, green: 95.0/255.0, blue: 167.0/255.0, alpha: 1.0),
        NSColor.black
    ]
    
    private var backgroundImages: [String] = []
    
    // 初始化
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
        loadBackgroundImages()
        setupPlayer()
        
        // 监听屏幕保护程序状态变化的通知
        setNotifications()
    }
    
    // 加载背景图片
    private func loadBackgroundImages() {
        guard let resourcePath = Bundle(for: type(of: self)).resourcePath else { return }
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: resourcePath)
            let heicFiles = files.filter { $0.hasSuffix(".heic") }
            self.backgroundImages = heicFiles
        } catch {
            print("Error reading Resources directory: \(error.localizedDescription)")
        }
    }
    
    // 配置播放项
    private func configPlayerItems() -> [AVPlayerItem] {
        let videoURLs = SnoopyClip.randomClipURLs(SnoopyClip.loadClips())
        self.videoURLs = videoURLs
        
        var playerItems: [AVPlayerItem] = []
        
        for videoStr in videoURLs {
            if let url = Bundle(for: type(of: self)).url(forResource: videoStr, withExtension: nil) {
                let item = AVPlayerItem(url: url)
                playerItems.append(item)
            } else {
                print("Error: Video file \(videoStr) not found!")
            }
        }
        
        return playerItems
    }
    
    // 设置播放器
    private func setupPlayer() {
        // 创建SpriteKit视图来播放带Alpha通道的视频
        let skView = SKView(frame: bounds)
        skView.wantsLayer = true
        skView.layer?.backgroundColor = NSColor.black.cgColor
        skView.ignoresSiblingOrder = true
        skView.allowsTransparency = true
        self.skView = skView
        addSubview(skView)
        
        // 创建场景
        let scene = SKScene(size: bounds.size)
        scene.scaleMode = .aspectFill
        self.scene = scene
        skView.presentScene(scene)
        
        // 添加纯色背景
        let randomColorIndex = Int.random(in: 0..<colors.count)
        let solidColorBGNode = SKSpriteNode(color: colors[randomColorIndex], size: scene.size)
        solidColorBGNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        solidColorBGNode.zPosition = 0
        solidColorBGNode.name = "backgroundColor"
        scene.addChild(solidColorBGNode)
        
        // 添加半色调图案背景
        if let bgImagePath = Bundle(for: type(of: self)).path(forResource: "halftone_pattern", ofType: "png"),
           let bgImage = NSImage(contentsOfFile: bgImagePath) {
            let bgtexture = SKTexture(image: bgImage)
            let backgroundBNode = SKSpriteNode(texture: bgtexture)
            backgroundBNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
            backgroundBNode.size = scene.size
            backgroundBNode.zPosition = 1
            backgroundBNode.alpha = 0.1
            backgroundBNode.name = "backgroundBImage"
            backgroundBNode.blendMode = .alpha
            scene.addChild(backgroundBNode)
        }
        
        // 添加随机背景图片
        if !backgroundImages.isEmpty {
            let randomBgIndex = Int.random(in: 0..<backgroundImages.count)
            if let imageURL = Bundle(for: type(of: self)).url(forResource: backgroundImages[randomBgIndex], withExtension: nil),
               let image = NSImage(contentsOf: imageURL) {
                let imageAspect = image.size.height / scene.size.height
                let texture = SKTexture(image: image)
                let backgroundNode = SKSpriteNode(texture: texture)
                backgroundNode.position = CGPoint(x: scene.size.width / 2, 
                                               y: scene.size.height / 2 - scene.size.height * offside)
                backgroundNode.size = CGSize(width: image.size.width / imageAspect * scale, 
                                          height: scene.size.height * scale)
                backgroundNode.zPosition = 2
                backgroundNode.name = "backgroundImage"
                backgroundNode.blendMode = .alpha
                scene.addChild(backgroundNode)
            }
        }
        
        // 创建队列播放器并添加视频节点
        self.queuePlayer = AVQueuePlayer(items: configPlayerItems())
        
        if let player = self.queuePlayer {
            let videoNode = SKVideoNode(avPlayer: player)
            videoNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
            videoNode.size = scene.size
            videoNode.zPosition = 3
            videoNode.name = "videoNode"
            scene.addChild(videoNode)
        }
        
        // 监听视频播放完成通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }
    
    // 视频播放完成处理
    @objc private func playerItemDidReachEnd(_ notification: Notification) {
        guard let finishedItem = notification.object as? AVPlayerItem else { return }
        
        if index < videoURLs.count {
            if let url = Bundle(for: type(of: self)).url(forResource: videoURLs[index], withExtension: nil) {
                let item = AVPlayerItem(url: url)
                queuePlayer?.insert(item, after: nil)
            }
        }
        
        index += 1
        
        // 当所有视频播放一轮后，重置索引并更改背景
        if index % videoURLs.count == 0 {
            index = 0
            
            // 更改背景图片
            if let scene = self.scene, let imageNode = scene.childNode(withName: "backgroundImage") as? SKSpriteNode {
                if !backgroundImages.isEmpty {
                    let randomBgIndex = Int.random(in: 0..<backgroundImages.count)
                    if let imageURL = Bundle(for: type(of: self)).url(forResource: backgroundImages[randomBgIndex], withExtension: nil),
                       let image = NSImage(contentsOf: imageURL) {
                        let imageAspect = image.size.height / scene.size.height
                        imageNode.texture = SKTexture(image: image)
                        imageNode.position = CGPoint(x: scene.size.width / 2, 
                                                   y: scene.size.height / 2 - scene.size.height * offside)
                        imageNode.size = CGSize(width: image.size.width / imageAspect * scale, 
                                              height: scene.size.height * scale)
                    }
                }
                
                // 更改背景颜色
                if let colorNode = scene.childNode(withName: "backgroundColor") as? SKSpriteNode {
                    let randomColorIndex = Int.random(in: 0..<colors.count)
                    colorNode.color = colors[randomColorIndex]
                }
            }
        }
    }
    
    // 开始动画
    override func startAnimation() {
        super.startAnimation()
        queuePlayer?.play()
    }
    
    // 停止动画
    override func stopAnimation() {
        super.stopAnimation()
        queuePlayer?.pause()
    }
    
    // 绘制方法
    override func draw(_ rect: NSRect) {
        super.draw(rect)
    }
    
    // 动画帧方法
    override func animateOneFrame() {
        // 不需要额外的帧动画逻辑
    }
    
    // 配置面板相关方法
    override var hasConfigureSheet: Bool {
        return false
    }
    
    override var configureSheet: NSWindow? {
        return nil
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
        print("屏保将要停止")
        
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
        print("屏保将要开始")
    }
    
    // 系统将要睡眠
    @objc private func onSleepNote(note: Notification) {
        print("系统将要睡眠")
        
        // 在Sonoma上，直接退出进程避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.async {
                exit(0)
            }
        }
    }
    
    // 释放资源
    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        
        queuePlayer?.pause()
        queuePlayer = nil
    }
}