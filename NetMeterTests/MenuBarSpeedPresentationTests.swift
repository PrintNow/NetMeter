//
//  MenuBarSpeedPresentationTests.swift
//  NetMeterTests
//

import XCTest
@testable import NetMeter

final class MenuBarSpeedPresentationTests: XCTestCase {

    // MARK: - 边界 / 极小值

    func testLine_zeroSpeed() {
        let lines = MenuBarSpeedLines.make(uploadBps: 0, downloadBps: 0)
        XCTAssertEqual(lines.upload, "  0.0 K/s")
        XCTAssertEqual(lines.download, "  0.0 K/s")
    }

    func testLine_negativeSpeed_clampsToZero() {
        let lines = MenuBarSpeedLines.make(uploadBps: -100, downloadBps: -999)
        XCTAssertEqual(lines.upload, "  0.0 K/s")
        XCTAssertEqual(lines.download, "  0.0 K/s")
    }

    func testLine_verySmallSpeed_showsZeroK() {
        // 50 B/s → k = 0.049 < 0.1 → "0.0 K/s"
        let lines = MenuBarSpeedLines.make(uploadBps: 50, downloadBps: 50)
        XCTAssertEqual(lines.upload, "  0.0 K/s")
    }

    // MARK: - K/s 范围

    func testLine_oneKB() {
        // 1024 B/s → k = 1.0
        let lines = MenuBarSpeedLines.make(uploadBps: 1024, downloadBps: 0)
        XCTAssertEqual(lines.upload, "  1.0 K/s")
    }

    func testLine_100KB() {
        // 102400 B/s → k = 100.0
        let lines = MenuBarSpeedLines.make(uploadBps: 102400, downloadBps: 0)
        XCTAssertEqual(lines.upload, "100.0 K/s")
    }

    func testLine_500KB_staysInK() {
        // 512000 B/s → k = 500.0, m = 0.488 < 0.5 → 仍显示 K/s
        let lines = MenuBarSpeedLines.make(uploadBps: 512000, downloadBps: 0)
        XCTAssertEqual(lines.upload, "500.0 K/s")
    }

    // MARK: - K→M 切换阈值

    func testLine_thresholdKtoM_showsPoint5M() {
        // 524288 B/s → k=512, m=0.5 → "0.5 M/s"
        let lines = MenuBarSpeedLines.make(uploadBps: 524288, downloadBps: 0)
        XCTAssertEqual(lines.upload, "  0.5 M/s")
    }

    func testLine_justBelowKtoM_staysK() {
        // 500*1024 B/s → k=500, m=0.488 < 0.5 → 仍显示 K/s
        let lines = MenuBarSpeedLines.make(uploadBps: 500 * 1024, downloadBps: 0)
        XCTAssertEqual(lines.upload, "500.0 K/s")
    }

    // MARK: - M/s 范围

    func testLine_oneMB() {
        // 1048576 B/s → m = 1.0
        let lines = MenuBarSpeedLines.make(uploadBps: 1048576, downloadBps: 0)
        XCTAssertEqual(lines.upload, "  1.0 M/s")
    }

    func testLine_10MB() {
        let lines = MenuBarSpeedLines.make(uploadBps: 10485760, downloadBps: 0)
        XCTAssertEqual(lines.upload, " 10.0 M/s")
    }

    func testLine_100MB() {
        let lines = MenuBarSpeedLines.make(uploadBps: 104857600, downloadBps: 0)
        XCTAssertEqual(lines.upload, "100.0 M/s")
    }

    func testLine_500MB_staysInM() {
        // 524288000 B/s → m=500, g=0.488 < 0.5 → 仍显示 M/s
        let lines = MenuBarSpeedLines.make(uploadBps: 524288000, downloadBps: 0)
        XCTAssertEqual(lines.upload, "500.0 M/s")
    }

    // MARK: - M→G 切换阈值

    func testLine_thresholdMtoG_showsPoint5G() {
        // 536870912 B/s → g = 0.5 → "0.5 G/s"
        let lines = MenuBarSpeedLines.make(uploadBps: 536870912, downloadBps: 0)
        XCTAssertEqual(lines.upload, "  0.5 G/s")
    }

    func testLine_justBelowMtoG_staysM() {
        // 500*1024*1024 B/s → m=500, g=0.488 < 0.5 → 仍显示 M/s
        let lines = MenuBarSpeedLines.make(uploadBps: 500 * 1024 * 1024, downloadBps: 0)
        XCTAssertEqual(lines.upload, "500.0 M/s")
    }

    // MARK: - G/s 范围

    func testLine_oneGB() {
        let lines = MenuBarSpeedLines.make(uploadBps: 1073741824, downloadBps: 0)
        XCTAssertEqual(lines.upload, "  1.0 G/s")
    }

    func testLine_10GB() {
        let lines = MenuBarSpeedLines.make(uploadBps: 10737418240, downloadBps: 0)
        XCTAssertEqual(lines.upload, " 10.0 G/s")
    }

    // MARK: - 双行独立

    func testLine_uploadAndDownloadIndependent() {
        let lines = MenuBarSpeedLines.make(uploadBps: 51200, downloadBps: 1048576)
        XCTAssertEqual(lines.upload, " 50.0 K/s")
        XCTAssertEqual(lines.download, "  1.0 M/s")
    }
}
