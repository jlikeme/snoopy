//
//  ContentView.swift
//  SnoopyPreview
//
//  Created by miuGrey on 2025/5/5.
//

import SwiftUI
import AppKit

struct SnoopyScreenSaverViewWrapper: NSViewRepresentable {
    func makeNSView(context: Context) -> SnoopyScreenSaverView {
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let screensaverView = SnoopyScreenSaverView(frame: frame, isPreview: false)
        screensaverView?.startAnimation()
        return screensaverView ?? SnoopyScreenSaverView()
    }

    func updateNSView(_ nsView: SnoopyScreenSaverView, context: Context) {
        // No updates needed for now
    }
}

struct ContentView: View {
    var body: some View {
        SnoopyScreenSaverViewWrapper()
    }
}

#Preview {
    ContentView()
}
