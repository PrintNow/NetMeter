//
//  SpeedSamplingBackendTests.swift
//  NetMeterTests
//

import XCTest
@testable import NetMeter

final class SpeedSamplingBackendTests: XCTestCase {
    func testMenuItemTag_roundTrip() {
        for b in SpeedSamplingBackend.allCases {
            XCTAssertEqual(SpeedSamplingBackend.fromMenuItemTag(b.menuItemTag), b)
        }
    }

    func testMenuItemTag_matchesAllCasesOrder() {
        for (idx, b) in SpeedSamplingBackend.allCases.enumerated() {
            XCTAssertEqual(b.menuItemTag, idx)
        }
    }
}
