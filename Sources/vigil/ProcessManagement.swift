// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

internal import WindowsCore

internal struct Job: ~Copyable {
  internal struct Configuration {
    fileprivate func apply(to job: inout Job) throws {
      var LimitInformation = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
      LimitInformation.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK
      guard SetInformationJobObject(job.hJob, JobObjectExtendedLimitInformation,
                                    &LimitInformation,
                                    DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)) else {
        throw WindowsError()
      }
    }

    internal static var `default`: Configuration {
      Configuration()
    }
  }

  private var hJob: HANDLE
  private var hPort: HANDLE

  internal static func create(name: String? = nil, configuration: Configuration = .default) throws -> Job {
    // Create job object
    let hJob = try name.withUTF16CString {
      guard let hJob = CreateJobObjectW(nil, $0) else { throw WindowsError() }
      return hJob
    }

    // Create completion port
    let hPort = CreateIoCompletionPort(INVALID_HANDLE_VALUE, nil, 0, 1)
    guard let hPort else {
      CloseHandle(hJob)
      throw WindowsError()
    }

    var job = Job(hJob: hJob, hPort: hPort)

    var ACPInformation = JOBOBJECT_ASSOCIATE_COMPLETION_PORT()
    ACPInformation.CompletionKey = hJob
    ACPInformation.CompletionPort = hPort
    guard SetInformationJobObject(hJob, JobObjectAssociateCompletionPortInformation,
                                  &ACPInformation,
                                  DWORD(MemoryLayout<JOBOBJECT_ASSOCIATE_COMPLETION_PORT>.size)) else {
      throw WindowsError()
    }
    try configuration.apply(to: &job)

    return job
  }

  deinit {
    CloseHandle(hJob)
    CloseHandle(hPort)
  }

  internal func assign(process hProcess: HANDLE?) throws {
    guard AssignProcessToJobObject(hJob, hProcess) else {
      throw WindowsError()
    }
  }

  internal func launch(_ command: [String]) throws -> PROCESS_INFORMATION {
    var StartupInformation = STARTUPINFOW()
    StartupInformation.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)

    var ProcessInformation = PROCESS_INFORMATION()

    try CommandLine.quote(command).withCString(encodedAs: UTF16.self) { pwszCommandLine in
      guard CreateProcessW(nil, UnsafeMutablePointer(mutating: pwszCommandLine), nil, nil, false,
                            CREATE_SUSPENDED | CREATE_NEW_PROCESS_GROUP,
                            nil, nil, &StartupInformation, &ProcessInformation) else {
        throw WindowsError()
      }
    }

    try assign(process: ProcessInformation.hProcess)

    if Int(ResumeThread(ProcessInformation.hThread)) < 0 {
      throw WindowsError()
    }

    return ProcessInformation
  }

  internal func `await`() {
    var dwCompletionCode: DWORD = 0
    var ulCompletionKey: ULONG_PTR = 0
    var lpOverlapped: LPOVERLAPPED?
    while GetQueuedCompletionStatus(hPort, &dwCompletionCode, &ulCompletionKey,
                                    &lpOverlapped, INFINITE) {
      if ulCompletionKey == ULONG_PTR(UInt(bitPattern: hJob)),
          dwCompletionCode == JOB_OBJECT_MSG_ACTIVE_PROCESS_ZERO {
        return
      }
    }
  }
}

extension Vigil {
  internal static var executable: String {
    var dwSize: DWORD = 0
    guard !QueryFullProcessImageNameW(GetCurrentProcess(), 0, nil, &dwSize),
        GetLastError() == ERROR_INSUFFICIENT_BUFFER else {
      return CommandLine.arguments[0]
    }
    return withUnsafeTemporaryAllocation(of: WCHAR.self, capacity: Int(dwSize)) { pBuffer in
      var size = dwSize
      guard QueryFullProcessImageNameW(GetCurrentProcess(), 0, pBuffer.baseAddress, &size) else {
        return CommandLine.arguments[0]
      }
      return String(decoding: UnsafeBufferPointer(start: pBuffer.baseAddress, count: Int(size)), as: UTF16.self)
    }
  }
}
