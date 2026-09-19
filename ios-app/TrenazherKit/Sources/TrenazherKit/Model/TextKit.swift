import Foundation

/// Нормализация текста для сравнения названий: регистр, «ё», пунктуация и лишние пробелы не важны.
public enum TextNormalizer {
    private static let alphanumerics = CharacterSet.alphanumerics

    /// Ключ сравнения: «Медвежья планка в динамике.» → «медвежья планка в динамике».
    public static func key(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        var scalars = String.UnicodeScalarView()
        for scalar in lowered.unicodeScalars {
            scalars.append(alphanumerics.contains(scalar) ? scalar : Unicode.Scalar(UInt8(32)))
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    public static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Пустая строка → nil.
    public static func nonEmpty(_ text: String) -> String? {
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }

    /// Название для показа: без пробелов и точки в конце («Медвежья планка в динамике.»).
    public static func displayName(_ text: String) -> String {
        var value = trimmed(text)
        while value.hasSuffix(".") { value.removeLast() }
        return trimmed(value)
    }

    /// Текст описания: убираем пробелы по краям и схлопываем 3+ переноса строки в пустую строку.
    public static func paragraphText(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }
}

/// Детерминированный короткий хеш (FNV-1a 64) — для версий и имён файлов.
/// `hashValue` в Swift меняется между запусками, поэтому свой.
public enum StableHash {
    public static func hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    public static func hex(_ parts: [String]) -> String {
        hex(parts.joined(separator: "\u{1F}"))
    }
}

/// Склонения для русских подписей: 1 упражнение, 2 упражнения, 5 упражнений.
public enum RussianPlural {
    public static func form(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n = abs(count) % 100
        let n1 = n % 10
        if n > 10 && n < 20 { return many }
        if n1 > 1 && n1 < 5 { return few }
        if n1 == 1 { return one }
        return many
    }

    public static func exercises(_ count: Int) -> String {
        "\(count) \(form(count, "упражнение", "упражнения", "упражнений"))"
    }

    public static func workouts(_ count: Int) -> String {
        "\(count) \(form(count, "тренировка", "тренировки", "тренировок"))"
    }

    public static func minutes(_ count: Int) -> String {
        "\(count) \(form(count, "минута", "минуты", "минут"))"
    }
}
