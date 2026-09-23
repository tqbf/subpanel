import Foundation

/// Renders the small Markdown subset Subpanel's own documents use, so
/// browsers get a readable page while agents get the Markdown source.
///
/// Supported: `#`–`###` headings, paragraphs, `-` lists, numbered lists
/// (with their starting number), fenced code blocks, `>` blockquotes, and
/// inline `code`, `**bold**`, `[links](url)` and bare http(s) URLs. That is
/// all the instructions use; this is not a general Markdown engine.
public enum MarkdownHTML {
    public static func render(_ markdown: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var list: (ordered: Bool, start: Int, items: [String])?
        var quote: [String] = []
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty {
                html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
                paragraph = []
            }
        }
        func flushList() {
            guard let current = list else { return }
            let items = current.items.map { "<li>\(inline($0))</li>" }.joined()
            if current.ordered {
                let start = current.start == 1 ? "" : " start=\"\(current.start)\""
                html.append("<ol\(start)>\(items)</ol>")
            } else {
                html.append("<ul>\(items)</ul>")
            }
            list = nil
        }
        func flushQuote() {
            if !quote.isEmpty {
                html.append("<blockquote><p>\(inline(quote.joined(separator: " ")))</p></blockquote>")
                quote = []
            }
        }
        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        for line in markdown.components(separatedBy: "\n") {
            if var lines = code {
                if line.hasPrefix("```") {
                    html.append("<pre><code>\(escape(lines.joined(separator: "\n")))</code></pre>")
                    code = nil
                } else {
                    lines.append(line)
                    code = lines
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushAll()
                code = []
            } else if trimmed.isEmpty {
                flushAll()
            } else if let (level, text) = heading(trimmed) {
                flushAll()
                html.append("<h\(level)>\(inline(text))</h\(level)>")
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                flushList()
                quote.append(String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("- ") {
                flushParagraph()
                flushQuote()
                if list?.ordered == true { flushList() }
                list = (false, 1, (list?.items ?? []) + [String(trimmed.dropFirst(2))])
            } else if let (number, text) = orderedItem(trimmed) {
                flushParagraph()
                flushQuote()
                if list?.ordered == false { flushList() }
                list = (true, list?.start ?? number, (list?.items ?? []) + [text])
            } else if var current = list, line.hasPrefix("  ") {
                current.items[current.items.count - 1] += " " + trimmed
                list = current
            } else {
                flushList()
                flushQuote()
                paragraph.append(trimmed)
            }
        }
        if let lines = code {
            html.append("<pre><code>\(escape(lines.joined(separator: "\n")))</code></pre>")
        }
        flushAll()
        return html.joined(separator: "\n")
    }

    /// Escapes text for HTML element content and attribute values.
    public static func escape(_ text: some StringProtocol) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    private static func heading(_ line: String) -> (Int, String)? {
        for level in 1...3 where line.hasPrefix(String(repeating: "#", count: level) + " ") {
            return (level, String(line.dropFirst(level + 1)))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> (Int, String)? {
        guard let dot = line.firstIndex(of: "."),
              let number = Int(line[..<dot]),
              line[line.index(after: dot)...].hasPrefix(" ")
        else { return nil }
        return (number, String(line[line.index(dot, offsetBy: 2)...]))
    }

    /// Inline spans, scanned left to right so code spans and link targets are
    /// never re-processed.
    static func inline(_ text: String) -> String {
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("`"),
               let close = text[text.index(after: index)...].firstIndex(of: "`") {
                out += "<code>\(escape(text[text.index(after: index)..<close]))</code>"
                index = text.index(after: close)
            } else if rest.hasPrefix("**"),
                      let close = text[text.index(index, offsetBy: 2)...].range(of: "**") {
                out += "<strong>\(inline(String(text[text.index(index, offsetBy: 2)..<close.lowerBound])))</strong>"
                index = close.upperBound
            } else if rest.hasPrefix("["),
                      let middle = rest.range(of: "]("),
                      !text[index..<middle.lowerBound].contains("\n"),
                      let close = text[middle.upperBound...].firstIndex(of: ")") {
                let label = String(text[text.index(after: index)..<middle.lowerBound])
                let href = text[middle.upperBound..<close]
                out += "<a href=\"\(escape(href))\">\(inline(label))</a>"
                index = text.index(after: close)
            } else if rest.hasPrefix("http://") || rest.hasPrefix("https://") {
                var end = rest.firstIndex { $0.isWhitespace || "<>\"'`)".contains($0) } ?? text.endIndex
                while end > index, ".,;:".contains(text[text.index(before: end)]) {
                    end = text.index(before: end)
                }
                let url = text[index..<end]
                out += "<a href=\"\(escape(url))\">\(escape(url))</a>"
                index = end
            } else {
                out += escape(String(text[index]))
                index = text.index(after: index)
            }
        }
        return out
    }
}
