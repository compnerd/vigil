// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

import ArgumentParser
import FoundationEssentials
internal import WindowsCore

private struct SleepInhibitionOptions: ParsableArguments {
  @Flag(name: .shortAndLong,
        help: "Inhibit display sleep while the command is running.")
  public var display: Bool = false

  @Flag(name: .shortAndLong,
        help: "Inhibit system idle sleep while the command is running.")
  public var idle: Bool = false

  @Flag(name: .shortAndLong,
        help: "Inhibit system idle sleep on AC while the command is running.")
  public var system: Bool = false

  public func validate() throws {
    guard idle || display || system else {
      throw ValidationError("at least one of `--idle`, `--system`, or `--display` must be specified")
    }
  }

  internal var flags: [String] {
    [
      idle ? "--idle" : nil,
      display ? "--display" : nil,
      system ? "--system" : nil
    ].compactMap { $0 }
  }
}

@main
internal struct Vigil: ParsableCommand {
  public struct Start: ParsableCommand {
    public static var configuration: CommandConfiguration {
      CommandConfiguration(abstract: "Ignore Power Management events until `vigil end` is called.")
    }

    @OptionGroup
    private var inhibition: SleepInhibitionOptions

    @Option(name: .shortAndLong,
            help: "Timeout in seconds for the Power Management Policy suspension.")
    public var timeout: UInt?

    @Flag(name: .shortAndLong, help: "Run the command in the background.")
    public var daemonize = false

    public func validate() throws {
      if daemonize, timeout == nil {
        throw ValidationError("Timeout must be specified when running as a daemon.")
      }
    }

    public func run() throws {
      if daemonize {
        let arguments = [Vigil.executable, "daemon", "--timeout", String(timeout!)] + inhibition.flags
        try CommandLine.quote(arguments).withCString(encodedAs: UTF16.self) {
          var StartupInformation = STARTUPINFOW()
          StartupInformation.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)

          var ProcessInformation = PROCESS_INFORMATION()

          guard CreateProcessW(nil, UnsafeMutablePointer(mutating: $0), nil, nil,
                               false, CREATE_NO_WINDOW | DETACHED_PROCESS,
                               nil, nil, &StartupInformation, &ProcessInformation) else {
            throw WindowsError()
          }

          _ = CloseHandle(ProcessInformation.hThread)
          _ = CloseHandle(ProcessInformation.hProcess)
        }
        return
      }

      let hEvent = try Vigil.begin()
      defer { _ = CloseHandle(hEvent) }

      try PowerManager.inhibit(.state(always: inhibition.idle,
                                      powered: inhibition.system,
                                      display: inhibition.display))
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
    public static var configuration: CommandConfiguration {
      CommandConfiguration(abstract: "Stand vigil, running a given command.")
    }

    @OptionGroup
    private var inhibition: SleepInhibitionOptions

    @Argument(parsing: .remaining,
              help: "Run command while preventing power management events. Use `--` before the command.")
    var command: [String]

    public func run() throws {
      if command.isEmpty { throw CleanExit.helpRequest() }

      try PowerManager.inhibit(.state(always: inhibition.idle,
                                      powered: inhibition.system,
                                      display: inhibition.display))
      defer { PowerManager.restore() }

      let job = try Job.create()
      let ProcessInformation = try job.launch(command)
      defer {
        _ = CloseHandle(ProcessInformation.hThread)
        _ = CloseHandle(ProcessInformation.hProcess)
      }

      job.await()

      var dwExitCode = DWORD(bitPattern: -1)
      _ = GetExitCodeProcess(ProcessInformation.hProcess, &dwExitCode)
      ucrt.exit(CInt(bitPattern: dwExitCode))
    }
  }

  public struct Daemon: ParsableCommand {
    public static var configuration: CommandConfiguration {
      CommandConfiguration(abstract: "Stand vigil for a given duration in the background.",
                           shouldDisplay: false)
    }

    @OptionGroup
    private var inhibition: SleepInhibitionOptions

    @Option(name: .shortAndLong,
            help: "Timeout in seconds for the Power Management Policy suspension.")
    public var timeout: UInt

    public func run() throws {
      let hEvent = try Vigil.begin()
      defer { _ = CloseHandle(hEvent) }

      try PowerManager.inhibit(.state(always: inhibition.idle,
                                      powered: inhibition.system,
                                      display: inhibition.display))
      defer { PowerManager.restore() }

      try Vigil.stand(hEvent, for: Duration.seconds(timeout))
    }
  }

  public static var configuration: CommandConfiguration {
    CommandConfiguration(abstract: "Prevent the machine from sleeping.",
                         version: PackageVersion,
                         subcommands: [Start.self, End.self, Stand.self, Daemon.self],
                         defaultSubcommand: Stand.self)
  }
}
