//
//  MenuBarSpeedPresentation.swift
//  NetMeter
//
//  菜单栏定宽速率文案；悬浮窗若后续再做可复用此层。

import AppKit
import Foundation

extension MenuBarSpeedLines {
    /// 与菜单栏速率标签一致的等宽数字字体
    static var menuBarMonospaceFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    }

    /// 两行共用占位宽：取较宽一行，且不超过 `999.9 M/s` 的测宽（与历史固定上限一致）
    static func unifiedLabelWidth(upload: String, download: String) -> CGFloat {
        let font = menuBarMonospaceFont
        let cap = capLabelWidth(font: font)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let wUp = ceil((upload as NSString).size(withAttributes: attrs).width)
        let wDown = ceil((download as NSString).size(withAttributes: attrs).width)
        return min(cap, max(wUp, wDown))
    }

    private static func capLabelWidth(font: NSFont) -> CGFloat {
        ceil(("999.9 M/s" as NSString).size(withAttributes: [.font: font]).width)
    }
}

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
    /// 选档：自 G→M→K 取第一个换算值 ≥ 0.5 的单位；极小流量固定 `0.0 K/s` 避免抖动
    private static func line(bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        let k = v / 1024
        if k < 0.1 {
            return String(format: "%5.1f K/s", 0.0)
        }
        let m = k / 1024
        let g = m / 1024
        if g >= 0.5 {
            return String(format: "%5.1f G/s", g)
        }
        if m >= 0.5 {
            return String(format: "%5.1f M/s", m)
        }
        return String(format: "%5.1f K/s", k)
    }
}
