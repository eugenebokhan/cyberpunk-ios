#if os(iOS)
  import Darwin

  /// The libSystem implementations behind the functions this library exports under the same
  /// names. Calls inside this image would bind to those exports, so the runtime calls through
  /// these pointers instead.
  enum SystemCall {
    typealias Path = UnsafePointer<CChar>?

    static let stat = next(
      "stat", as: (@convention(c) (Path, UnsafeMutablePointer<Darwin.stat>?) -> Int32).self)
    static let access = next("access", as: (@convention(c) (Path, Int32) -> Int32).self)
    static let close = next("close", as: (@convention(c) (Int32) -> Int32).self)
    static let fopen = next(
      "fopen", as: (@convention(c) (Path, Path) -> UnsafeMutablePointer<FILE>?).self)
    static let opendir = next(
      "opendir", as: (@convention(c) (Path) -> UnsafeMutablePointer<DIR>?).self)
    static let realpath = next(
      "realpath$DARWIN_EXTSN",
      as: (@convention(c) (Path, UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>?)
        .self)
    static let sysctl = next(
      "sysctl",
      as: (@convention(c) (
        UnsafeMutablePointer<Int32>?, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?,
        UnsafeMutableRawPointer?, Int
      ) -> Int32).self)
    static let sysctlbyname = next(
      "sysctlbyname",
      as: (@convention(c) (
        Path, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?, UnsafeMutableRawPointer?, Int
      ) -> Int32).self)
    static let pthreadSetSchedulingParameters = next(
      "pthread_setschedparam",
      as: (@convention(c) (pthread_t, Int32, UnsafePointer<sched_param>?) -> Int32).self)
    static let pthreadAttributeSetSchedulingPolicy = next(
      "pthread_attr_setschedpolicy",
      as: (@convention(c) (UnsafeMutablePointer<pthread_attr_t>?, Int32) -> Int32).self)
    static let pthreadSetQualityOfService = symbol(
      "pthread_set_qos_class_self_np", in: "/usr/lib/system/libsystem_pthread.dylib",
      as: (@convention(c) (qos_class_t, Int32) -> Int32).self)
    static let mmap = symbol(
      "mmap", in: kernel,
      as: (@convention(c) (UnsafeMutableRawPointer?, Int, Int32, Int32, Int32, off_t) ->
        UnsafeMutableRawPointer?).self)
    static let mprotect = symbol(
      "mprotect", in: kernel,
      as: (@convention(c) (UnsafeMutableRawPointer?, Int, Int32) -> Int32).self)

    private static let kernel = "/usr/lib/system/libsystem_kernel.dylib"

    private static func next<Function>(_ name: String, as _: Function.Type) -> Function {
      // RTLD_NEXT: the first definition loaded after this image.
      resolved(dlsym(UnsafeMutableRawPointer(bitPattern: -1), name), name)
    }

    private static func symbol<Function>(_ name: String, in library: String, as _: Function.Type)
      -> Function
    {
      resolved(dlsym(dlopen(library, RTLD_NOLOAD | RTLD_LAZY), name), name)
    }

    private static func resolved<Function>(_ address: UnsafeMutableRawPointer?, _ name: String)
      -> Function
    {
      guard let address else { fatalError("libSystem does not provide \(name)") }
      return unsafeBitCast(address, to: Function.self)
    }
  }
#endif
