//
//  NetTopCSVParseTests.swift
//  NetMeterTests
//

import XCTest
@testable import NetMeter

final class NetTopCSVParseTests: XCTestCase {
    func testParseNettopCSVBlocks_twoBlocks() throws {
        let csv = """
        time,bytes_in,bytes_out,foo
        0,0,0,x

        time,bytes_in,bytes_out,foo
        0,0,0,x
        p1,100,200,y
        p2,50,25,z
        """
        let interval = 2.0
        let r = try NetTopSpeedSampler.parseNettopCSVBlocks(csv, intervalSeconds: interval)
        XCTAssertEqual(r.downloadBps, 75.0)
        XCTAssertEqual(r.uploadBps, 112.5)
    }
}
