// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

import ArgumentParser
import FoundationEssentials
private import WindowsCore

@main
internal struct Vigil: ParsableCommand {
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
      let hEvent = try Vigil.begin()
      defer { _ = CloseHandle(hEvent) }

      try PowerManager.inhibit(.state(always: idle, powered: system, display: display))
      defer { PowerManager.restore() }

      try Vigil.stand(hEvent, for: timeout.map(Duration.seconds(_:)))
    }
  }

  public struct End: ParsableCommand {
    public static var configuration: CommandConfiguration {
      CommandConfiguration(abstract: "Signal a running `vigil start` to stop and restore power management behaviour.")
    }

    public func run() throws {
      try Vigil.end()
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

      try PowerManager.inhibit(.state(always: idle, powered: system, display: display))
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
