//
//  MenuBarStatusController.swift
//  NetMeter
//
//  使用 NSStatusItem + AppKit 布局，在系统菜单栏厚度内垂直居中，避免 SwiftUI MenuBarExtra 裁切双行文字。

import AppKit
import Observation
import SwiftUI

@MainActor
final class NetMeterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NetTopSpeedMonitor.shared.start()
        MenuBarStatusController.shared.install(monitor: NetTopSpeedMonitor.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetTopSpeedMonitor.shared.stop()
    }
}

@MainActor
final class MenuBarStatusController: NSObject, NSMenuDelegate {
    static let shared = MenuBarStatusController()

    /// 与紧凑版 SpeedHUD 内容区一致（含内边距与两行文字）
    private enum HUDWindowMetrics {
        static let width: CGFloat = 148
        static let height: CGFloat = 72
    }

    /// 菜单栏箭头与速率间距（须为正，避免 NSTextField 与数字重叠）
    private enum MenuBarTrafficLayout {
        static let arrowToSpeedSpacing: CGFloat = 3
    }

    private var statusItem: NSStatusItem?
    private weak var monitor: NetTopSpeedMonitor?
    private weak var labelUp: NSTextField?
    private weak var labelDown: NSTextField?
    private weak var hudMenuItem: NSMenuItem?
    /// 网速悬浮窗（无主窗口时由 AppKit 托管 SwiftUI）
    private var hudWindow: NSWindow?

    private override init() {
        super.init()
    }

    func install(monitor: NetTopSpeedMonitor) {
        guard statusItem == nil else { return }
        self.monitor = monitor

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }

        button.imagePosition = .noImage
        button.title = ""

        // Unicode 箭头 + 速率；不用负间距（NSTextField 自带边距，负值会与数字重叠）
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.alignment = .trailing

        let rowUp = NSStackView()
        rowUp.orientation = .horizontal
        rowUp.spacing = MenuBarTrafficLayout.arrowToSpeedSpacing
        rowUp.alignment = .centerY
        rowUp.distribution = .fill

        let rowDown = NSStackView()
        rowDown.orientation = .horizontal
        rowDown.spacing = MenuBarTrafficLayout.arrowToSpeedSpacing
        rowDown.alignment = .centerY
        rowDown.distribution = .fill

        // ↗/↙ 旋转 ±45°，视觉上为正上/正下
        let arrowUp = makeRotatedArrowView(character: "↗", rotationDegrees: -45)
        let arrowDown = makeRotatedArrowView(character: "↙", rotationDegrees: -45)
        let up = makeSpeedLabel()
        let down = makeSpeedLabel()
        rowUp.addArrangedSubview(arrowUp)
        rowUp.addArrangedSubview(up)
        rowDown.addArrangedSubview(arrowDown)
        rowDown.addArrangedSubview(down)
        labelUp = up
        labelDown = down

        // 顶 1pt 占位，与参考里 Spacer(height: 1) 一致，微调垂直位置
        let topInset = NSView()
        topInset.translatesAutoresizingMaskIntoConstraints = false
        topInset.heightAnchor.constraint(equalToConstant: 1).isActive = true
        root.addArrangedSubview(topInset)
        root.addArrangedSubview(rowUp)
        root.addArrangedSubview(rowDown)
        root.setCustomSpacing(-1.5, after: rowUp)

        root.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(root)

        NSLayoutConstraint.activate([
            root.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            root.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 3),
            root.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
        ])

        item.menu = buildMenu()
        updateLabels()
        bindObservation(monitor)
    }

    /// 斜向箭头旋转为正上/正下（与 SpeedHUDView 一致）
    private func makeRotatedArrowView(character: String, rotationDegrees: Double) -> NSView {
        let root = Text(character)
            .font(.system(size: 10))
            .foregroundStyle(Color(nsColor: .labelColor))
            .rotationEffect(.degrees(rotationDegrees))
            .frame(width: 15, height: 15)
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        host.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return host
    }

    private func makeSpeedLabel() -> NSTextField {
        let f = NSTextField(labelWithString: "—")
        f.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        f.textColor = .labelColor
        f.alignment = .right
        f.maximumNumberOfLines = 1
        f.lineBreakMode = .byTruncatingTail
        f.backgroundColor = .clear
        f.drawsBackground = false
        f.isBordered = false
        f.isEditable = false
        f.isSelectable = false
        return f
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        let hudItem = NSMenuItem(title: Self.hudMenuTitle(showing: false), action: #selector(toggleHudWindow), keyEquivalent: "")
        hudItem.target = self
        hudMenuItem = hudItem
        m.addItem(hudItem)
        m.addItem(.separator())
        let quit = NSMenuItem(title: "退出 NetMeter", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)
        return m
    }

    /// 菜单展开时同步文案（避免仅依赖上次点击后的状态）
    func menuWillOpen(_ menu: NSMenu) {
        refreshHudMenuItemTitle()
    }

    private static func hudMenuTitle(showing: Bool) -> String {
        showing ? "隐藏网速悬浮窗" : "显示网速悬浮窗"
    }

    private func refreshHudMenuItemTitle() {
        let showing = hudWindow?.isVisible == true
        hudMenuItem?.title = Self.hudMenuTitle(showing: showing)
    }

    @objc private func toggleHudWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = hudWindow, w.isVisible {
            w.orderOut(nil)
            refreshHudMenuItemTitle()
            return
        }
        if hudWindow == nil {
            let size = NSSize(width: HUDWindowMetrics.width, height: HUDWindowMetrics.height)
            let root = SpeedHUDView()
                .environment(NetTopSpeedMonitor.shared)
            let hosting = NSHostingController(rootView: root)
            hosting.view.frame = CGRect(origin: .zero, size: size)

            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.level = .floating
            w.collectionBehavior.insert(.canJoinAllSpaces)
            w.isMovableByWindowBackground = true
            w.contentViewController = hosting
            w.setContentSize(size)
            w.center()
            hudWindow = w
        }
        hudWindow?.makeKeyAndOrderFront(nil)
        refreshHudMenuItemTitle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateLabels() {
        guard let monitor else { return }
        labelUp?.stringValue = SpeedFormatter.menuBarStyledSpeed(bytesPerSecond: monitor.uploadBps)
        labelDown?.stringValue = SpeedFormatter.menuBarStyledSpeed(bytesPerSecond: monitor.downloadBps)
    }

    /// 监听 @Observable 的速率变化并刷新标签
    private func bindObservation(_ monitor: NetTopSpeedMonitor) {
        func observe() {
            withObservationTracking {
                _ = monitor.uploadBps
                _ = monitor.downloadBps
            } onChange: {
                Task { @MainActor in
                    self.updateLabels()
                    observe()
                }
            }
        }
        observe()
    }
}
