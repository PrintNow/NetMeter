//
//  SpeedFormatter.swift
//  NetMeter
//

import Foundation

/// 将字节/秒格式化为易读字符串
enum SpeedFormatter {
    /// 菜单栏单行速率，参照常见网速样式：`27.0 K/s`、`5.8 M/s`（数字与单位间有空格）
    static func menuBarStyledSpeed(bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        // 有流量但不足 1K/s 时用统一文案，避免 B/s 位数跳动；零流量仍显示 0
        if v < 1024 {
            return v > 0 ? "<1K/s" : "0 B/s"
        }
        let k = v / 1024
        if k < 1024 {
            return String(format: "%.1f K/s", k)
        }
        let m = k / 1024
        if m < 1024 {
            return String(format: "%.1f M/s", m)
        }
        let g = m / 1024
        return String(format: "%.1f G/s", g)
    }

    /// 主窗口用，带单位后缀
    static func detailLine(bytesPerSecond: Double, prefix: String) -> String {
        "\(prefix) \(detail(bytesPerSecond: bytesPerSecond))"
    }

    private static func compact(bytesPerSecond: Double) -> String {
        format(bytesPerSecond: bytesPerSecond, decimals: 1, suffix: "")
    }

    private static func detail(bytesPerSecond: Double) -> String {
        format(bytesPerSecond: bytesPerSecond, decimals: 2, suffix: "/s")
    }

    private static func format(bytesPerSecond: Double, decimals: Int, suffix: String) -> String {
        let v = max(0, bytesPerSecond)
        let units = ["B", "K", "M", "G", "T"]
        var n = v
        var i = 0
        while n >= 1024 && i < units.count - 1 {
            n /= 1024
            i += 1
        }
        if i == 0 {
            return "\(Int(v)) B\(suffix)"
        }
        let num = String(format: "%.\(decimals)f", n)
        return num + " " + units[i] + suffix
    }
}
