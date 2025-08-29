// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

internal func quote<S: Sequence>(_ arguments: S) -> String where S.Element == String {
  func quote(argument: String) -> String {
    if !argument.contains(" \t\n\"") {
      return argument
    }

    // To escape the command line, we surround the argument with quotes.
    // However, the complication comes due to how the Windows command line
    // parser treats backslashes (\) and quotes (").
    //
    // - \ is normally treated as a literal backslash
    //      e.g. alpha\beta\gamma => alpha\beta\gamma
    // - The sequence \" is treated as a literal "
    //      e.g. alpha\"beta => alpha"beta
    //
    // But then what if we are given a path that ends with a \?
    //
    // Surrounding alpha\beta\ with " would be "alpha\beta\" which would be
    // an unterminated string since it ends on a literal quote. To allow
    // this case the parser treats:
    //
    //  - \\" as \ followed by the " metacharacter
    //  - \\\" as \ followed by a literal "
    //
    // In general:
    //  - 2n \ followed by " => n \ followed by the " metacharacter
    //  - 2n + 1 \ followed by " => n \ followed by a literal "
    var unquoted = argument.unicodeScalars
    var quoted = ""

    // Rough (over-)estimate of the capacity needed for the quoted string
    quoted.reserveCapacity(argument.count * 2)

    quoted.append("\"")
    while !unquoted.isEmpty {
      guard let index = unquoted.firstIndex(where: { $0 != "\\" }) else {
        // String ends with a backslash (e.g. first\second\), escape all
        // the backslashes then add the metacharacter ".
        let count = unquoted.count
        quoted.append(String(repeating: "\\", count: 2 * count))
        break
      }

      let count = unquoted.distance(from: unquoted.startIndex, to: index)
      if unquoted[index] == "\"" {
        // This is a string of \ followed by a " (e.g. first\"second).
        // Escape the backslashes and the quote.
        quoted.append(String(repeating: "\\", count: 2 * count + 1))
      } else {
        // These are just literal backslashes
        quoted.append(String(repeating: "\\", count: count))
      }

      quoted.append(String(unquoted[index]))

      // Drop the backslashes and the following character
      unquoted.removeFirst(count + 1)
    }
    quoted.append("\"")

    return quoted
  }
  return arguments.map(quote(argument:)).joined(separator: " ")
}
