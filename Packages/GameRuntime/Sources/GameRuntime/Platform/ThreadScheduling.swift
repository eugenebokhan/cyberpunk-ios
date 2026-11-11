#if os(iOS)
  import Darwin

  @_cdecl("pthread_set_qos_class_self_np")
  public func gameRuntimeSetQualityOfService(_ qos: qos_class_t, _ relativePriority: Int32) -> Int32
  {
    let requested: qos_class_t
    switch qos {
    case QOS_CLASS_UTILITY, QOS_CLASS_DEFAULT, QOS_CLASS_UNSPECIFIED:
      requested = QOS_CLASS_USER_INITIATED
    default:
      requested = qos
    }
    return SystemCall.pthreadSetQualityOfService(requested, relativePriority)
  }

  @_cdecl("pthread_setschedparam")
  public func gameRuntimeSetSchedulingParameters(
    _ thread: pthread_t, _ policy: Int32, _ parameters: UnsafePointer<sched_param>?
  ) -> Int32 {
    SystemCall.pthreadSetSchedulingParameters(thread, timeshare(policy), parameters)
  }

  @_cdecl("pthread_attr_setschedpolicy")
  public func gameRuntimeSetSchedulingPolicy(
    _ attributes: UnsafeMutablePointer<pthread_attr_t>?, _ policy: Int32
  ) -> Int32 {
    SystemCall.pthreadAttributeSetSchedulingPolicy(attributes, timeshare(policy))
  }

  private func timeshare(_ policy: Int32) -> Int32 {
    switch policy {
    case SCHED_FIFO, SCHED_RR: SCHED_OTHER
    default: policy
    }
  }
#endif
