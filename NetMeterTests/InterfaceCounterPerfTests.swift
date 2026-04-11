//
//  InterfaceCounterPerfTests.swift
//  NetMeterTests
//

import XCTest
@testable import NetMeter

final class InterfaceCounterPerfTests: XCTestCase {
    func testPerformance_snapshotTotals() {
        measure(options: XCTMeasureOptions.default) {
            for _ in 0..<80 {
                _ = try? InterfaceCounterSampler.snapshotTotals()
            }
        }
    }

    func testPerformance_deltaBytes_largeMap() {
        var prev: [String: (UInt32, UInt32)] = [:]
        var cur: [String: (UInt32, UInt32)] = [:]
        for i in 0..<500 {
            let k = "en\(i)"
            prev[k] = (UInt32(i), UInt32(i &+ 1))
            cur[k] = (UInt32(i &+ 10), UInt32(i &+ 11))
        }
        measure {
            for _ in 0..<2000 {
                _ = InterfaceCounterSampler.deltaBytes(previous: prev, current: cur)
            }
        }
    }
}
