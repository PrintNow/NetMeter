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
        case .nettop: return "nettop 进程增量汇总"
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

    /// 菜单栏 / SwiftUI 共用一份展示状态；仅在主队列写入以触发 objectWillChange
    @Published private(set) var displayState = SpeedDisplayState()

    var downloadBps: Double { displayState.downloadBps }
    var uploadBps: Double { displayState.uploadBps }
    var lastError: String? { displayState.lastError }
    var lastUpdate: Date? { displayState.lastUpdate }

    /// 与 nettop -s 或接口轮询间隔一致；菜单栏约 2s
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

    init(userDefaults: UserDefaults = .standard) {
        self.preferences = userDefaults
        let raw = userDefaults.string(forKey: Self.defaultsKey)
        self._backend = SpeedSamplingBackend(rawValue: raw ?? "") ?? .interfaceCounters
    }

    func start() {
        scheduleRestartLoopFromMain()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
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

    private func publishDisplayOnMain(_ state: SpeedDisplayState) {
        DispatchQueue.main.async { [weak self] in
            self?.displayState = state
        }
    }

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
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func runInterfaceCountersPass() async {
        var previousSnapshot: [String: (UInt32, UInt32)]?
        var previousTime: Date?
        var idleStreak = 0

        while !Task.isCancelled {
            if Task.isCancelled { break }

            let interval = lock.withLock { max(_sampleIntervalSeconds, 0.2) }

            do {
                let snap = try await snapshotOnUtilityQueue()
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

    private nonisolated static func takeSnapshot() throws -> [String: (UInt32, UInt32)] {
        try InterfaceCounterSampler.snapshotTotals()
    }

    private func snapshotOnUtilityQueue() async throws -> [String: (UInt32, UInt32)] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: (UInt32, UInt32)], Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let s = try Self.takeSnapshot()
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
