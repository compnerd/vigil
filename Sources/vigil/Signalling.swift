// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

internal import WindowsCore

private var kVigilEvent: String {
  "Global\\org.compnerd.vigil.sentinel"
}

extension Vigil {
  public static func begin() throws -> HANDLE {
    // Create a named event that `vigil end` can signal.
    let hEvent = kVigilEvent.withCString(encodedAs: UTF16.self) {
      CreateEventW(nil, true, false, $0)
    }
    guard let hEvent else { throw WindowsError() }
    return hEvent
  }

  public static func stand(_ hEvent: HANDLE, for duration: Duration?) throws {
    var hEvent = hEvent

    var hTimer: HANDLE?
    if let duration {
      let pCallback: WAITORTIMERCALLBACK = { lpParameter, _ in
        if let hEvent = lpParameter?.assumingMemoryBound(to: HANDLE.self).pointee {
          _ = SetEvent(hEvent)
        }
      }

      guard CreateTimerQueueTimer(&hTimer, nil, pCallback, &hEvent,
                                  DWORD(duration.milliseconds),
                                  0, WT_EXECUTEINTIMERTHREAD | WT_EXECUTEONLYONCE) else {
        throw WindowsError()
      }
    }

    defer {
      if let hTimer {
        _ = DeleteTimerQueueTimer(nil, hTimer, nil)
      }
    }

    repeat {
      switch WaitForSingleObject(hEvent, INFINITE) {
      case WAIT_OBJECT_0: return
      case WAIT_FAILED: throw WindowsError()
      default: continue
      }
    } while true
  }

  public static func end() throws {
    let hEvent = kVigilEvent.withCString(encodedAs: UTF16.self) {
      OpenEventW(EVENT_MODIFY_STATE, false, $0)
    }
    guard let hEvent else { throw WindowsError() }
    defer { _ = CloseHandle(hEvent) }
    guard SetEvent(hEvent) else { throw WindowsError() }
  }
}
