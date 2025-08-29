// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

import ArgumentParser
import FoundationEssentials
import WindowsCore

private var kVigilEvent: String {
  "Global\\org.compnerd.vigil.signal"
}

private struct Policy {
  public let bInhibitIdle: Bool
  public let bInhibitDisplay: Bool

  public static func settings(idle: Bool, system: Bool, display: Bool) throws -> Policy {
    return try Self(bInhibitIdle: idle || (system ? PowerManager.IsOnAC : false),
                    bInhibitDisplay: display)
  }
}

private enum PowerManager {
  public static var IsOnAC: Bool {
    get throws {
      var SystemPowerStatus = SYSTEM_POWER_STATUS()
      guard GetSystemPowerStatus(&SystemPowerStatus) else {
        throw WindowsError()
      }
      return SystemPowerStatus.ACLineStatus == 1
    }
  }

  public static func inhibit(_ policy: Policy) {
    let state = ES_CONTINUOUS
              | (policy.bInhibitIdle ? ES_SYSTEM_REQUIRED : 0)
              | (policy.bInhibitDisplay ? ES_DISPLAY_REQUIRED : 0)
    _ = SetThreadExecutionState(state)
  }

  public static func restore() {
    _ = SetThreadExecutionState(ES_CONTINUOUS)
  }
}

@main
private struct Vigil: ParsableCommand {
  public struct Start: ParsableCommand {
    public static var configuration: CommandConfiguration {
      CommandConfiguration(abstract: "Ignore Power Management events until `vigil end` is called.")
    }

    @Flag(name: .shortAndLong,
          help: "Inhibit display sleep while the command is running.")
    public var display: Bool = false

    @Flag(name: .shortAndLong,
          help: "Inhibit system idle sleep while the command is running.")
    public var idle: Bool = false

    @Flag(name: .shortAndLong,
          help: "Inhibit system idle sleep on AC while the command is running.")
    public var system: Bool = false

    @Option(name: .shortAndLong,
            help: "Timeout in seconds for the Power Management Policy suspension.")
    public var timeout: UInt?

    public func validate() throws {
      guard idle || display || system else {
        throw ValidationError("at least one of `--idle`, `--system`, or `--display` must be specified")
      }
    }

    public func run() throws {
      // Create a named event that `vigil end` can signal.
      var hEvent = kVigilEvent.withCString(encodedAs: UTF16.self) {
        CreateEventW(nil, true, false, $0)
      }
      if hEvent == HANDLE(bitPattern: 0) { throw WindowsError() }
      defer { _ = CloseHandle(hEvent) }

      try PowerManager.inhibit(.settings(idle: idle, system: system, display: display))
      defer { PowerManager.restore() }

      var hTimer: HANDLE?
      if let timeout {
        let pCallback: WAITORTIMERCALLBACK = { lpParameter, _ in
          let hEvent = lpParameter?.assumingMemoryBound(to: HANDLE.self).pointee
          _ = SetEvent(hEvent)
        }

        guard CreateTimerQueueTimer(&hTimer, nil, pCallback, &hEvent,
                                    DWORD(Duration.seconds(timeout).milliseconds),
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
        case WAIT_OBJECT_0:
          break
        case WAIT_FAILED:
          throw WindowsError()
        default:
          continue
        }
      } while false
    }
  }

  public struct End: ParsableCommand {
    public static var configuration: CommandConfiguration {
      CommandConfiguration(abstract: "Signal a running `vigil start` to stop and restore power management behaviour.")
    }

    public func run() throws {
      let hEvent = kVigilEvent.withCString(encodedAs: UTF16.self) {
        OpenEventW(EVENT_MODIFY_STATE, false, $0)
      }
      if hEvent == HANDLE(bitPattern: 0) { throw WindowsError() }
      defer { _ = CloseHandle(hEvent) }

      guard SetEvent(hEvent) else {
        throw WindowsError()
      }
    }
  }

  public struct Stand: ParsableCommand {
    @Flag(name: .shortAndLong,
          help: "Inhibit display sleep while the command is running.")
    public var display: Bool = false

    @Flag(name: .shortAndLong,
          help: "Inhibit system idle sleep while the command is running.")
    public var idle: Bool = false

    @Flag(name: .shortAndLong,
          help: "Inhibit system idle sleep on AC while the command is running.")
    public var system: Bool = false

    @Argument(parsing: .remaining,
              help: "Run command while preventing power management events. Use `--` before the command.")
    var command: [String]

    public func run() throws {
      if command.isEmpty { throw CleanExit.helpRequest() }

      try PowerManager.inhibit(.settings(idle: idle, system: system, display: display))
      defer { PowerManager.restore() }

      let hJob = CreateJobObjectW(nil, nil)
      if hJob == HANDLE(bitPattern: 0) { throw WindowsError() }
      defer { _ = CloseHandle(hJob) }

      let hPort = CreateIoCompletionPort(INVALID_HANDLE_VALUE, nil, 0, 1)
      if hPort == HANDLE(bitPattern: 0) { throw WindowsError() }

      var ACPInformation = JOBOBJECT_ASSOCIATE_COMPLETION_PORT()
      ACPInformation.CompletionKey = hJob
      ACPInformation.CompletionPort = hPort
      guard SetInformationJobObject(hJob, JobObjectAssociateCompletionPortInformation,
                                    &ACPInformation,
                                    DWORD(MemoryLayout<JOBOBJECT_ASSOCIATE_COMPLETION_PORT>.size)) else {
        throw WindowsError()
      }

      var LimitInformation = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
      LimitInformation.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK
      guard SetInformationJobObject(hJob, JobObjectExtendedLimitInformation,
                                    &LimitInformation,
                                    DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)) else {
        throw WindowsError()
      }

      var StartupInformation = STARTUPINFOW()
      StartupInformation.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)

      var ProcessInformation = PROCESS_INFORMATION()

      try quote(command).withCString(encodedAs: UTF16.self) { pwszCommandLine in
        guard CreateProcessW(nil, UnsafeMutablePointer(mutating: pwszCommandLine), nil, nil, false,
                             CREATE_SUSPENDED | CREATE_NEW_PROCESS_GROUP,
                             nil, nil, &StartupInformation, &ProcessInformation) else {
          throw WindowsError()
        }
      }

      defer { _ = CloseHandle(ProcessInformation.hThread) }
      defer { _ = CloseHandle(ProcessInformation.hProcess) }

      guard AssignProcessToJobObject(hJob, ProcessInformation.hProcess) else {
        throw WindowsError()
      }

      if Int(ResumeThread(ProcessInformation.hThread)) < 0 {
        throw WindowsError()
      }

      var dwCompletionCode: DWORD = 0
      var ulCompletionKey: ULONG_PTR = 0
      var lpOverlapped: LPOVERLAPPED?
      while GetQueuedCompletionStatus(hPort, &dwCompletionCode, &ulCompletionKey, &lpOverlapped, INFINITE),
          !(ulCompletionKey == ULONG_PTR(UInt(bitPattern: hJob)) && dwCompletionCode == JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO) {
      }

      var dwExitCode = DWORD(bitPattern: -1)
      _ = GetExitCodeProcess(ProcessInformation.hProcess, &dwExitCode)
      ucrt.exit(CInt(bitPattern: dwExitCode))
    }
  }

  public static var configuration: CommandConfiguration {
    CommandConfiguration(abstract: "Prevent the machine from sleeping.",
                         version: PackageVersion,
                         subcommands: [Start.self, End.self, Stand.self],
                         defaultSubcommand: Stand.self)
  }
}
