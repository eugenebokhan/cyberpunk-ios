// The parts of the game-facing ABI that Swift cannot express: exported data symbols, C variadic
// entry points, the caller's return address, a two-register return and a stack switch.
#include "GameRuntimeABI.h"

#include <TargetConditionals.h>

#if TARGET_OS_IOS
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>

#define GAME_RUNTIME_EXPORT __attribute__((visibility("default"), used))

GAME_RUNTIME_EXPORT void *NSApp = NULL;
GAME_RUNTIME_EXPORT const CFStringRef NSApplicationDidBecomeActiveNotification =
    CFSTR("NSApplicationDidBecomeActiveNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSApplicationDidChangeScreenParametersNotification =
    CFSTR("NSApplicationDidChangeScreenParametersNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSApplicationDidResignActiveNotification =
    CFSTR("NSApplicationDidResignActiveNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSApplicationWillResignActiveNotification =
    CFSTR("NSApplicationWillResignActiveNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSWindowDidBecomeKeyNotification =
    CFSTR("NSWindowDidBecomeKeyNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSWindowDidResignKeyNotification =
    CFSTR("NSWindowDidResignKeyNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSWindowDidResizeNotification =
    CFSTR("NSWindowDidResizeNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSWindowWillCloseNotification =
    CFSTR("NSWindowWillCloseNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSWindowWillExitFullScreenNotification =
    CFSTR("NSWindowWillExitFullScreenNotification");
GAME_RUNTIME_EXPORT const CFStringRef NSImageHintInterpolation = CFSTR("NSImageHintInterpolation");
// AppKit's event-tracking mode is UIKit's tracking mode on iOS.
GAME_RUNTIME_EXPORT const CFStringRef NSEventTrackingRunLoopMode = CFSTR("UITrackingRunLoopMode");
GAME_RUNTIME_EXPORT const CFStringRef kCGDisplayShowDuplicateLowResolutionModes =
    CFSTR("kCGDisplayShowDuplicateLowResolutionModes");
GAME_RUNTIME_EXPORT const unsigned int kIOMainPortDefault = 0;

// Implemented in Swift.
extern void GameRuntimeLoad(void);
extern int GameRuntimeOpenFile(const char *path, int flags, int mode);
extern GameRuntimeMapping GameRuntimeMapMemory(
    void *address, size_t length, int protection, int flags, int descriptor, off_t offset,
    const void *returnAddress);
extern void *GameRuntimeCurlFunction(const char *name);

typedef int (*SystemOpen)(const char *, int, ...);
static SystemOpen system_open;

// Code linked into this image binds `open` to the export below, possibly before the constructor.
int GameRuntimeSystemOpen(const char *path, int flags, int mode) {
  SystemOpen function = __atomic_load_n(&system_open, __ATOMIC_ACQUIRE);
  if (!function) {
    function = (SystemOpen)dlsym(RTLD_NEXT, "open");
    __atomic_store_n(&system_open, function, __ATOMIC_RELEASE);
  }
  return function(path, flags, mode);
}

GAME_RUNTIME_EXPORT int game_runtime_open(const char *path, int flags, ...) __asm("_open");
int game_runtime_open(const char *path, int flags, ...) {
  int mode = 0;
  if (flags & O_CREAT) {
    va_list arguments;
    va_start(arguments, flags);
    mode = va_arg(arguments, int);
    va_end(arguments);
  }
  return GameRuntimeOpenFile(path, flags, mode);
}

// The retargeted pool reservation sites read the real end of the mapping from x1.
GAME_RUNTIME_EXPORT GameRuntimeMapping game_runtime_mmap(
    void *address, size_t length, int protection, int flags, int descriptor, off_t offset)
    __asm("_mmap");
GameRuntimeMapping game_runtime_mmap(
    void *address, size_t length, int protection, int flags, int descriptor, off_t offset) {
  return GameRuntimeMapMemory(
      address, length, protection, flags, descriptor, offset, __builtin_return_address(0));
}

GAME_RUNTIME_EXPORT int curl_easy_setopt(void *handle, int option, ...) {
  va_list arguments;
  va_start(arguments, option);
  int result = ((int (*)(void *, int, va_list))GameRuntimeCurlFunction("Curl_vsetopt"))(
      handle, option, arguments);
  va_end(arguments);
  return result;
}

GAME_RUNTIME_EXPORT int curl_easy_getinfo(void *handle, int info, ...) {
  va_list arguments;
  va_start(arguments, info);
  void *output = va_arg(arguments, void *);
  va_end(arguments);
  return ((int (*)(void *, int, ...))GameRuntimeCurlFunction("curl_easy_getinfo"))(
      handle, info, output);
}

__asm__(
    ".text\n"
    ".p2align 2\n"
    ".globl _GameRuntimeCallOnStack\n"
    "_GameRuntimeCallOnStack:\n"
    "  stp x29, x30, [sp, #-32]!\n"
    "  str x19, [sp, #16]\n"
    "  mov x29, sp\n"
    "  mov x19, sp\n"
    "  mov sp, x0\n"
    "  mov x0, x2\n"
    "  blr x1\n"
    "  mov sp, x19\n"
    "  ldr x19, [sp, #16]\n"
    "  ldp x29, x30, [sp], #32\n"
    "  ret\n");

__attribute__((constructor)) static void game_runtime_load(void) { GameRuntimeLoad(); }
#endif
