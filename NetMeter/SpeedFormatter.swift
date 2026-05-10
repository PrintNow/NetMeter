//
//  SpeedFormatter.swift
//  NetMeter
//

import Foundation

/// 将字节/秒格式化为易读字符串
enum SpeedFormatter {
    /// 主窗口用，带单位后缀
    static func detailLine(bytesPerSecond: Double, prefix: String) -> String {
        "\(prefix) \(detail(bytesPerSecond: bytesPerSecond))"
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
