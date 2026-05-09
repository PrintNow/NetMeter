//
//  NetworkSpeedMonitor.swift
//  NetMeter
//
//  统一门面：默认 getifaddrs 接口差分，可选 nettop。采样在 detached 任务中运行，
//  避免 @Observable + MainActor 采样环导致 CPU 异常偏高。
//

import Combine
import Foundation

// MARK: - 后端

enum SpeedSamplingBackend: String, CaseIterable, Sendable {
    case interfaceCounters
    case nettop

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

    var statusLineHint: String {
        switch self {
        case .interfaceCounters: return "内核网络接口字节计数差分（低开销）"
        case .nettop:
            // 活动监视器里大量 CPU 常记在子进程 nettop 上，与接口模式对比时请合计 NetMeter+nettop
            return "nettop 子进程增量汇总（对比 CPU 时请与「nettop」进程相加）"
        }
    }
}

// MARK: - 展示状态（单次 @Published 刷新，减少 SwiftUI 通知开销）

struct SpeedDisplayState: Equatable, Sendable {
    var downloadBps: Double = 0
    var uploadBps: Double = 0
    var lastError: String?
    var lastUpdate: Date?
}

// MARK: - 门面

final class NetworkSpeedMonitor: ObservableObject, @unchecked Sendable {
    static let shared = NetworkSpeedMonitor()

    private static let defaultsKey = "NetMeter.SpeedSamplingBackend"
    private static let intervalDefaultsKey = "NetMeter.SampleInterval"

    /// 菜单栏 / SwiftUI 共用一份展示状态；仅在主队列写入以触发 objectWillChange
    @Published private(set) var displayState = SpeedDisplayState()

    let interfaceMonitor: InterfaceMonitor

    var downloadBps: Double { displayState.downloadBps }
    var uploadBps: Double { displayState.uploadBps }
    var lastError: String? { displayState.lastError }
    var lastUpdate: Date? { displayState.lastUpdate }

    /// 与 nettop -s 或接口轮询间隔一致；变更时自动持久化并重启采样环
    var sampleIntervalSeconds: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _sampleIntervalSeconds
        }
        set {
            lock.lock()
            _sampleIntervalSeconds = newValue
            lock.unlock()
            preferences.set(newValue, forKey: Self.intervalDefaultsKey)
            scheduleRestartLoopFromMain()
        }
    }

    var backend: SpeedSamplingBackend {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _backend
        }
        set {
            lock.lock()
            _backend = newValue
            lock.unlock()
            preferences.set(newValue.rawValue, forKey: Self.defaultsKey)
            scheduleRestartLoopFromMain()
        }
    }

    private let preferences: UserDefaults
    private let lock = NSLock()
    private var _backend: SpeedSamplingBackend
    private var _sampleIntervalSeconds: Double = 2
    private var loopTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard, interfaceMonitor: InterfaceMonitor = .shared) {
        self.preferences = userDefaults
        self.interfaceMonitor = interfaceMonitor
        let raw = userDefaults.string(forKey: Self.defaultsKey)
        self._backend = SpeedSamplingBackend(rawValue: raw ?? "") ?? .interfaceCounters
        let savedInterval = userDefaults.double(forKey: Self.intervalDefaultsKey)
        if savedInterval > 0 {
            self._sampleIntervalSeconds = savedInterval
        }
    }

    func start() {
        interfaceMonitor.start()
        scheduleRestartLoopFromMain()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        interfaceMonitor.stop()
    }

    /// 在主线程安排重启采样环（start / backend / interval 变更）
    private func scheduleRestartLoopFromMain() {
        if Thread.isMainThread {
            restartLoopLocked()
        } else {
            DispatchQueue.main.async { [weak self] in self?.restartLoopLocked() }
        }
    }

    private func restartLoopLocked() {
        loopTask?.cancel()
        loopTask = Task.detached(priority: .utility) { [weak self] in
            await self?.runSamplingLoop()
        }
    }

    /// 仅当速率/错误文案变化时更新，避免重复 @Published；首次写入（lastUpdate 仍为 nil）始终发布。
    private func publishDisplayOnMain(_ state: SpeedDisplayState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let cur = self.displayState
            let coreEqual = cur.downloadBps == state.downloadBps
                && cur.uploadBps == state.uploadBps
                && cur.lastError == state.lastError
            if coreEqual, cur.lastUpdate != nil { return }
            self.displayState = state
        }
    }

    // 维护者：对比两种后端 CPU 时请用 Instruments「Time Profiler」各采一段，核对 getifaddrs、主线程与 CSV 解析栈。
    private func runSamplingLoop() async {
        while !Task.isCancelled {
            let (backendNow, interval) = lock.withLock {
                (_backend, max(_sampleIntervalSeconds, 0.2))
            }

            switch backendNow {
            case .interfaceCounters:
                await runInterfaceCountersPass()
            case .nettop:
                await runNettopPass(interval: interval)
            }
        }
    }

    private func runNettopPass(interval: Double) async {
        var idleStreak = 0
        var errorBackoff: Double = 1

        while !Task.isCancelled {
            do {
                let parsed = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Double, Double), Error>) in
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            let v = try NetTopSpeedSampler.runNettopSync(intervalSeconds: interval)
                            cont.resume(returning: (v.downloadBps, v.uploadBps))
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
                let active = parsed.0 > 0 || parsed.1 > 0
                if active {
                    idleStreak = 0
                    errorBackoff = 1
                } else {
                    idleStreak += 1
                }
                publishDisplayOnMain(SpeedDisplayState(
                    downloadBps: parsed.0,
                    uploadBps: parsed.1,
                    lastError: nil,
                    lastUpdate: Date()
                ))
            } catch is CancellationError {
                return
            } catch {
                let keep = await MainActor.run { [weak self] in
                    self?.displayState ?? SpeedDisplayState()
                }
                publishDisplayOnMain(SpeedDisplayState(
                    downloadBps: keep.downloadBps,
                    uploadBps: keep.uploadBps,
                    lastError: error.localizedDescription,
                    lastUpdate: Date()
                ))
                // 指数退避：1s → 2s → 4s，上限 8s
                try? await Task.sleep(nanoseconds: UInt64(errorBackoff * 1_000_000_000))
                errorBackoff = min(8, errorBackoff * 2)
                continue
            }

            // 空闲退避：连续 3 次无流量后 sleep 翻倍，上限 8s
            var sleepSec = interval
            if idleStreak >= 3 {
                sleepSec = min(8, interval * 2)
            }
            let sleepClamped = max(0.2, min(sleepSec, 60))
            do {
                try await Task.sleep(nanoseconds: UInt64(sleepClamped * 1_000_000_000))
            } catch { return }

            let stillNettop = lock.withLock { _backend == .nettop }
            if !stillNettop { return }
        }
    }

    private func runInterfaceCountersPass() async {
        var previousSnapshot: [String: (UInt32, UInt32)]?
        var previousTime: Date?
        var idleStreak = 0

        while !Task.isCancelled {
            if Task.isCancelled { break }

            let interval = lock.withLock { max(_sampleIntervalSeconds, 0.2) }
            // 读取当前选定接口：手动选择优先，否则使用默认路由接口
            let selectedIf = interfaceMonitor.selectedInterface ?? interfaceMonitor.defaultInterface

            do {
                let snap = try await snapshotOnUtilityQueue(selectedInterface: selectedIf)
                let tAfter = Date()

                if let prev = previousSnapshot, let t0 = previousTime {
                    let dt = tAfter.timeIntervalSince(t0)
                    let (dIn, dOut) = InterfaceCounterSampler.deltaBytes(previous: prev, current: snap)
                    let active = dIn > 0 || dOut > 0
                    if active {
                        idleStreak = 0
                    } else {
                        idleStreak += 1
                    }

                    if dt > 0.05 {
                        publishDisplayOnMain(SpeedDisplayState(
                            downloadBps: Double(dIn) / dt,
                            uploadBps: Double(dOut) / dt,
                            lastError: nil,
                            lastUpdate: tAfter
                        ))
                    }
                } else {
                    idleStreak = 0
                    publishDisplayOnMain(SpeedDisplayState(
                        downloadBps: 0,
                        uploadBps: 0,
                        lastError: nil,
                        lastUpdate: tAfter
                    ))
                }

                previousSnapshot = snap
                previousTime = tAfter
            } catch is CancellationError {
                break
            } catch {
                let keep = await MainActor.run { [weak self] in
                    self?.displayState ?? SpeedDisplayState()
                }
                publishDisplayOnMain(SpeedDisplayState(
                    downloadBps: keep.downloadBps,
                    uploadBps: keep.uploadBps,
                    lastError: error.localizedDescription,
                    lastUpdate: Date()
                ))
            }

            var sleepSec = interval
            if idleStreak >= 3 {
                sleepSec = min(8, interval * 2)
            }
            let sleepClamped = max(0.2, min(sleepSec, 60))
            let ns = UInt64(sleepClamped * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: ns)
            } catch {
                break
            }

            let stillCounters = lock.withLock { _backend == .interfaceCounters }
            if !stillCounters { break }
        }
    }

    private nonisolated static func takeSnapshot(selectedInterface: String?) throws -> [String: (UInt32, UInt32)] {
        try InterfaceCounterSampler.snapshotTotals(selectedInterface: selectedInterface)
    }

    private func snapshotOnUtilityQueue(selectedInterface: String?) async throws -> [String: (UInt32, UInt32)] {
        let sel = selectedInterface
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: (UInt32, UInt32)], Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let s = try Self.takeSnapshot(selectedInterface: sel)
                    cont.resume(returning: s)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }

    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
