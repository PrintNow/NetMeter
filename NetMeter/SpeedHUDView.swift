//
//  SpeedHUDView.swift
//  NetMeter
//

import AppKit
import SwiftUI

/// 将悬浮窗提到浮动层并跨 Space（可选）
struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 从 Monitor 映射为 `MenuBarSpeedLines`，再交给纯展示视图
struct SpeedHUDRoot: View {
    @Environment(NetTopSpeedMonitor.self) private var monitor

    var body: some View {
        SpeedHUDView(
            lines: MenuBarSpeedLines.make(uploadBps: monitor.uploadBps, downloadBps: monitor.downloadBps),
            lastError: monitor.lastError
        )
    }
}

/// 仅负责布局与样式；速率字符串由外部传入
struct SpeedHUDView: View {
    let lines: MenuBarSpeedLines
    let lastError: String?

    var body: some View {
        // ↗/↙ 旋转 ±45°，与菜单栏一致呈正上/正下
        let rowFont = Font.system(size: 12, weight: .semibold, design: .rounded)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("↗")
                    .font(rowFont)
                    .rotationEffect(.degrees(-45))
                    .frame(width: 16, height: 16)
                Text(lines.upload)
                    .font(rowFont)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                Text("↙")
                    .font(rowFont)
                    .rotationEffect(.degrees(-45))
                    .frame(width: 16, height: 16)
                Text(lines.download)
                    .font(rowFont)
                    .monospacedDigit()
            }
            if let err = lastError {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(8)
        .frame(minWidth: 128, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(FloatingWindowConfigurator())
    }
}
