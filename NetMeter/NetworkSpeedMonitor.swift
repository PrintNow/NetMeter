//
//  NetworkSpeedMonitor.swift
//  NetMeter
//
//  统一门面：默认使用 getifaddrs 接口字节差分（低开销），可选 nettop 后端。
//

import Darwin
import Foundation
import Observation

// MARK: - 后端与错误

enum SpeedSamplingBackend: String, CaseIterable, Sendable {
    case interfaceCounters
    case nettop

    /// 菜单项 tag（与 `allCases` 顺序一致）
    var menuItemTag: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func fromMenuItemTag(_ tag: Int) -> SpeedSamplingBackend? {
        guard tag >= 0, tag < allCases.count else { return nil }
        return allCases[tag]
    }

    var localizedTitle: String {
        switch self {
        case .interfaceCounters: return "接口计数器"
        case .nettop: return "nettop（全进程）"
        }
    }

    /// 关于/界面说明用短描述
    var statusLineHint: String {
        switch self {
        case .interfaceCounters: return "内核网络接口字节计数差分（低开销）"
        case .nettop: return "nettop 进程增量汇总"
        }
    }
}

private enum InterfaceCounterSamplerError: LocalizedError {
    case getifaddrsFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .getifaddrsFailed(let code): return "getifaddrs 失败（错误码 \(code)）"
        }
    }
}

// MARK: - 接口筛选与采样

/// 常见物理网卡与 VPN utun；排除桥接以降低重复计数风险
private enum InterfaceCounterPolicy {
    nonisolated static func shouldInclude(name: String, flags: UInt32) -> Bool {
        guard (flags & UInt32(IFF_UP)) != 0, (flags & UInt32(IFF_RUNNING)) != 0 else { return false }
        guard (flags & UInt32(IFF_LOOPBACK)) == 0 else { return false }
        let n = name.lowercased()
        if n.hasPrefix("bridge") { return false }
        return n.hasPrefix("en") || n.hasPrefix("utun")
    }
}

private enum InterfaceCounterSampler {
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

// MARK: - 门面

@Observable
@MainActor
final class NetworkSpeedMonitor {
    static let shared = NetworkSpeedMonitor()

    private static let defaultsKey = "NetMeter.SpeedSamplingBackend"

    /// 下行（本机接收）
    private(set) var downloadBps: Double = 0
    /// 上行（本机发送）
    private(set) var uploadBps: Double = 0
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?

    /// 与 nettop -s 或接口轮询间隔一致；菜单栏约 2s
    var sampleIntervalSeconds: Double = 2 {
        didSet {
            if loopTask != nil { start() }
        }
    }

    var backend: SpeedSamplingBackend {
        didSet {
            UserDefaults.standard.set(backend.rawValue, forKey: Self.defaultsKey)
            if loopTask != nil { start() }
        }
    }

    private var loopTask: Task<Void, Never>?

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        self.backend = SpeedSamplingBackend(rawValue: raw ?? "") ?? .interfaceCounters
    }

    func start() {
        loopTask?.cancel()
        loopTask = Task { await self.runLoop() }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func runLoop() async {
        switch backend {
        case .interfaceCounters:
            await runInterfaceCountersLoop()
        case .nettop:
            await runNettopLoop()
        }
    }

    private func runNettopLoop() async {
        while !Task.isCancelled {
            let interval = sampleIntervalSeconds
            do {
                let parsed = try await Task.detached(priority: .utility) {
                    try NetTopSpeedSampler.runNettopSync(intervalSeconds: interval)
                }.value
                downloadBps = parsed.downloadBps
                uploadBps = parsed.uploadBps
                lastError = nil
                lastUpdate = Date()
            } catch is CancellationError {
                break
            } catch {
                lastError = error.localizedDescription
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func runInterfaceCountersLoop() async {
        var previousSnapshot: [String: (UInt32, UInt32)]?
        var previousTime: Date?

        while !Task.isCancelled {
            let interval = sampleIntervalSeconds

            do {
                let snap = try await Task.detached(priority: .utility) {
                    try InterfaceCounterSampler.snapshotTotals()
                }.value
                let tAfter = Date()

                if let prev = previousSnapshot, let t0 = previousTime {
                    let dt = tAfter.timeIntervalSince(t0)
                    let (dIn, dOut) = InterfaceCounterSampler.deltaBytes(previous: prev, current: snap)
                    if dt > 0.05 {
                        downloadBps = Double(dIn) / dt
                        uploadBps = Double(dOut) / dt
                    }
                } else {
                    downloadBps = 0
                    uploadBps = 0
                }

                previousSnapshot = snap
                previousTime = tAfter
                lastError = nil
                lastUpdate = tAfter
            } catch is CancellationError {
                break
            } catch {
                lastError = error.localizedDescription
            }

            let ns = UInt64(max(interval, 0.2) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: ns)
            } catch {
                break
            }
        }
    }
}
