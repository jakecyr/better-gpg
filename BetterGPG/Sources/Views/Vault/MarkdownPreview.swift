import SwiftUI

struct MarkdownPreview: View {
    var source: String

    var body: some View {
        ScrollView {
            if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Rendered Markdown shows up here as you type.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MarkdownParser.parse(source)) { block in
                        MarkdownBlockView(block: block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block.content {
        case .heading(let level, let inlines):
            Text(MarkdownInlineText.attributed(inlines, font: headingFont(level)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 8 : 12)
                .padding(.bottom, 6)
        case .paragraph(let inlines):
            Text(MarkdownInlineText.attributed(inlines, font: .body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 10)
        case .quote(let children):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children) { child in
                        MarkdownBlockView(block: child)
                    }
                }
            }
            .padding(.bottom, 10)
        case .listItem(let level, let marker, let inlines):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: marker.count > 1 ? 22 : 14, alignment: .trailing)
                Text(MarkdownInlineText.attributed(inlines, font: .body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 18)
            .padding(.bottom, 4)
        case .rule:
            Divider()
                .padding(.vertical, 8)
        case .spacer:
            Color.clear
                .frame(height: 16)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 28, weight: .bold)
        case 2: return .system(size: 22, weight: .bold)
        case 3: return .system(size: 18, weight: .semibold)
        default: return .system(size: 16, weight: .semibold)
        }
    }
}

private struct MarkdownBlock: Identifiable {
    let id: Int
    var content: Content

    enum Content {
        case heading(Int, [MarkdownInline])
        case paragraph([MarkdownInline])
        case code(String)
        case quote([MarkdownBlock])
        case listItem(level: Int, marker: String, inlines: [MarkdownInline])
        case rule
        case spacer
    }
}

private enum MarkdownInline {
    case text(String)
    case code(String)
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strike([MarkdownInline])
    case link([MarkdownInline], URL?)
}

private enum MarkdownInlineText {
    static func attributed(_ inlines: [MarkdownInline], font: Font) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            result += render(inline, font: font)
        }
        if result.characters.isEmpty {
            var placeholder = AttributedString(" ")
            placeholder.font = font
            return placeholder
        }
        return result
    }

    private static func render(_ inline: MarkdownInline, font: Font) -> AttributedString {
        switch inline {
        case .text(let string):
            var run = AttributedString(string)
            run.font = font
            return run
        case .code(let string):
            var run = AttributedString(string)
            run.font = .system(.body, design: .monospaced)
            run.backgroundColor = Color.primary.opacity(0.08)
            return run
        case .strong(let inner):
            return attributed(inner, font: font.bold())
        case .emphasis(let inner):
            return attributed(inner, font: font.italic())
        case .strike(let inner):
            var run = attributed(inner, font: font)
            run.strikethroughStyle = .single
            return run
        case .link(let inner, let url):
            var run = attributed(inner, font: font)
            run.foregroundColor = .accentColor
            run.underlineStyle = .single
            if let url {
                run.link = url
            }
            return run
        }
    }
}

/// Block renderer for vault notes.
///
/// Foundation's markdown parser removes the line-break characters and only tags headings with a
/// presentation intent that SwiftUI `Text` does not draw. Notes keep a single newline as a line
/// break, and each extra blank line as space.
private enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var nextID = 0
        func make(_ content: MarkdownBlock.Content) -> MarkdownBlock {
            nextID += 1
            return MarkdownBlock(id: nextID, content: content)
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if isBlank(line) {
                var count = 0
                while index < lines.count && isBlank(lines[index]) {
                    count += 1
                    index += 1
                }
                let extras = blocks.isEmpty ? count : count - 1
                for _ in 0..<extras {
                    blocks.append(make(.spacer))
                }
                continue
            }

            if let opened = fence(line) {
                index += 1
                var body: [String] = []
                while index < lines.count {
                    if let closed = fence(lines[index]), closed.marker == opened.marker, closed.count >= opened.count, closed.info.isEmpty {
                        index += 1
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                blocks.append(make(.code(body.joined(separator: "\n"))))
                continue
            }

            if let (level, text) = heading(in: line) {
                blocks.append(make(.heading(level, parseInlines(text))))
                index += 1
                continue
            }

            if quoteText(line) != nil {
                var quoted: [String] = []
                while index < lines.count, let text = quoteText(lines[index]) {
                    quoted.append(text)
                    index += 1
                }
                let children = parse(quoted.joined(separator: "\n"))
                blocks.append(make(.quote(children)))
                continue
            }

            if index + 1 < lines.count, let level = setextLevel(lines[index + 1]), !isSpecial(line) {
                blocks.append(make(.heading(level, parseInlines(line))))
                index += 2
                continue
            }

            if isRule(line) {
                blocks.append(make(.rule))
                index += 1
                continue
            }

            if listItem(in: line) != nil {
                while index < lines.count, let matched = listItem(in: lines[index]) {
                    var item = matched
                    index += 1
                    while index < lines.count && isListContinuation(lines[index]) {
                        item.text += "\n" + lines[index].trimmingCharacters(in: .whitespaces)
                        index += 1
                    }
                    let marker = listMarker(for: &item)
                    blocks.append(make(.listItem(level: item.level, marker: marker, inlines: parseInlines(item.text))))
                }
                continue
            }

            var collected = [line]
            index += 1
            while index < lines.count && !isSpecial(lines[index]) {
                collected.append(lines[index])
                index += 1
            }
            blocks.append(make(.paragraph(parseInlines(collected.joined(separator: "\n")))))
        }
        return blocks
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isSpecial(_ line: String) -> Bool {
        if isBlank(line) { return true }
        if fence(line) != nil { return true }
        if heading(in: line) != nil { return true }
        if quoteText(line) != nil { return true }
        if isRule(line) { return true }
        if listItem(in: line) != nil { return true }
        return false
    }

    private static func heading(in line: String) -> (Int, String)? {
        var spaces = 0
        for character in line {
            if character == " " && spaces < 3 {
                spaces += 1
            } else {
                break
            }
        }
        let rest = line.dropFirst(spaces)
        guard !rest.hasPrefix("\\#") else { return nil }
        guard rest.first == "#" else { return nil }
        var level = 0
        var index = rest.startIndex
        while index < rest.endIndex, rest[index] == "#", level < 7 {
            level += 1
            index = rest.index(after: index)
        }
        guard (1...6).contains(level) else { return nil }
        var text = String(rest[index...])
        if text.first == " " || text.first == "\t" {
            text = text.trimmingCharacters(in: .whitespaces)
        }
        if let range = text.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private static func setextLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        let characters = Set(trimmed)
        return characters == ["-"] || characters == ["*"] || characters == ["_"]
    }

    private static func quoteText(_ line: String) -> String? {
        var spaces = 0
        for character in line {
            if character == " " && spaces < 3 {
                spaces += 1
            } else {
                break
            }
        }
        let rest = line.dropFirst(spaces)
        guard rest.first == ">" else { return nil }
        var body = rest.dropFirst()
        if body.first == " " {
            body = body.dropFirst()
        }
        return String(body)
    }

    private static func fence(_ line: String) -> (marker: Character, count: Int, info: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        var count = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == marker {
            count += 1
            index = trimmed.index(after: index)
        }
        guard count >= 3 else { return nil }
        let info = trimmed[index...].trimmingCharacters(in: .whitespaces)
        if marker == "`" && info.contains("`") { return nil }
        return (marker, count, info)
    }

    private struct ListMatch {
        var level: Int
        var ordered: Int?
        var text: String
    }

    private static func listItem(in line: String) -> ListMatch? {
        var indent = 0
        var consumed = 0
        for character in line {
            if character == " " {
                indent += 1
                consumed += 1
            } else if character == "\t" {
                indent += 2
                consumed += 1
            } else {
                break
            }
        }
        let rest = line.dropFirst(consumed)
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            return ListMatch(level: indent / 2, ordered: nil, text: String(rest.dropFirst(2)))
        }
        var index = rest.startIndex
        var digits = ""
        while index < rest.endIndex, rest[index].isNumber, digits.count < 6 {
            digits.append(rest[index])
            index = rest.index(after: index)
        }
        guard !digits.isEmpty, let number = Int(digits), index < rest.endIndex, rest[index] == "." else { return nil }
        let afterDot = rest.index(after: index)
        guard afterDot < rest.endIndex, rest[afterDot] == " " else { return nil }
        let textIndex = rest.index(after: afterDot)
        return ListMatch(level: indent / 2, ordered: number, text: String(rest[textIndex...]))
    }

    private static func isListContinuation(_ line: String) -> Bool {
        guard !isBlank(line), listItem(in: line) == nil, heading(in: line) == nil, fence(line) == nil else { return false }
        return line.first == " " || line.first == "\t"
    }

    private static func listMarker(for item: inout ListMatch) -> String {
        if item.text.hasPrefix("[ ] ") {
            item.text = String(item.text.dropFirst(4))
            return "☐"
        }
        if item.text.hasPrefix("[x] ") || item.text.hasPrefix("[X] ") {
            item.text = String(item.text.dropFirst(4))
            return "☑"
        }
        if let number = item.ordered {
            return "\(number)."
        }
        return "•"
    }

    private static func parseInlines(_ source: String) -> [MarkdownInline] {
        var scanner = InlineScanner(source: source)
        return scanner.parse()
    }
}

private struct InlineScanner {
    let source: String
    var index: String.Index

    init(source: String) {
        self.source = source
        index = source.startIndex
    }

    mutating func parse(until stop: String? = nil) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        var buffer = ""
        func flush() {
            if !buffer.isEmpty {
                result.append(.text(buffer))
                buffer = ""
            }
        }

        while index < source.endIndex {
            if let stop, source[index...].hasPrefix(stop) {
                break
            }
            let character = source[index]
            if character == "\\" {
                let next = source.index(after: index)
                if next < source.endIndex {
                    buffer.append(source[next])
                    index = source.index(after: next)
                    continue
                }
            }
            if character == "`", let code = consumeCode() {
                flush()
                result.append(.code(code))
                continue
            }
            if source[index...].hasPrefix("~~"), let inner = consumeWrapped("~~") {
                flush()
                result.append(.strike(inner))
                continue
            }
            if source[index...].hasPrefix("**"), let inner = consumeWrapped("**") {
                flush()
                result.append(.strong(inner))
                continue
            }
            if source[index...].hasPrefix("__"), let inner = consumeWrapped("__") {
                flush()
                result.append(.strong(inner))
                continue
            }
            if character == "*", let inner = consumeWrapped("*") {
                flush()
                result.append(.emphasis(inner))
                continue
            }
            if character == "_", canStartUnderscore, let inner = consumeWrapped("_") {
                flush()
                result.append(.emphasis(inner))
                continue
            }
            if character == "!", source[index...].hasPrefix("!["), let link = consumeLink(image: true) {
                flush()
                result.append(contentsOf: link.label)
                continue
            }
            if character == "[", let link = consumeLink(image: false) {
                flush()
                result.append(.link(link.label, link.url))
                continue
            }
            buffer.append(character)
            index = source.index(after: index)
        }
        flush()
        return result
    }

    private var canStartUnderscore: Bool {
        guard index > source.startIndex else { return true }
        let previous = source[source.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    private mutating func consumeCode() -> String? {
        let start = index
        var ticks = 0
        var cursor = index
        while cursor < source.endIndex, source[cursor] == "`" {
            ticks += 1
            cursor = source.index(after: cursor)
        }
        guard ticks > 0 else { return nil }
        let marker = String(repeating: "`", count: ticks)
        var scan = cursor
        while scan < source.endIndex {
            if source[scan...].hasPrefix(marker) {
                let code = String(source[cursor..<scan])
                index = source.index(scan, offsetBy: ticks)
                return code
            }
            scan = source.index(after: scan)
        }
        index = start
        return nil
    }

    private mutating func consumeWrapped(_ marker: String) -> [MarkdownInline]? {
        guard source[index...].hasPrefix(marker) else { return nil }
        let start = index
        let contentStart = source.index(index, offsetBy: marker.count)
        var scan = contentStart
        while scan < source.endIndex {
            if source[scan] == "\\" {
                let next = source.index(after: scan)
                scan = next < source.endIndex ? source.index(after: next) : next
                continue
            }
            if source[scan...].hasPrefix(marker) {
                let innerSource = String(source[contentStart..<scan])
                var inner = InlineScanner(source: innerSource)
                let parsed = inner.parse()
                index = source.index(scan, offsetBy: marker.count)
                return parsed
            }
            scan = source.index(after: scan)
        }
        index = start
        return nil
    }

    private mutating func consumeLink(image: Bool) -> (label: [MarkdownInline], url: URL?)? {
        let start = index
        if image {
            guard source[index...].hasPrefix("![") else { return nil }
            index = source.index(index, offsetBy: 2)
        } else {
            guard source[index] == "[" else { return nil }
            index = source.index(after: index)
        }
        let labelStart = index
        var scan = index
        while scan < source.endIndex, source[scan] != "]" {
            if source[scan] == "\\" {
                let next = source.index(after: scan)
                scan = next < source.endIndex ? source.index(after: next) : next
                continue
            }
            scan = source.index(after: scan)
        }
        guard scan < source.endIndex, source[scan] == "]" else {
            index = start
            return nil
        }
        let paren = source.index(after: scan)
        guard paren < source.endIndex, source[paren] == "(" else {
            index = start
            return nil
        }
        var urlEnd = source.index(after: paren)
        while urlEnd < source.endIndex, source[urlEnd] != ")" {
            urlEnd = source.index(after: urlEnd)
        }
        guard urlEnd < source.endIndex else {
            index = start
            return nil
        }
        let labelSource = String(source[labelStart..<scan])
        var labelParser = InlineScanner(source: labelSource)
        let label = labelParser.parse()
        let rawURL = String(source[source.index(after: paren)..<urlEnd]).trimmingCharacters(in: .whitespaces)
        index = source.index(after: urlEnd)
        return (label, safeURL(rawURL))
    }

    private func safeURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" || scheme == "mailto" else { return nil }
        return url
    }
}
