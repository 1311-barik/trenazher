import Foundation

/// CSV по RFC 4180 (так выгружает Google Sheets): поля в кавычках, переносы строк внутри ячеек, "" внутри кавычек.
public enum CSVParser {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func nextChar() -> Character? {
            if let char = pending {
                pending = nil
                return char
            }
            return iterator.next()
        }

        while let char = nextChar() {
            if inQuotes {
                if char == "\"" {
                    if let following = nextChar() {
                        if following == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\r\n", "\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
