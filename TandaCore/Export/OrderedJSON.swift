//
//  OrderedJSON.swift
//
//  Copyright © 2026 Hagen Eckert.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

/// A minimal JSON value tree that serializes objects with keys in
/// exactly the order given, instead of Foundation's `JSONEncoder`.
///
/// `JSONEncoder` looks like it should preserve the order in which a
/// `Codable` type calls `encode(_:forKey:)`, but on Apple platforms it
/// currently doesn't guarantee that — object keys can come out in an
/// effectively arbitrary order, regardless of struct property order or
/// encode-call order (confirmed empirically: reordering `Song`'s stored
/// properties in Models.swift had no effect on the exported file's key
/// order). Anywhere a specific, human-curated key order matters in an
/// exported file, build a `JSONValue` tree by hand and call
/// `serialized()` instead of going through `JSONEncoder`.
///
/// Decoding is unaffected by any of this — `JSONDecoder` reads objects
/// by key name, not position — so existing `Codable`/`JSONDecoder`
/// round-trips elsewhere in the app don't need to change.
/// Pure data type — never touches actor-isolated state, so the whole
/// type (and its extensions below) is marked `nonisolated`. Without
/// this it inherits the project's default MainActor isolation, which
/// then blocks callers like `SetlistMetadataExport`'s `orderedJSONValue`
/// (itself `nonisolated`, since it's used as a bare function reference
/// passed to `.map(...)`) from calling into it synchronously.
public nonisolated indirect enum JSONValue {
    case null
    case bool(Bool)
    case number(String)  // pre-formatted literal, so the caller controls int vs. double formatting
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])  // ordered pairs — the whole point of this type
}

nonisolated extension JSONValue {

    // MARK: Optional-friendly constructors (`nil` -> JSON null)

    public static func opt(_ s: String?) -> JSONValue {
        s.map(JSONValue.string) ?? .null
    }

    public static func opt(_ i: Int?) -> JSONValue {
        i.map { .number(String($0)) } ?? .null
    }

    public static func opt(_ i: Int64?) -> JSONValue {
        i.map { .number(String($0)) } ?? .null
    }

    public static func opt(_ d: Double?) -> JSONValue {
        guard let d else { return .null }
        return .number(formatted(d))
    }

    /// Whole-number Doubles print without a trailing ".0" (e.g. a bpm
    /// of `111.0` prints as `111`), matching what this app's files
    /// looked like previously. Fractional values print via Swift's
    /// normal shortest round-trippable `Double` description.
    private static func formatted(_ d: Double) -> String {
        if d.truncatingRemainder(dividingBy: 1) == 0, abs(d) < 1e15 {
            return String(Int64(d))
        }
        return String(d)
    }
}

nonisolated extension JSONValue {

    /// Pretty-printed (2-space indent) JSON text, keys in the exact
    /// order supplied to `.object(...)`.
    public func serialized() -> String {
        var out = ""
        write(into: &out, indent: 0)
        return out
    }

    private func write(into out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        let padInner = String(repeating: "  ", count: indent + 1)

        switch self {
        case .null:
            out += "null"

        case .bool(let b):
            out += b ? "true" : "false"

        case .number(let n):
            out += n

        case .string(let s):
            out += Self.escaped(s)

        case .array(let items):
            guard !items.isEmpty else {
                out += "[]"
                return
            }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += padInner
                item.write(into: &out, indent: indent + 1)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += pad + "]"

        case .object(let pairs):
            guard !pairs.isEmpty else {
                out += "{}"
                return
            }
            out += "{\n"
            for (i, pair) in pairs.enumerated() {
                let (key, value) = pair
                out += padInner + Self.escaped(key) + " : "
                value.write(into: &out, indent: indent + 1)
                out += i < pairs.count - 1 ? ",\n" : "\n"
            }
            out += pad + "}"
        }
    }

    /// Matches the escaping this app's Setlist files already used
    /// under `JSONEncoder` (notably: forward slashes are escaped as
    /// `\/`), so existing files stay visually consistent with newly
    /// written ones even though migration isn't required.
    private static func escaped(_ s: String) -> String {
        var result = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "/": result += "\\/"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}
