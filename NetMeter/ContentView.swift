//
//  ContentView.swift
//  NetMeter
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: NetworkSpeedMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NetMeter")
                .font(.title2.weight(.bold))

            // 同一区域上下两行：上=上传，下=下载
            VStack(alignment: .leading, spacing: 8) {
                Text(SpeedFormatter.detailLine(bytesPerSecond: monitor.uploadBps, prefix: "上行"))
                Text(SpeedFormatter.detailLine(bytesPerSecond: monitor.downloadBps, prefix: "下行"))
            }
            .font(.title3.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))

            if let t = monitor.lastUpdate {
                Text("更新于 \(t.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let err = monitor.lastError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text("内核网络接口字节计数差分（低开销）。约每 \(String(format: "%.1f", monitor.sampleIntervalSeconds)) 秒刷新。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 220, alignment: .topLeading)
    }
}

#Preview {
    ContentView(monitor: NetworkSpeedMonitor())
}
