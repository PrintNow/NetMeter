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

        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 3
        root.alignment = .centerY
        // 水平方向填满状态按钮，多余宽度交给低 hugging 的子视图（文本列），整体靠右排布
        root.distribution = .fill

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .labelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        // 是否使用资源中的瘦高 SVG（与下方宽高比约束一致）
        let usesTrafficSVG: Bool
        if let img = NSImage(named: "MenuBarTrafficArrows") {
            iconView.image = img
            usesTrafficSVG = true
        } else if let img = NSImage(systemSymbolName: "arrow.up.and.down", accessibilityDescription: nil) {
            // 兜底用偏细字重，接近矢量版的细线观感
            let sym = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            iconView.image = img.withSymbolConfiguration(sym)
            usesTrafficSVG = false
        } else {
            usesTrafficSVG = false
        }
        iconView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let col = NSStackView()
        col.orientation = .vertical
        col.spacing = 0
        // 两行右缘对齐；配合低 hugging 让本列吃掉图标右侧剩余宽度，数字贴近菜单栏右侧
        col.alignment = .trailing
        col.setContentHuggingPriority(.defaultLow, for: .horizontal)

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

        var rootConstraints: [NSLayoutConstraint] = [
            root.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            root.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 3),
            root.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
        ]
        // SVG viewBox 12×18（约 2:3，对齐参考双箭头比例）；高度略低于文字列，避免图标显得笨重
        if usesTrafficSVG {
            let svgAspect: CGFloat = 12 / 18
            rootConstraints.append(contentsOf: [
                iconView.heightAnchor.constraint(equalTo: col.heightAnchor, multiplier: 0.82),
                iconView.widthAnchor.constraint(equalTo: iconView.heightAnchor, multiplier: svgAspect),
            ])
        } else if iconView.image != nil {
            rootConstraints.append(contentsOf: [
                iconView.widthAnchor.constraint(equalToConstant: 12),
                iconView.heightAnchor.constraint(lessThanOrEqualTo: col.heightAnchor),
            ])
        }
        NSLayoutConstraint.activate(rootConstraints)

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
