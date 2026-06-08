//
//  InterfaceMonitor.swift
//  NetMeter
//
//  使用 NWPathMonitor 监听默认路由接口变化，维护可用接口列表。
//  自动跟随默认路由接口（如 Wi-Fi ↔ 有线切换），同时支持手动选定接口。
//

import Combine
import Darwin
import Foundation
import Network

struct InterfaceInfo: Identifiable, Hashable {
    let id: String          // 接口名，如 "en0"
    let name: String        // 同 id
    let isDefaultRoute: Bool
    let isVPN: Bool
    let typeDescription: String  // 如 "Wi-Fi"、"Ethernet"、"VPN"

    var displayName: String {
        if isDefaultRoute {
            return "\(name)（\(typeDescription)，默认路由）"
        }
        return "\(name)（\(typeDescription)）"
    }
}

final class InterfaceMonitor: ObservableObject {
    static let shared = InterfaceMonitor()

    /// 当前默认路由接口名（由 NWPathMonitor 驱动）
    @Published private(set) var defaultInterface: String?

    /// 所有活跃的 en*/utun* 接口
    @Published private(set) var availableInterfaces: [InterfaceInfo] = []

    /// 用户手动选定的接口；nil = 自动跟随默认路由
    @Published var selectedInterface: String? {
        didSet {
            if selectedInterface != oldValue {
                UserDefaults.standard.set(selectedInterface, forKey: Self.defaultsKey)
                onSelectedInterfaceChange?()
            }
        }
    }

    /// 接口切换回调（供采样器重置 previousSnapshot）
    var onSelectedInterfaceChange: (() -> Void)?

    private static let defaultsKey = "NetMeter.SelectedInterface"

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "cc.nowtime.NetMeter.InterfaceMonitor", qos: .utility)
    private var isMonitoring = false
    /// 防抖：避免网络抖动时连续触发 getifaddrs
    private var refreshWorkItem: DispatchWorkItem?

    private init() {
        self.selectedInterface = UserDefaults.standard.string(forKey: Self.defaultsKey)
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor 回调在 monitorQueue 上，取默认接口后切到主线程更新
            let name = path.availableInterfaces.first?.name
            DispatchQueue.main.async {
                guard let self else { return }
                // 仅在默认接口变化时更新，避免重复触发 @Published
                guard name != self.defaultInterface else { return }
                self.defaultInterface = name
                // 防抖 100ms：网络抖动时路径可能连续变化，稳定后再刷新接口列表
                self.refreshWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.refreshAvailableInterfaces() }
                self.refreshWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
            }
        }
        monitor.start(queue: monitorQueue)
        refreshAvailableInterfaces()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor.cancel()
    }

    /// 刷新可用接口列表（从 getifaddrs 读取当前 UP+RUNNING 的 en*/utun* 接口）
    /// getifaddrs 在后台队列执行，结果回调到主线程更新 @Published 属性
    func refreshAvailableInterfaces() {
        let defaultIf = defaultInterface
        DispatchQueue.global(qos: .utility).async {
            var ifaddr: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&ifaddr) == 0, let head = ifaddr else {
                DispatchQueue.main.async { [weak self] in
                    self?.availableInterfaces = []
                }
                return
            }
            defer { freeifaddrs(head) }

            var seen = Set<String>()
            var result: [InterfaceInfo] = []
            var ptr: UnsafeMutablePointer<ifaddrs>? = head
            while let p = ptr {
                defer { ptr = p.pointee.ifa_next }
                let flags = p.pointee.ifa_flags
                guard (flags & UInt32(IFF_UP)) != 0, (flags & UInt32(IFF_RUNNING)) != 0 else { continue }
                guard (flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
                let name = String(cString: p.pointee.ifa_name)
                guard !seen.contains(name) else { continue }
                let n = name.lowercased()
                guard n.hasPrefix("en") || n.hasPrefix("utun") else { continue }
                seen.insert(name)
                let isDef = (name == defaultIf)
                result.append(InterfaceInfo(
                    id: name,
                    name: name,
                    isDefaultRoute: isDef,
                    isVPN: n.hasPrefix("utun"),
                    typeDescription: Self.friendlyType(for: name)
                ))
            }

            result.sort { a, b in
                if a.isDefaultRoute != b.isDefaultRoute { return a.isDefaultRoute }
                if a.isVPN != b.isVPN { return !a.isVPN }
                return a.name < b.name
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if result.map(\.name) != self.availableInterfaces.map(\.name) {
                    self.availableInterfaces = result
                }
            }
        }
    }

    private nonisolated static func friendlyType(for name: String) -> String {
        let n = name.lowercased()
        if n.hasPrefix("utun") { return "VPN" }
        if n == "en0" { return "Wi-Fi" }
        if n == "en1" { return "Thunderbolt" }
        if n.hasPrefix("en") {
            if let idx = Int(n.dropFirst("en".count)) {
                return idx <= 3 ? "Ethernet" : "Network"
            }
            return "Network"
        }
        return "Network"
    }
}
