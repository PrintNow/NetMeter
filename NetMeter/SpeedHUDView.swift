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

struct SpeedHUDView: View {
    @Environment(NetTopSpeedMonitor.self) private var monitor

    var body: some View {
        // 同一区域：上半上传、下半下载（与菜单栏一致）
        VStack(alignment: .leading, spacing: 6) {
            Text(SpeedFormatter.detailLine(bytesPerSecond: monitor.uploadBps, prefix: "↑ 上行"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(SpeedFormatter.detailLine(bytesPerSecond: monitor.downloadBps, prefix: "↓ 下行"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let err = monitor.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(minWidth: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(FloatingWindowConfigurator())
    }
}
