#if os(iOS)
  import Darwin
  import Foundation

  /// The engine sizes its pools from the installed memory. On iOS the process may use only its
  /// current footprint plus what the kernel still allows (the increased-memory entitlement raises
  /// that limit), so the installed memory the game sees is capped at that budget.
  enum MemoryBudget {
    static func bytes(physical: UInt64) -> UInt64 {
      var information = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
      let revision4 = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_swapins)!
          / MemoryLayout<natural_t>.size)
      let result = withUnsafeMutablePointer(to: &information) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      guard result == KERN_SUCCESS, count >= revision4 else {
        RuntimeLog.write(
          "memory budget unavailable (task_info \(result)); reporting installed memory")
        return physical
      }
      let (limit, overflow) = information.limit_bytes_remaining.addingReportingOverflow(
        information.phys_footprint)
      return overflow || limit == 0 ? physical : min(physical, limit)
    }

    static func install() {
      let selector = #selector(getter: ProcessInfo.physicalMemory)
      ObjectiveCRuntime.replace(ProcessInfo.self, selector) { original in
        typealias Getter = @convention(c) (ProcessInfo, Selector) -> UInt64
        let getter = unsafeBitCast(original, to: Getter.self)
        let block: @convention(block) (ProcessInfo) -> UInt64 = {
          bytes(physical: getter($0, selector))
        }
        return block
      }
    }
  }

  /// Mac identity answers: the engine reads these while choosing its hardware configuration.
  private let macIdentity: [String: String] = [
    "machdep.cpu.brand_string": "Apple M4", "hw.model": "Mac16,1", "kern.osproductversion": "15.5",
  ]

  @_cdecl("sysctlbyname")
  public func gameRuntimeSysctlByName(
    _ name: UnsafePointer<CChar>?, _ old: UnsafeMutableRawPointer?,
    _ oldLength: UnsafeMutablePointer<Int>?, _ new: UnsafeMutableRawPointer?, _ newLength: Int
  ) -> Int32 {
    if new == nil, let name, let value = macIdentity[String(cString: name)] {
      let bytes = Array(value.utf8CString)
      if let old, let oldLength {
        guard oldLength.pointee >= bytes.count else {
          oldLength.pointee = bytes.count
          errno = ENOMEM
          return -1
        }
        bytes.withUnsafeBytes { old.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
      }
      oldLength?.pointee = bytes.count
      return 0
    }
    let result = SystemCall.sysctlbyname(name, old, oldLength, new, newLength)
    if result == 0, new == nil, let name, strcmp(name, "hw.memsize") == 0 {
      budgetMemorySize(old, oldLength)
    }
    return result
  }

  @_cdecl("sysctl")
  public func gameRuntimeSysctl(
    _ name: UnsafeMutablePointer<Int32>?, _ count: UInt32, _ old: UnsafeMutableRawPointer?,
    _ oldLength: UnsafeMutablePointer<Int>?, _ new: UnsafeMutableRawPointer?, _ newLength: Int
  ) -> Int32 {
    let result = SystemCall.sysctl(name, count, old, oldLength, new, newLength)
    if result == 0, new == nil, count == 2, let name, name[0] == CTL_HW, name[1] == HW_MEMSIZE {
      budgetMemorySize(old, oldLength)
    }
    return result
  }

  private func budgetMemorySize(
    _ old: UnsafeMutableRawPointer?, _ length: UnsafeMutablePointer<Int>?
  ) {
    guard let old, let length, length.pointee >= MemoryLayout<UInt64>.size else { return }
    let error = errno
    old.storeBytes(
      of: MemoryBudget.bytes(physical: old.loadUnaligned(as: UInt64.self)), as: UInt64.self)
    errno = error
  }
#endif
