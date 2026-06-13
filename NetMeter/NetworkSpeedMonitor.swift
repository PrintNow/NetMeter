//
//  NetworkSpeedMonitor.swift
//  NetMeter
//
//  getifaddrs 接口差分采样。采样在 detached 任务中运行，
//  避免 @Observable + MainActor 采样环导致 CPU 异常偏高。
//

import AppKit
import Combine
import Foundation

// MARK: - 展示状态（单次 @Published 刷新，减少 SwiftUI 通知开销）

struct SpeedDisplayState: Equatable, Sendable {
    var downloadBps: Double = 0
    var uploadBps: Double = 0
    var lastError: String?
    var lastUpdate: Date?
}

// MARK: - 采样策略常量

private enum SamplingPolicy {
    static let minInterval: Double = 0.2
    static let maxInterval: Double = 60
    /// 连续无流量超过此次数后进入退避；每经过一个 threshold 周期指数翻倍，直至 maxInterval
    static let idleStreakThreshold = 3
    static let idleBackoffMultiplier: Double = 2
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
    private var _sampleIntervalSeconds: Double = 1.5
    private var loopTask: Task<Void, Never>?
    /// 接口切换时由 InterfaceMonitor 回调置位，采样循环检测后重置快照
    private var needsResetSnapshot = false
    private var sleepObservers: [NSObjectProtocol] = []

    init(userDefaults: UserDefaults = .standard, interfaceMonitor: InterfaceMonitor = .shared) {
        self.preferences = userDefaults
        self.interfaceMonitor = interfaceMonitor
        let savedInterval = userDefaults.double(forKey: Self.intervalDefaultsKey)
        if savedInterval > 0 {
            self._sampleIntervalSeconds = savedInterval
        }
    }

    func start() {
        interfaceMonitor.onSelectedInterfaceChange = { [weak self] in
            self?.lock.lock()
            self?.needsResetSnapshot = true
            self?.lock.unlock()
        }
        interfaceMonitor.start()
        scheduleRestartLoopFromMain()
        setupSleepObservers()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        interfaceMonitor.stop()
        let ws = NSWorkspace.shared.notificationCenter
        sleepObservers.forEach { ws.removeObserver($0) }
        sleepObservers.removeAll()
    }

    private func setupSleepObservers() {
        // 先清理旧的，防止 start() 多次调用时重复注册
        let ws = NSWorkspace.shared.notificationCenter
        sleepObservers.forEach { ws.removeObserver($0) }
        sleepObservers.removeAll()

        let pause: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async {
                self?.loopTask?.cancel()
                self?.loopTask = nil
            }
        }
        let resume: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleRestartLoopFromMain() }
        }
        sleepObservers = [
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil, using: pause),
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil, using: pause),
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil, using: resume),
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil, using: resume),
        ]
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
            let interval = lock.withLock { max(_sampleIntervalSeconds, SamplingPolicy.minInterval) }

            // 接口切换时重置快照，避免跨接口 delta 产生异常值
            let shouldReset = lock.withLock {
                let r = needsResetSnapshot
                needsResetSnapshot = false
                return r
            }
            if shouldReset {
                previousSnapshot = nil
                previousTime = nil
                idleStreak = 0
            }

            // 读取当前选定接口：手动选择优先，否则使用默认路由接口
            let selectedIf = interfaceMonitor.selectedInterface ?? interfaceMonitor.defaultInterface

            do {
                let snap = try Self.takeSnapshot(selectedInterface: selectedIf)
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
            if idleStreak >= SamplingPolicy.idleStreakThreshold {
                let steps = idleStreak / SamplingPolicy.idleStreakThreshold
                sleepSec = min(
                    SamplingPolicy.maxInterval,
                    interval * pow(SamplingPolicy.idleBackoffMultiplier, Double(steps))
                )
            }
            let sleepClamped = max(SamplingPolicy.minInterval, min(sleepSec, SamplingPolicy.maxInterval))
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
