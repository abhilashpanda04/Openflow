import XCTest
@testable import OpenflowMac

final class ProcessCapacityMonitorTests: XCTestCase {
    func testCurrentReportReturnsValidMetrics() {
        let report = ProcessCapacityMonitor.currentReport(modelFootprintMB: 140)

        // Memory resident size should be positive
        XCTAssertGreaterThan(report.memoryResidentMB, 0.0)
        XCTAssertTrue(report.formattedRAM.contains("MB RAM"))

        // CPU percentage should be in valid range
        XCTAssertGreaterThanOrEqual(report.cpuPercent, 0.0)
        XCTAssertLessThanOrEqual(report.cpuPercent, 100.0)
        XCTAssertTrue(report.formattedCPU.contains("% CPU"))

        // Thread count should be at least 1
        XCTAssertGreaterThanOrEqual(report.threadCount, 1)

        // Model footprint
        XCTAssertEqual(report.activeModelFootprintMB, 140)
        XCTAssertEqual(report.formattedModelFootprint, "+140 MB Weights")

        // Total capacity
        XCTAssertGreaterThan(report.totalAppCapacityMB, report.memoryResidentMB)
        XCTAssertTrue(report.formattedTotalCapacity.contains("MB Total Capacity"))
    }

    func testReportWithZeroModelFootprint() {
        let report = ProcessCapacityMonitor.currentReport(modelFootprintMB: 0)
        XCTAssertEqual(report.activeModelFootprintMB, 0)
        XCTAssertEqual(report.totalAppCapacityMB, report.memoryResidentMB)
    }
}
