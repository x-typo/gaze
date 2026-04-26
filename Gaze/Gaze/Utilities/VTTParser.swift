import Foundation

enum VTTParser {
    nonisolated static func parse(_ text: String) throws -> [CaptionCue] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = splitBlocks(in: normalizedText)

        let header = blocks.first.map(normalizedHeader)
        guard let header, header.hasPrefix("WEBVTT") else {
            throw VTTParserError.missingHeader
        }

        return try blocks.dropFirst().reduce(into: [CaptionCue]()) { cues, block in
            guard let cue = try parseBlock(block, id: cues.count) else {
                return
            }

            cues.append(cue)
        }
    }

    nonisolated private static func splitBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var currentBlockLines: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !currentBlockLines.isEmpty {
                    blocks.append(currentBlockLines.joined(separator: "\n"))
                    currentBlockLines.removeAll(keepingCapacity: true)
                }
            } else {
                currentBlockLines.append(line)
            }
        }

        if !currentBlockLines.isEmpty {
            blocks.append(currentBlockLines.joined(separator: "\n"))
        }

        return blocks
    }

    nonisolated private static func normalizedHeader(_ block: String) -> String {
        let withoutBOM = block.hasPrefix("\u{FEFF}") ? String(block.dropFirst()) : block
        return withoutBOM.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseBlock(_ block: String, id: Int) throws -> CaptionCue? {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
            return nil
        }

        let timingParts = lines[timingIndex].components(separatedBy: "-->")
        guard timingParts.count == 2 else {
            return nil
        }

        let startTime = try parseTimestamp(timingParts[0])
        let endTime = try parseTimestamp(timingParts[1])
        guard endTime > startTime else {
            return nil
        }

        let cueText = lines
            .dropFirst(timingIndex + 1)
            .map(cleanCueLine)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cueText.isEmpty else {
            return nil
        }

        return CaptionCue(
            id: id,
            startTime: startTime,
            endTime: endTime,
            text: cueText
        )
    }

    nonisolated private static func parseTimestamp(_ rawValue: String) throws -> TimeInterval {
        let timestamp = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)?
            .replacingOccurrences(of: ",", with: ".")

        guard let timestamp else {
            throw VTTParserError.invalidTimestamp(rawValue)
        }

        let components = timestamp.split(separator: ":").map(String.init)
        guard components.count == 2 || components.count == 3 else {
            throw VTTParserError.invalidTimestamp(rawValue)
        }

        let secondsText = components[components.count - 1]
        let minutesText = components[components.count - 2]
        let hoursText = components.count == 3 ? components[0] : "0"

        guard let hours = TimeInterval(hoursText),
              let minutes = TimeInterval(minutesText),
              let seconds = TimeInterval(secondsText) else {
            throw VTTParserError.invalidTimestamp(rawValue)
        }

        return (hours * 3_600) + (minutes * 60) + seconds
    }

    nonisolated private static func cleanCueLine(_ line: String) -> String {
        decodeEntities(stripMarkup(from: line))
    }

    nonisolated private static func stripMarkup(from line: String) -> String {
        var output = ""
        var isInsideTag = false

        for character in line {
            switch character {
            case "<":
                isInsideTag = true
            case ">":
                isInsideTag = false
            default:
                if !isInsideTag {
                    output.append(character)
                }
            }
        }

        return output
    }

    nonisolated private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

enum VTTParserError: Error, LocalizedError {
    case missingHeader
    case invalidTimestamp(String)

    var errorDescription: String? {
        switch self {
        case .missingHeader:
            "Caption file is missing a WEBVTT header."
        case .invalidTimestamp(let value):
            "Caption timestamp is invalid: \(value)"
        }
    }
}
