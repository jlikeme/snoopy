//
//  ViewController.swift
//  SnoopyDebug
//
//  Created by miuGrey on 2025/5/4.
//

import Cocoa
import ScreenSaver

class DebugViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let screenSaverView = SnoopyScreenSaverView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            isPreview: false
        )!
        view.addSubview(screenSaverView)
        
        // 手动启动动画
        screenSaverView.startAnimation()
    }
}

