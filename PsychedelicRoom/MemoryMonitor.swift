import Foundation
import Darwin

/// 自プロセスの常駐メモリ (resident size) を MB 単位で取得する小ヘルパー。
/// Xcode を繋がない実機長時間検証でメモリ遷移を確認するために使う。
enum MemoryMonitor {
    /// 現在の物理メモリ使用量 (MB) を返す。取得失敗時は nil。
    static func currentResidentMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // phys_footprint は jetsam が実際に評価する値。OS が見るプロセスメモリに最も近い。
        let bytes = Double(info.phys_footprint)
        return bytes / 1024.0 / 1024.0
    }
}
