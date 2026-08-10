#ifndef GAME_RUNTIME_ABI_H
#define GAME_RUNTIME_ABI_H

#include <CoreFoundation/CoreFoundation.h>
#include <crt_externs.h>
#include <stdint.h>
#include <sys/types.h>

/// The game's `mmap` import returns the mapping in x0 and, at patched pool sites, its end in x1.
typedef struct {
  void *_Nullable base;
  uintptr_t end;
} GameRuntimeMapping;

/// AppKit data symbols imported by the game and its libraries.
extern void *_Nullable NSApp;
extern const CFStringRef _Nonnull NSApplicationDidBecomeActiveNotification;
extern const CFStringRef _Nonnull NSApplicationDidResignActiveNotification;
extern const CFStringRef _Nonnull NSApplicationWillResignActiveNotification;
extern const CFStringRef _Nonnull NSWindowDidBecomeKeyNotification;
extern const CFStringRef _Nonnull NSWindowDidResignKeyNotification;
extern const CFStringRef _Nonnull NSWindowDidResizeNotification;
extern const CFStringRef _Nonnull NSWindowWillCloseNotification;
extern const CFStringRef _Nonnull NSWindowWillExitFullScreenNotification;
extern const CFStringRef _Nonnull NSImageHintInterpolation;

/// Calls `body(context)` with the stack pointer at `top` (16-byte aligned), then restores it.
int GameRuntimeCallOnStack(
    void *_Nonnull top, int (*_Nonnull body)(void *_Nullable), void *_Nullable context);

/// The system `open`, for paths the runtime already resolved.
int GameRuntimeSystemOpen(const char *_Nullable path, int flags, int mode);

/// libdispatch's main-queue drain, used while the game is held in the background.
extern void _dispatch_main_queue_callback_4CF(void *_Nullable message);

#endif
