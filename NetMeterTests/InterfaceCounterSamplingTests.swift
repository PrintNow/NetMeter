//
//  InterfaceCounterSamplingTests.swift
//  NetMeterTests
//

import Darwin
import XCTest

@testable import NetMeter

final class InterfaceCounterSamplingTests: XCTestCase {
    func testDeltaBytes_normalIncrease() {
        let prev: [String: (UInt32, UInt32)] = ["en0": (100, 50)]
        let cur: [String: (UInt32, UInt32)] = ["en0": (160, 80)]
        let d = InterfaceCounterSampler.deltaBytes(previous: prev, current: cur)
        XCTAssertEqual(d.in, 60)
        XCTAssertEqual(d.out, 30)
    }

    func testDeltaBytes_wrap32() {
        let prev: [String: (UInt32, UInt32)] = ["en0": (UInt32.max - 9, 0)]
        let cur: [String: (UInt32, UInt32)] = ["en0": (5, 0)]
        let d = InterfaceCounterSampler.deltaBytes(previous: prev, current: cur)
        XCTAssertEqual(d.in, 15)
        XCTAssertEqual(d.out, 0)
    }

    func testDeltaBytes_newInterfaceSkipped() {
        let prev: [String: (UInt32, UInt32)] = [:]
        let cur: [String: (UInt32, UInt32)] = ["en0": (10, 10)]
        let d = InterfaceCounterSampler.deltaBytes(previous: prev, current: cur)
        XCTAssertEqual(d.in, 0)
        XCTAssertEqual(d.out, 0)
    }

    func testDeltaBytes_multiInterfaces() {
        let prev: [String: (UInt32, UInt32)] = ["en0": (10, 5), "utun3": (1, 1)]
        let cur: [String: (UInt32, UInt32)] = ["en0": (20, 10), "utun3": (4, 2)]
        let d = InterfaceCounterSampler.deltaBytes(previous: prev, current: cur)
        XCTAssertEqual(d.in, 13)
        XCTAssertEqual(d.out, 6)
    }

    func testPolicy_excludesLoopback() {
        let flags = UInt32(IFF_UP | IFF_RUNNING | IFF_LOOPBACK)
        XCTAssertFalse(InterfaceCounterPolicy.shouldInclude(name: "lo0", flags: flags))
    }

    func testPolicy_excludesBridge() {
        let flags = UInt32(IFF_UP | IFF_RUNNING)
        XCTAssertFalse(InterfaceCounterPolicy.shouldInclude(name: "bridge100", flags: flags))
    }

    func testPolicy_includesEnWhenUpRunning() {
        let flags = UInt32(IFF_UP | IFF_RUNNING)
        XCTAssertTrue(InterfaceCounterPolicy.shouldInclude(name: "en0", flags: flags))
    }

    func testPolicy_includesUtun() {
        let flags = UInt32(IFF_UP | IFF_RUNNING)
        XCTAssertTrue(InterfaceCounterPolicy.shouldInclude(name: "utun4", flags: flags))
    }

    func testPolicy_excludesNotRunning() {
        let flags = UInt32(IFF_UP)
        XCTAssertFalse(InterfaceCounterPolicy.shouldInclude(name: "en0", flags: flags))
    }

    func testSnapshotTotals_smoke() throws {
        let snap = try InterfaceCounterSampler.snapshotTotals()
        XCTAssertFalse(snap.isEmpty, "本机应至少有一个符合条件的接口统计")
    }

    func testSnapshotTotals_withSelectedInterface() throws {
        // 先获取所有接口
        let allSnap = try InterfaceCounterSampler.snapshotTotals()
        guard let firstInterface = allSnap.keys.first else {
            throw XCTSkip("本机无可用接口，跳过过滤测试")
        }

        // 只监控第一个接口
        let filtered = try InterfaceCounterSampler.snapshotTotals(selectedInterface: firstInterface)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertNotNil(filtered[firstInterface])
    }

    func testSnapshotTotals_nilSelectedReturnsAll() throws {
        let all = try InterfaceCounterSampler.snapshotTotals(selectedInterface: nil)
        let defaultAll = try InterfaceCounterSampler.snapshotTotals()
        XCTAssertEqual(all.count, defaultAll.count)
    }
}
