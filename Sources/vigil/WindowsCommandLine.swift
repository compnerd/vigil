// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

extension CommandLine {
  private enum Argument<StringType: StringProtocol> {
    enum Segment {
      case literal(StringType.SubSequence)
      case backslashes(Int)
      case quote
    }

    case unquoted(StringType.SubSequence)
    case quoted([Segment], length: Int)

    var length: Int {
      switch self {
      case let .unquoted(literal): literal.utf8.count
      case let .quoted(_, length): length + 2
      }
    }
  }

  private static func quote<StringType: StringProtocol>(argument: StringType) -> Argument<StringType> {
    // Fast path: no quoting needed
    guard argument.contains(where: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\"" }) else {
      return .unquoted(argument[...])
    }

    // Segment the argument for quoting
    var segments = Array<Argument<StringType>.Segment>()
    var length = 0

    var index = argument.startIndex
    while index < argument.endIndex {
      // Find next backslash or quote
      guard let next = argument[index...].firstIndex(where: { $0 == "\\" || $0 == "\"" }) else {
        // Rest of string is literal
        let segment = argument[index...]
        length += segment.utf8.count
        segments.append(.literal(segment))
        break
      }

      // Add any literal text before the special character
      if next > index {
        let segment = argument[index ..< next]
        length += segment.utf8.count
        segments.append(.literal(segment))
      }

      index = next

      // Handle backslash or quote
      if argument[index] == "\\" {
        // Count consecutive backslashes
        let start = index
        guard let end = argument[start...].firstIndex(where: { $0 != "\\" }) else {
          // String ends with backslashes - double them for closing quote
          let backslashes = argument.distance(from: start, to: argument.endIndex)
          length += backslashes * 2
          segments.append(.backslashes(backslashes * 2))
          break
        }

        index = end

        let count = argument.distance(from: start, to: index)
        if argument[index] == "\"" {
          // Backslashes before quote need escaping: 2n+1 total
          length += count * 2 + 1
          segments.append(.backslashes(count * 2 + 1))
          length += 1
          segments.append(.quote)
          index = argument.index(after: index)
        } else {
          // Regular backslashes - emit as-is
          length += count
          segments.append(.backslashes(count))
        }
      } else {
        assert(argument[index] == "\"")
        // Bare quote (no preceding backslashes)
        length += 1
        segments.append(.backslashes(1))  // Escape the quote
        length += 1
        segments.append(.quote)
        index = argument.index(after: index)
      }
    }

    return .quoted(segments, length: length)
  }

  private static func build<CollectionType: Collection, StringType: StringProtocol>(_ arguments: CollectionType, length: Int) -> String where CollectionType.Element == Argument<StringType> {
    return String(unsafeUninitializedCapacity: length) { buffer in
      var offset = 0

      func write(_ byte: UInt8) {
        buffer[offset] = byte
        offset += 1
      }

      func write(_ bytes: any Collection<UInt8>) {
        var index = offset
        for byte in bytes {
          buffer[index] = byte
          index += 1
        }
        offset += bytes.count
      }

      func write(segment: Argument<StringType>.Segment) {
        switch segment {
        case .literal(let literal):
          write(literal.utf8)
        case .backslashes(let count):
          write(repeatElement(UInt8(ascii: "\\"), count: count))
        case .quote:
          write(UInt8(ascii: "\""))
        }
      }

      for (index, element) in arguments.enumerated() {
        if index > 0 { write(UInt8(ascii: " ")) }
        switch element {
        case let .unquoted(literal):
          write(literal.utf8)
        case let .quoted(segments, _):
          write(UInt8(ascii: "\""))
          for segment in segments { write(segment: segment) }
          write(UInt8(ascii: "\""))
        }
      }

      return offset
    }
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
  internal static func quote<SequenceType: Sequence>(_ arguments: SequenceType) -> String where SequenceType.Element: StringProtocol {
    let (arguments, length) = arguments.reduce(into: (arguments: Array<Argument<SequenceType.Element>>(), length: 0)) { (accumulator, argument) in
      let argument = quote(argument: argument)
      accumulator.arguments.append(argument)
      accumulator.length += argument.length
    }
    guard !arguments.isEmpty else { return "" }
    return build(arguments, length: length + arguments.count - 1)
  }
}
