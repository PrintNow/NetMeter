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
final class MenuBarStatusController: NSObject {
    static let shared = MenuBarStatusController()

    /// 菜单栏箭头与速率间距（须为正，避免 NSTextField 与数字重叠）
    private enum MenuBarTrafficLayout {
        static let arrowToSpeedSpacing: CGFloat = 3
    }

    private var statusItem: NSStatusItem?
    private weak var monitor: NetTopSpeedMonitor?
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

    private override init() {
        super.init()
    }

    deinit {
        shrinkWidthWorkItem?.cancel()
    }

    func install(monitor: NetTopSpeedMonitor) {
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

    /// 斜向箭头旋转为正上/正下；略加大字号并加粗，避免在菜单栏上偏淡
    private func makeRotatedArrowView(character: String, rotationDegrees: Double) -> NSView {
        let root = Text(character)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(nsColor: .labelColor))
            .rotationEffect(.degrees(rotationDegrees))
            .frame(width: 14, height: 14)
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        host.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return host
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

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        let about = NSMenuItem(title: "关于 \(NetMeterDisplayName.resolved)…", action: #selector(showAboutPanel), keyEquivalent: "")
        about.target = self
        m.addItem(about)
        m.addItem(.separator())
        let quit = NSMenuItem(title: "退出 \(NetMeterDisplayName.resolved)", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)
        return m
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
            w.center()
            w.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: AboutView())
            host.sizingOptions = [.minSize, .maxSize]
            w.contentViewController = host
            aboutWindow = w
        }
        // 每次打开同步标题（避免复用窗口时仍为旧文案）
        aboutWindow?.title = "关于 \(NetMeterDisplayName.resolved)"
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateLabels() {
        guard let monitor else { return }
        let lines = MenuBarSpeedLines.make(uploadBps: monitor.uploadBps, downloadBps: monitor.downloadBps)
        labelUp?.stringValue = lines.upload
        labelDown?.stringValue = lines.download
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
