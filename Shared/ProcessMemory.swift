import Foundation

/// Self-measurement of the calling process's memory use. Shared by the app and the
/// helper daemon so diagnostics can show both footprints side by side — a leak in
/// either process is invisible in system-wide `host_statistics64` numbers.
enum ProcessMemory {

    /// Physical footprint of the current process in bytes — the figure Activity Monitor
    /// reports in its "Memory" column. Returns nil if the kernel call fails.
    static func footprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}
