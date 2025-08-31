// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

private import WindowsCore

internal enum PowerManager {
  public struct PolicyInhibition {
    public let system: Bool
    public let display: Bool

    public static func state(always: Bool, powered: Bool, display: Bool) throws -> PolicyInhibition {
      return try Self(system: always || (powered ? PowerManager.IsOnAC : false),
                      display: display)
    }
  }

  public static var IsOnAC: Bool {
    get throws {
      var SystemPowerStatus = SYSTEM_POWER_STATUS()
      guard GetSystemPowerStatus(&SystemPowerStatus) else {
        throw WindowsError()
      }
      return SystemPowerStatus.ACLineStatus == 1
    }
  }

  public static func inhibit(_ policy: PolicyInhibition) {
    let state = ES_CONTINUOUS
              | (policy.system ? ES_SYSTEM_REQUIRED : 0)
              | (policy.display ? ES_DISPLAY_REQUIRED : 0)
    _ = SetThreadExecutionState(state)
  }

  public static func restore() {
    _ = SetThreadExecutionState(ES_CONTINUOUS)
  }
}
