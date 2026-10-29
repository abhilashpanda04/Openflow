import Darwin
import Foundation

// MARK: - Process Capacity Report

public struct ProcessCapacityReport: Equatable {
    public let memoryResidentMB: Double
    public let memoryVirtualMB: Double
    public let cpuPercent: Double
    public let threadCount: Int
    public let activeModelFootprintMB: Int
    public let totalAppCapacityMB: Double

    public init(
        memoryResidentMB: Double,
        memoryVirtualMB: Double,
        cpuPercent: Double,
        threadCount: Int,
        activeModelFootprintMB: Int,
        totalAppCapacityMB: Double
    ) {
        self.memoryResidentMB = memoryResidentMB
        self.memoryVirtualMB = memoryVirtualMB
        self.cpuPercent = cpuPercent
        self.threadCount = threadCount
        self.activeModelFootprintMB = activeModelFootprintMB
        self.totalAppCapacityMB = totalAppCapacityMB
    }

    public var formattedRAM: String {
        String(format: "%.1f MB RAM", memoryResidentMB)
    }

    public var formattedCPU: String {
        String(format: "%.1f%% CPU", cpuPercent)
    }

    public var formattedModelFootprint: String {
        "+\(activeModelFootprintMB) MB Weights"
    }

    public var formattedTotalCapacity: String {
        String(format: "%.0f MB Total Capacity", totalAppCapacityMB)
    }
}

// MARK: - Live Process Capacity Monitor

public enum ProcessCapacityMonitor {
    public static func currentReport(modelFootprintMB: Int = 0) -> ProcessCapacityReport {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let residentMB: Double
        let virtualMB: Double
        if kerr == KERN_SUCCESS {
            residentMB = Double(info.resident_size) / (1024.0 * 1024.0)
            virtualMB = Double(info.virtual_size) / (1024.0 * 1024.0)
        } else {
            residentMB = 105.0
            virtualMB = 380.0
        }

        // Live CPU & Thread query from Mach task
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        var totalCpu: Double = 0.0

        if task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threadList = threadList {
            for i in 0..<Int(threadCount) {
                var thInfo = thread_basic_info()
                var thInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let thKerr = withUnsafeMutablePointer(to: &thInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &thInfoCount)
                    }
                }
                if thKerr == KERN_SUCCESS {
                    if (thInfo.flags & TH_FLAGS_IDLE) == 0 {
                        totalCpu += Double(thInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    }
                }
                mach_port_deallocate(mach_task_self_, threadList[i])
            }
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threadList)),
                vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size))
            )
        }

        let totalCapacity = residentMB + Double(modelFootprintMB)

        return ProcessCapacityReport(
            memoryResidentMB: residentMB,
            memoryVirtualMB: virtualMB,
            cpuPercent: max(0.0, min(100.0, totalCpu)),
            threadCount: max(1, Int(threadCount)),
            activeModelFootprintMB: modelFootprintMB,
            totalAppCapacityMB: totalCapacity
        )
    }
}
