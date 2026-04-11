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

/// 菜单、关于页、状态栏 toolTip 用的展示名（勿用 `AppBundleDisplay` 作类型名，易与编译器生成符号冲突）
enum NetMeterDisplayName {
    static var resolved: String {
        let b = Bundle.main
        if let s = b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !s.isEmpty { return s }
        if let s = b.object(forInfoDictionaryKey: "CFBundleName") as? String, !s.isEmpty { return s }
        return ProcessInfo.processInfo.processName
    }
}
