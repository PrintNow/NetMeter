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

        let m = NetworkSpeedMonitor(userDefaults: defaults)
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

        let m = NetworkSpeedMonitor(userDefaults: defaults)
        XCTAssertEqual(m.backend, .interfaceCounters)
    }
}
