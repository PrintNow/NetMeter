//
//  NetworkSpeedMonitor.swift
//  NetMeter
//
//  getifaddrs 接口差分采样。采样在 detached 任务中运行，
//  避免 @Observable + MainActor 采样环导致 CPU 异常偏高。
//

import Combine
import Foundation

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

    private static let intervalDefaultsKey = "NetMeter.SampleInterval"

    /// 菜单栏 / SwiftUI 共用一份展示状态；仅在主队列写入以触发 objectWillChange
    @Published private(set) var displayState = SpeedDisplayState()

    let interfaceMonitor: InterfaceMonitor

    var downloadBps: Double { displayState.downloadBps }
    var uploadBps: Double { displayState.uploadBps }
    var lastError: String? { displayState.lastError }
    var lastUpdate: Date? { displayState.lastUpdate }

    /// 接口轮询间隔；变更时自动持久化并重启采样环
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

    private let preferences: UserDefaults
    private let lock = NSLock()
    private var _sampleIntervalSeconds: Double = 2
    private var loopTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard, interfaceMonitor: InterfaceMonitor = .shared) {
        self.preferences = userDefaults
        self.interfaceMonitor = interfaceMonitor
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

    /// 在主线程安排重启采样环（start / interval 变更）
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

    private func runSamplingLoop() async {
        await runInterfaceCountersPass()
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
