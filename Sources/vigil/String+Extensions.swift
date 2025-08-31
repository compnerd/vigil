// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

internal import Foundation

extension Optional where Wrapped == String {
  internal func withUTF16CString<T>(_ body: (UnsafePointer<UTF16.CodeUnit>?) throws -> T)
      rethrows -> T {
    guard let self else { return try body(nil) }
    return try self.withCString(encodedAs: UTF16.self, body)
  }
}
