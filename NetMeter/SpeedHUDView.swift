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
        // ↗/↙ 旋转 ±45°，与菜单栏一致呈正上/正下
        let rowFont = Font.system(size: 12, weight: .semibold, design: .rounded)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("↗")
                    .font(rowFont)
                    .rotationEffect(.degrees(-45))
                    .frame(width: 16, height: 16)
                Text(SpeedFormatter.menuBarStyledSpeed(bytesPerSecond: monitor.uploadBps))
                    .font(rowFont)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                Text("↙")
                    .font(rowFont)
                    .rotationEffect(.degrees(45))
                    .frame(width: 16, height: 16)
                Text(SpeedFormatter.menuBarStyledSpeed(bytesPerSecond: monitor.downloadBps))
                    .font(rowFont)
                    .monospacedDigit()
            }
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
