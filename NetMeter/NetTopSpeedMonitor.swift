//
//  NetTopSpeedMonitor.swift
//  NetMeter
//

import Foundation
import Observation

enum NetTopMonitorError: LocalizedError {
    case timeout
    case processFailed(code: Int32, message: String)
    case emptyOutput
    case parseFailed(String)
    case insufficientBlocks

    var errorDescription: String? {
        switch self {
        case .timeout: return "nettop 执行超时"
        case .processFailed(let code, let message): return "nettop 退出码 \(code): \(message)"
        case .emptyOutput: return "nettop 无输出"
        case .parseFailed(let m): return "解析失败: \(m)"
        case .insufficientBlocks: return "输出中未找到第二段增量数据"
        }
    }
}

/// 后台轮询 nettop，汇总全进程上下行速率（字节/秒）
@Observable
@MainActor
final class NetTopSpeedMonitor {
    /// 菜单栏等全局入口共用同一实例
    static let shared = NetTopSpeedMonitor()

    /// 下行（本机接收）
    private(set) var downloadBps: Double = 0
    /// 上行（本机发送）
    private(set) var uploadBps: Double = 0
    private(set) var lastError: String?
    private(set) var lastUpdate: Date?

    /// 与 nettop -s 一致，用于换算 Bps
    var sampleIntervalSeconds: Double = 1.5

    private var loopTask: Task<Void, Never>?

    func start() {
        loopTask?.cancel()
        loopTask = Task { await self.runLoop() }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let interval = sampleIntervalSeconds
            do {
                let parsed = try await Task.detached(priority: .utility) {
                    try NetTopSpeedMonitor.runNettopSync(intervalSeconds: interval)
                }.value
                downloadBps = parsed.downloadBps
                uploadBps = parsed.uploadBps
                lastError = nil
                lastUpdate = Date()
            } catch is CancellationError {
                break
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// 单次执行 nettop，解析第二段 CSV（delta）
    private nonisolated static func runNettopSync(intervalSeconds: Double) throws -> (downloadBps: Double, uploadBps: Double) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "2", "-d", "-s", formatIntervalArg(intervalSeconds), "-x"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let timeout: TimeInterval = max(8, intervalSeconds * 4 + 4)
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw NetTopMonitorError.timeout
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw NetTopMonitorError.emptyOutput
        }

        if process.terminationStatus != 0 {
            throw NetTopMonitorError.processFailed(code: process.terminationStatus, message: text)
        }

        return try parseCSVBlocks(text, intervalSeconds: intervalSeconds)
    }

    /// 生成 nettop -s 参数（避免多余小数位）
    private nonisolated static func formatIntervalArg(_ v: Double) -> String {
        if v == floor(v) { return String(format: "%.0f", v) }
        return String(v)
    }

    // MARK: - 解析

    private nonisolated static func isHeaderLine(_ line: String) -> Bool {
        line.hasPrefix("time") && line.contains("bytes_in") && line.contains("bytes_out")
    }

    /// 简易 CSV 拆行（支持引号内逗号）
    private nonisolated static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if inQuotes {
                if ch == "\"" {
                    inQuotes = false
                } else {
                    current.append(ch)
                }
            } else {
                switch ch {
                case ",":
                    fields.append(current)
                    current = ""
                case "\"":
                    inQuotes = true
                default:
                    current.append(ch)
                }
            }
        }
        fields.append(current)
        return fields
    }

    private nonisolated static func parseCSVBlocks(_ output: String, intervalSeconds: Double) throws -> (downloadBps: Double, uploadBps: Double) {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }

        var blocks: [[String]] = []
        var current: [String] = []
        var headerForIndices: [String]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isHeaderLine(trimmed) {
                if headerForIndices == nil {
                    headerForIndices = parseCSVLine(trimmed)
                }
                if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }

        guard blocks.count >= 2 else {
            throw NetTopMonitorError.insufficientBlocks
        }
        guard let header = headerForIndices else {
            throw NetTopMonitorError.parseFailed("无表头")
        }

        let idxIn = header.firstIndex(of: "bytes_in") ?? header.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "bytes_in" })
        let idxOut = header.firstIndex(of: "bytes_out") ?? header.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "bytes_out" })
        guard let bi = idxIn, let bo = idxOut else {
            throw NetTopMonitorError.parseFailed("找不到 bytes_in/bytes_out 列")
        }

        let deltaLines = blocks[1]
        var sumIn: UInt64 = 0
        var sumOut: UInt64 = 0

        for row in deltaLines {
            let f = parseCSVLine(row)
            guard f.count > max(bi, bo) else { continue }
            if let v = UInt64(f[bi].trimmingCharacters(in: .whitespaces)) { sumIn &+= v }
            if let v = UInt64(f[bo].trimmingCharacters(in: .whitespaces)) { sumOut &+= v }
        }

        let inv = max(intervalSeconds, 0.001)
        let down = Double(sumIn) / inv
        let up = Double(sumOut) / inv
        return (downloadBps: down, uploadBps: up)
    }
}
