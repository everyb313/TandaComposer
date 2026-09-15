//
//  OutputFormatter.swift
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

public enum OutputFormatter {

    public static func plain(_ results: [FileMetadataResult], grouped: Bool) -> String {
        var lines: [String] = []
        for result in results {
            lines.append("==== \(result.path) ====")
            for row in result.rows {
                let label = grouped ? "\(row.group):\(row.key)" : row.key
                lines.append("\(label): \(row.value)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func json(_ results: [FileMetadataResult], grouped: Bool) throws -> String {
        var payload: [String: [String: String]] = [:]
        for result in results {
            var fileDict: [String: String] = [:]
            for row in result.rows {
                let label = grouped ? "\(row.group):\(row.key)" : row.key
                fileDict[label] = row.value
            }
            payload[result.path] = fileDict
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func csv(_ results: [FileMetadataResult], grouped: Bool) -> String {
        var lines = ["file,group,key,value"]
        for result in results {
            for row in result.rows {
                let group = grouped ? row.group : ""
                lines.append([result.path, group, row.key, row.value].map(csvEscape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func xml(_ results: [FileMetadataResult], grouped: Bool) -> String {
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<audiotag>"]
        for result in results {
            lines.append("  <file path=\"\(xmlEscape(result.path))\">")
            for row in result.rows {
                let groupAttr = grouped ? " group=\"\(xmlEscape(row.group))\"" : ""
                lines.append("    <tag key=\"\(xmlEscape(row.key))\"\(groupAttr) value=\"\(xmlEscape(row.value))\"/>")
            }
            lines.append("  </file>")
        }
        lines.append("</audiotag>")
        return lines.joined(separator: "\n")
    }

    // Marked `nonisolated`: passed as a bare function reference to
    // `.map(csvEscape)` below, which needs a plain (non-actor-isolated)
    // function value — it touches no actor-isolated state anyway.
    private nonisolated static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
