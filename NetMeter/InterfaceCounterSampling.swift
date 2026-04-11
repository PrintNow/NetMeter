//
//  InterfaceCounterSampling.swift
//  NetMeter
//
//  getifaddrs 接口字节采样（internal 供 @testable 单测）。
//

import Darwin
import Foundation

enum InterfaceCounterSamplerError: LocalizedError {
    case getifaddrsFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .getifaddrsFailed(let code): return "getifaddrs 失败（错误码 \(code)）"
        }
    }
}

/// 常见物理网卡与 VPN utun；排除桥接以降低重复计数风险
enum InterfaceCounterPolicy {
    nonisolated static func shouldInclude(name: String, flags: UInt32) -> Bool {
        guard (flags & UInt32(IFF_UP)) != 0, (flags & UInt32(IFF_RUNNING)) != 0 else { return false }
        guard (flags & UInt32(IFF_LOOPBACK)) == 0 else { return false }
        let n = name.lowercased()
        if n.hasPrefix("bridge") { return false }
        return n.hasPrefix("en") || n.hasPrefix("utun")
    }
}

enum InterfaceCounterSampler {
    /// 各接口名 -> (ifi_ibytes, ifi_obytes)，内核为 32 位累计值
    nonisolated static func snapshotTotals() throws -> [String: (UInt32, UInt32)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let head = ifaddr else {
            throw InterfaceCounterSamplerError.getifaddrsFailed(code: errno)
        }
        defer { freeifaddrs(head) }

        var result: [String: (UInt32, UInt32)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = head
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }

            let flags = UInt32(p.pointee.ifa_flags)
            let name = String(cString: p.pointee.ifa_name)
            guard let addr = p.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard InterfaceCounterPolicy.shouldInclude(name: name, flags: flags) else { continue }
            guard let rawData = p.pointee.ifa_data else { continue }

            let ifData = rawData.assumingMemoryBound(to: if_data.self)
            let ib = ifData.pointee.ifi_ibytes
            let ob = ifData.pointee.ifi_obytes

            if result[name] == nil {
                result[name] = (ib, ob)
            }
        }

        return result
    }

    nonisolated static func deltaBytes(previous: [String: (UInt32, UInt32)], current: [String: (UInt32, UInt32)]) -> (in: UInt64, out: UInt64) {
        var sumIn: UInt64 = 0
        var sumOut: UInt64 = 0
        for (name, cur) in current {
            guard let prev = previous[name] else { continue }
            sumIn &+= unsignedDelta32(previous: prev.0, current: cur.0)
            sumOut &+= unsignedDelta32(previous: prev.1, current: cur.1)
        }
        return (sumIn, sumOut)
    }

    /// 32 位计数器回绕安全的增量
    private nonisolated static func unsignedDelta32(previous: UInt32, current: UInt32) -> UInt64 {
        if current >= previous {
            return UInt64(current &- previous)
        }
        return UInt64(current) + UInt64(UInt32.max) - UInt64(previous) + 1
    }
}
