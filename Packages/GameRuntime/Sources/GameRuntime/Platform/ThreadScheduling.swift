#if os(iOS)
  import Darwin

  // Mac thread priorities do not mean the same on an iPhone: utility and default QoS park engine
  // threads on the efficiency cores, and fixed-priority (round-robin, FIFO) engine threads starve
  // the threads that deliver input. Engine threads keep their priority as timeshare threads.

  @_cdecl("pthread_set_qos_class_self_np")
  public func gameRuntimeSetQualityOfService(_ qos: qos_class_t, _ relativePriority: Int32) -> Int32
  {
    let raised = [QOS_CLASS_UTILITY, QOS_CLASS_DEFAULT, QOS_CLASS_UNSPECIFIED].contains(qos)
    return SystemCall.pthreadSetQualityOfService(
      raised ? QOS_CLASS_USER_INITIATED : qos, relativePriority)
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
    policy == SCHED_RR || policy == SCHED_FIFO ? SCHED_OTHER : policy
  }
#endif
