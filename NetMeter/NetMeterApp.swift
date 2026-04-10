//
//  NetMeterApp.swift
//  NetMeter
//

import AppKit
import SwiftUI

@main
struct NetMeterApp: App {
    @NSApplicationDelegateAdaptor(NetMeterAppDelegate.self) private var appDelegate

    var body: some Scene {
        // 满足 SwiftUI App 的 Scene 要求；启动时不自动打开文档窗口
        WindowGroup {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
