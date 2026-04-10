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
        WindowGroup(id: "main") {
            MainWindowHost()
                .environment(NetTopSpeedMonitor.shared)
        }

        Window("网速悬浮", id: "speedHud") {
            SpeedHUDView()
                .environment(NetTopSpeedMonitor.shared)
        }
        .windowStyle(.plain)
        .defaultSize(width: 240, height: 120)
    }
}

// MARK: - 主窗口（接收来自 NSStatusItem 菜单的通知以 openWindow）

private struct MainWindowHost: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .onReceive(NotificationCenter.default.publisher(for: .netMeterOpenMainWindow)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .onReceive(NotificationCenter.default.publisher(for: .netMeterOpenHudWindow)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "speedHud")
            }
    }
}
