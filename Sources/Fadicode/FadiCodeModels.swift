import Foundation
import AppKit

// MARK: - Claude Question Model

/// Represents a detected multi-choice question from Claude Code.
struct ClaudeQuestion: Equatable {
    let questionText: String
    let options: [(label: String, value: String)]

    static func == (lhs: ClaudeQuestion, rhs: ClaudeQuestion) -> Bool {
        lhs.questionText == rhs.questionText && lhs.options.map(\.value) == rhs.options.map(\.value)
    }

    /// Parse a Claude Code AskUserQuestion pattern from terminal content.
    static func parse(from content: String) -> ClaudeQuestion? {
        let lines = content.components(separatedBy: "\n")

        // Step 1: Find the navigation footer (anchor)
        var footerIndex: Int?
        for i in stride(from: lines.count - 1, through: max(0, lines.count - 15), by: -1) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Enter to select") || trimmed.contains("to navigate")
                || trimmed.contains("ctrl-g to edi") {
                footerIndex = i
                break
            }
        }

        guard let footer = footerIndex else { return nil }

        // Step 2: Scan upward from footer, collecting numbered options
        guard let ansiPattern = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[A-Za-z]"#) else { return nil }
        func stripAnsi(_ s: String) -> String {
            ansiPattern.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        guard let optionPattern = try? NSRegularExpression(pattern: #"^\s*(\d+)\.\s+(.+)$"#) else { return nil }
        var options: [(label: String, value: String)] = []
        var topOptionIndex = footer

        for i in stride(from: footer - 1, through: max(0, footer - 40), by: -1) {
            var clean = stripAnsi(lines[i])
            while let first = clean.unicodeScalars.first,
                  first == "\u{276F}" || first == "\u{203A}" || first == ">"
                  || first == "\u{25B8}" || first == "\u{25B6}" {
                clean = String(clean.dropFirst())
            }
            let trimmedClean = clean.trimmingCharacters(in: .whitespaces)
            let range = NSRange(clean.startIndex..., in: clean)
            if let match = optionPattern.firstMatch(in: clean, range: range),
               let numRange = Range(match.range(at: 1), in: clean),
               let labelRange = Range(match.range(at: 2), in: clean) {
                let num = String(clean[numRange])
                let label = String(clean[labelRange]).trimmingCharacters(in: .whitespaces)
                options.insert((label: label, value: num), at: 0)
                topOptionIndex = i
            } else if !trimmedClean.isEmpty {
                let leadingSpaces = clean.prefix(while: { $0 == " " }).count
                if !options.isEmpty && leadingSpaces < 4 {
                    break
                }
            }
        }

        guard options.count >= 2 else { return nil }

        // Step 3: Find question text
        var questionText = ""
        for i in stride(from: topOptionIndex - 1, through: max(0, topOptionIndex - 10), by: -1) {
            let clean = stripAnsi(lines[i])
            let trimmed = clean.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let leadingSpaces = clean.prefix(while: { $0 == " " }).count
            let matchRange = NSRange(clean.startIndex..., in: clean)
            if leadingSpaces >= 4 && optionPattern.firstMatch(in: clean, range: matchRange) == nil {
                continue
            }
            if trimmed.hasPrefix("? ") {
                questionText = String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("❯ ") {
                questionText = String(trimmed.dropFirst(2))
            } else {
                questionText = trimmed
            }
            break
        }

        if questionText.isEmpty {
            questionText = "Choose an option"
        }

        return ClaudeQuestion(questionText: questionText, options: options)
    }
}
