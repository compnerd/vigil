// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

extension Duration {
  internal var seconds: Double {
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
  }

  internal var milliseconds: Int64 {
    let seconds = Int64(components.seconds)
    guard seconds <= .max / 1_000 else { return .max }
    return seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
  }
}
