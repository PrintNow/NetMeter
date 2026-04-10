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
        // 与菜单栏相同短格式，仅保留上下行箭头（无「上行/下行」文案）
        VStack(alignment: .leading, spacing: 4) {
            Text("↑ \(SpeedFormatter.menuBarStyledSpeed(bytesPerSecond: monitor.uploadBps))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("↓ \(SpeedFormatter.menuBarStyledSpeed(bytesPerSecond: monitor.downloadBps))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let err = monitor.lastError {
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
