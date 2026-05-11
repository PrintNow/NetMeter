//
//  MenuBarStatusController.swift
//  NetMeter
//
//  使用 NSStatusItem + AppKit 布局，在系统菜单栏厚度内垂直居中，避免 SwiftUI MenuBarExtra 裁切双行文字。

import AppKit
import SwiftUI

@MainActor
final class NetMeterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NetworkSpeedMonitor.shared.start()
        MenuBarStatusController.shared.install(monitor: NetworkSpeedMonitor.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetworkSpeedMonitor.shared.stop()
    }
}

@MainActor
final class MenuBarStatusController: NSObject {
    static let shared = MenuBarStatusController()

    /// 菜单栏箭头与速率间距（须为正，避免 NSTextField 与数字重叠）
    private enum MenuBarTrafficLayout {
        static let arrowToSpeedSpacing: CGFloat = 2
    }

    private var statusItem: NSStatusItem?
    private weak var monitor: NetworkSpeedMonitor?
    private weak var labelUp: NSTextField?
    private weak var labelDown: NSTextField?

    /// 动态占位宽：加宽立即生效，收窄延迟执行，减少菜单栏左右抖动
    private enum DynamicSpeedWidth {
        /// 计划未答复时的默认：流量低于当前占位宽持续该时长后才收窄
        static let shrinkDelay: TimeInterval = 5
        static let widthEpsilon: CGFloat = 0.5
    }

    private var widthConstraintUp: NSLayoutConstraint?
    private var widthConstraintDown: NSLayoutConstraint?
    private var appliedSpeedLabelWidth: CGFloat = 0
    private var shrinkWidthWorkItem: DispatchWorkItem?
    private var aboutWindow: NSWindow?
    /// 定时拉取速率刷新菜单栏，避免 withObservationTracking 高频闭环占满 CPU
    private var menuBarRefreshTimer: Timer?

    private override init() {
        super.init()
    }

    deinit {
        shrinkWidthWorkItem?.cancel()
        menuBarRefreshTimer?.invalidate()
    }

    func install(monitor: NetworkSpeedMonitor) {
        guard statusItem == nil else { return }
        self.monitor = monitor

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }

        button.imagePosition = .noImage
        button.title = ""
        button.toolTip = NetMeterDisplayName.resolved

        // Unicode 箭头 + 速率；不用负间距（NSTextField 自带边距，负值会与数字重叠）
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.alignment = .trailing

        // 上行按顶部对齐：箭头顶边贴齐速率文本顶边
        let rowUp = NSStackView()
        rowUp.orientation = .horizontal
        rowUp.spacing = MenuBarTrafficLayout.arrowToSpeedSpacing
        rowUp.alignment = .top
        rowUp.distribution = .fill

        // 下行按基线对齐：↓ 的箭头尖端恰好位于字体基线上，
        // 速率文本中的数字/字母底部也位于基线上，
        // 因此基线对齐能让两者视觉底部精确贴齐，避免不同字号 descent 空白带来的视觉错位
        let rowDown = NSStackView()
        rowDown.orientation = .horizontal
        rowDown.spacing = MenuBarTrafficLayout.arrowToSpeedSpacing
        rowDown.alignment = .lastBaseline
        rowDown.distribution = .fill

        // 纯 AppKit 箭头，避免 NSHostingView+SwiftUI 在菜单栏持续合成
        let arrowUp = makeArrowLabel(isUpload: true)
        let arrowDown = makeArrowLabel(isUpload: false)
        let up = makeSpeedLabel()
        let down = makeSpeedLabel()
        rowUp.addArrangedSubview(arrowUp)
        rowUp.addArrangedSubview(up)
        rowDown.addArrangedSubview(arrowDown)
        rowDown.addArrangedSubview(down)
        labelUp = up
        labelDown = down

        let lines0 = MenuBarSpeedLines.make(uploadBps: monitor.uploadBps, downloadBps: monitor.downloadBps)
        up.stringValue = lines0.upload
        down.stringValue = lines0.download
        let w0 = MenuBarSpeedLines.unifiedLabelWidth(upload: lines0.upload, download: lines0.download)
        appliedSpeedLabelWidth = w0
        up.translatesAutoresizingMaskIntoConstraints = false
        down.translatesAutoresizingMaskIntoConstraints = false
        let cUp = up.widthAnchor.constraint(equalToConstant: w0)
        let cDown = down.widthAnchor.constraint(equalToConstant: w0)
        widthConstraintUp = cUp
        widthConstraintDown = cDown
        NSLayoutConstraint.activate([cUp, cDown])

        // 顶 1pt 占位，与参考里 Spacer(height: 1) 一致，微调垂直位置
        let topInset = NSView()
        topInset.translatesAutoresizingMaskIntoConstraints = false
        topInset.heightAnchor.constraint(equalToConstant: 1).isActive = true
        root.addArrangedSubview(topInset)
        root.addArrangedSubview(rowUp)
        root.addArrangedSubview(rowDown)
        root.setCustomSpacing(-2, after: rowUp)

        root.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(root)

        NSLayoutConstraint.activate([
            root.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            root.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 3),
            root.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
        ])

        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
        updateLabels()
        startMenuBarRefreshTimer(for: monitor)
    }

    private func makeArrowLabel(isUpload: Bool) -> NSTextField {
        let glyph = isUpload ? "↑" : "↓"
        let font = NSFont.systemFont(ofSize: 10, weight: .bold)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        // 下箭头视觉上略高于速率底线，按 1pt 基线下偏移让箭头尖端更贴齐底部；
        // 字段对外报告的基线位置不变，行内 `.lastBaseline` 对齐基准仍然成立
        if !isUpload {
            attrs[.baselineOffset] = NSNumber(value: -1.0)
        }
        let f = NSTextField(labelWithAttributedString: NSAttributedString(string: glyph, attributes: attrs))
        f.alignment = .center
        f.backgroundColor = .clear
        f.isBordered = false
        f.isEditable = false
        f.isSelectable = false
        f.translatesAutoresizingMaskIntoConstraints = false
        f.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        f.setContentHuggingPriority(.defaultHigh, for: .vertical)
        f.widthAnchor.constraint(equalToConstant: 11).isActive = true
        // 不强制高度，使用自然内容高度，避免与速率文本框高差异在居中/边缘对齐时拉偏
        return f
    }

    private func startMenuBarRefreshTimer(for monitor: NetworkSpeedMonitor) {
        menuBarRefreshTimer?.invalidate()
        let interval = max(0.25, monitor.sampleIntervalSeconds)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateLabels()
            }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        menuBarRefreshTimer = t
    }

    private func makeSpeedLabel() -> NSTextField {
        let f = NSTextField(labelWithString: "—")
        f.font = MenuBarSpeedLines.menuBarMonospaceFont
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

    private enum MenuCopy {
        static let intervalOptions: [Double] = [1, 1.5, 2, 3, 5, 10]
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        let about = NSMenuItem(title: "关于 \(NetMeterDisplayName.resolved)…", action: #selector(showAboutPanel), keyEquivalent: "")
        about.target = self
        m.addItem(about)
        m.addItem(.separator())

        // 刷新间隔
        let intervalParent = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        let intervalSub = NSMenu()
        for sec in MenuCopy.intervalOptions {
            let it = NSMenuItem(title: "\(sec) 秒", action: #selector(selectRefreshInterval(_:)), keyEquivalent: "")
            it.target = self
            it.tag = Int(sec * 1000)  // 用 tag 存储间隔值（×1000 避免浮点精度问题）
            intervalSub.addItem(it)
        }
        intervalParent.submenu = intervalSub
        m.addItem(intervalParent)

        m.addItem(.separator())
        let quit = NSMenuItem(title: "退出 \(NetMeterDisplayName.resolved)", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)
        return m
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        let sec = Double(sender.tag) / 1000.0
        monitor?.sampleIntervalSeconds = sec
        if let m = monitor {
            startMenuBarRefreshTimer(for: m)
        }
    }

    @objc private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        if aboutWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.collectionBehavior = .moveToActiveSpace
            w.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: AboutView())
            host.sizingOptions = [.minSize, .maxSize]
            w.contentViewController = host
            aboutWindow = w
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: w,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.aboutWindow = nil
                }
            }
        }
        aboutWindow?.title = "关于 \(NetMeterDisplayName.resolved)"
        aboutWindow?.center()
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateLabels() {
        guard let monitor else { return }
        let lines = MenuBarSpeedLines.make(uploadBps: monitor.uploadBps, downloadBps: monitor.downloadBps)
        if labelUp?.stringValue != lines.upload {
            labelUp?.stringValue = lines.upload
        }
        if labelDown?.stringValue != lines.download {
            labelDown?.stringValue = lines.download
        }
        reconcileSpeedLabelWidths(upload: lines.upload, download: lines.download)
    }

    /// 目标宽小于已应用宽时防抖收窄；变宽立即跟上
    private func reconcileSpeedLabelWidths(upload: String, download: String) {
        let targetW = MenuBarSpeedLines.unifiedLabelWidth(upload: upload, download: download)
        let eps = DynamicSpeedWidth.widthEpsilon
        if targetW > appliedSpeedLabelWidth + eps {
            cancelScheduledShrink()
            applySpeedLabelWidth(targetW)
        } else if targetW + eps < appliedSpeedLabelWidth {
            scheduleShrinkDebounced()
        } else {
            cancelScheduledShrink()
        }
    }

    private func applySpeedLabelWidth(_ w: CGFloat) {
        widthConstraintUp?.constant = w
        widthConstraintDown?.constant = w
        appliedSpeedLabelWidth = w
    }

    private func cancelScheduledShrink() {
        shrinkWidthWorkItem?.cancel()
        shrinkWidthWorkItem = nil
    }

    private func scheduleShrinkDebounced() {
        cancelScheduledShrink()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.shrinkWidthWorkItem = nil
            guard let u = self.labelUp?.stringValue, let d = self.labelDown?.stringValue else { return }
            let targetW = MenuBarSpeedLines.unifiedLabelWidth(upload: u, download: d)
            let eps = DynamicSpeedWidth.widthEpsilon
            guard targetW + eps < self.appliedSpeedLabelWidth else { return }
            self.applySpeedLabelWidth(targetW)
        }
        shrinkWidthWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DynamicSpeedWidth.shrinkDelay, execute: work)
    }

    /// 打开菜单前同步子菜单勾选状态
    private func syncMenuChecks(in menu: NSMenu) {
        guard let monitor else { return }

        // 同步刷新间隔
        if let idx = menu.items.firstIndex(where: { $0.title == "刷新间隔" }),
           let sub = menu.items[idx].submenu {
            let currentTag = Int(monitor.sampleIntervalSeconds * 1000)
            for it in sub.items {
                it.state = it.tag == currentTag ? .on : .off
            }
        }
    }
}

extension MenuBarStatusController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        syncMenuChecks(in: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        updateLabels()
    }
}
