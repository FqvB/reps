// Minimal RFC 4180 reader: commas, double-quoted fields, "" escapes, \n or \r\n rows.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // Rows as dictionaries keyed by the header row. Blank lines are dropped.
    static func records(_ text: String) -> [[String: String]] {
        let rows = parse(text).filter { $0 != [""] }
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { row in
            var record: [String: String] = [:]
            for (index, key) in header.enumerated() {
                record[key] = index < row.count ? row[index] : ""
            }
            return record
        }
    }
}
