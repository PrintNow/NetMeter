//
//  MenuBarStatusController.swift
//  NetMeter
//
//  使用 NSStatusItem + AppKit 布局，在系统菜单栏厚度内垂直居中，避免 SwiftUI MenuBarExtra 裁切双行文字。

import AppKit
import Observation

extension Notification.Name {
    static let netMeterOpenMainWindow = Notification.Name("netMeterOpenMainWindow")
    static let netMeterOpenHudWindow = Notification.Name("netMeterOpenHudWindow")
}

@MainActor
final class NetMeterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NetTopSpeedMonitor.shared.start()
        MenuBarStatusController.shared.install(monitor: NetTopSpeedMonitor.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetTopSpeedMonitor.shared.stop()
    }
}

@MainActor
final class MenuBarStatusController: NSObject {
    static let shared = MenuBarStatusController()

    private var statusItem: NSStatusItem?
    private weak var monitor: NetTopSpeedMonitor?
    private weak var labelUp: NSTextField?
    private weak var labelDown: NSTextField?

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

        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 3
        root.alignment = .centerY

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: nil) {
            let sym = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(sym)
            iconView.contentTintColor = .secondaryLabelColor
            iconView.imageScaling = .scaleProportionallyDown
        }

        let col = NSStackView()
        col.orientation = .vertical
        col.spacing = 0
        col.alignment = .trailing

        let up = makeSpeedLabel()
        let down = makeSpeedLabel()
        col.addArrangedSubview(up)
        col.addArrangedSubview(down)
        labelUp = up
        labelDown = down

        root.addArrangedSubview(iconView)
        root.addArrangedSubview(col)

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

    private func makeSpeedLabel() -> NSTextField {
        let f = NSTextField(labelWithString: "—")
        f.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
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
        let mainItem = NSMenuItem(title: "打开主窗口…", action: #selector(openMainWindow), keyEquivalent: "")
        mainItem.target = self
        m.addItem(mainItem)
        let hudItem = NSMenuItem(title: "网速悬浮窗", action: #selector(openHudWindow), keyEquivalent: "")
        hudItem.target = self
        m.addItem(hudItem)
        m.addItem(.separator())
        let quit = NSMenuItem(title: "退出 NetMeter", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)
        return m
    }

    @objc private func openMainWindow() {
        NotificationCenter.default.post(name: .netMeterOpenMainWindow, object: nil)
    }

    @objc private func openHudWindow() {
        NotificationCenter.default.post(name: .netMeterOpenHudWindow, object: nil)
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
