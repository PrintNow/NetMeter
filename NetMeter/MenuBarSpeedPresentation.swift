//
//  MenuBarSpeedPresentation.swift
//  NetMeter
//
//  菜单栏定宽速率文案；悬浮窗若后续再做可复用此层。

import Foundation

/// 菜单栏两行定宽速率文案（由 bps 换算，与 View 解耦）
struct MenuBarSpeedLines: Equatable {
    let upload: String
    let download: String

    static func make(uploadBps: Double, downloadBps: Double) -> MenuBarSpeedLines {
        MenuBarSpeedLines(
            upload: Self.line(bytesPerSecond: uploadBps),
            download: Self.line(bytesPerSecond: downloadBps)
        )
    }

    /// 单行定宽：`%5.1f` + ` K/s`/` M/s`/` G/s`（等宽数字字体下列对齐）
    /// 选档：自 G→M→K 取第一个换算值 ≥ 0.1 的单位（如 812K/s → 0.8M/s）；极小流量固定 `0.0 K/s` 避免抖动
    private static func line(bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        let k = v / 1024
        if k < 0.1 {
            return String(format: "%5.1f K/s", 0.0)
        }
        let m = k / 1024
        let g = m / 1024
        if g >= 0.1 {
            return String(format: "%5.1f G/s", g)
        }
        if m >= 0.1 {
            return String(format: "%5.1f M/s", m)
        }
        return String(format: "%5.1f K/s", k)
    }
}
