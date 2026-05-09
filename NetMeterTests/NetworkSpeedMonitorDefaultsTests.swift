//
//  NetworkSpeedMonitorDefaultsTests.swift
//  NetMeterTests
//

import XCTest
@testable import NetMeter

final class NetworkSpeedMonitorDefaultsTests: XCTestCase {
    func testInit_readsBackendFromSuite() {
        let suiteName = "test.NetMeter.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离 UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(SpeedSamplingBackend.nettop.rawValue, forKey: "NetMeter.SpeedSamplingBackend")

        let m = NetworkSpeedMonitor(userDefaults: defaults, interfaceMonitor: .shared)
        XCTAssertEqual(m.backend, .nettop)
    }

    func testInit_invalidFallsBackToInterfaceCounters() {
        let suiteName = "test.NetMeter.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离 UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("bogus", forKey: "NetMeter.SpeedSamplingBackend")

        let m = NetworkSpeedMonitor(userDefaults: defaults, interfaceMonitor: .shared)
        XCTAssertEqual(m.backend, .interfaceCounters)
    }

    func testInit_readsIntervalFromSuite() {
        let suiteName = "test.NetMeter.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离 UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(5.0, forKey: "NetMeter.SampleInterval")

        let m = NetworkSpeedMonitor(userDefaults: defaults, interfaceMonitor: .shared)
        XCTAssertEqual(m.sampleIntervalSeconds, 5.0)
    }

    func testInit_defaultIntervalIs2() {
        let suiteName = "test.NetMeter.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("无法创建隔离 UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let m = NetworkSpeedMonitor(userDefaults: defaults, interfaceMonitor: .shared)
        XCTAssertEqual(m.sampleIntervalSeconds, 2.0)
    }
}
