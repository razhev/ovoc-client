import Foundation

/// Нормализация того, что человек реально вставляет в поле импорта: ключ редко
/// приходит «чистой строкой». Его пересылают внутри сообщения («вот ключ: vpn://…
/// спасибо»), мессенджеры и почта рвут длинную строку переносами, при копировании
/// цепляются невидимые символы.
///
/// Живёт в ConfigKit, а не в приложении: у приложения нет тестового таргета,
/// а эта логика проверяется на Mac (`make test`).
public enum VPNKeyText {
    static let prefix = "vpn://"

    /// Сколько раз пробуем отбросить хвостовой фрагмент (см. `candidates`).
    private static let maxDroppedChunks = 16

    /// Варианты ключа, найденные в тексте, от самого длинного к самому короткому.
    /// Пустой массив — в тексте нет `vpn://`.
    ///
    /// Тело ключа — base64url; после префикса собираем фрагменты из символов
    /// этого алфавита, разделённые пробелами/переносами (так выглядит ключ,
    /// разорванный мессенджером), до первого постороннего символа. Беда в том,
    /// что латинское слово после ключа («… thanks») неотличимо от его продолжения,
    /// поэтому кандидатов несколько: все фрагменты, затем без последнего и т.д.
    /// Кто из них настоящий, решает декодер — zlib и JSON внутри ключа служат
    /// надёжной проверкой.
    public static func candidates(in text: String) -> [String] {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { !isInvisible($0) }))

        guard let start = cleaned.range(of: prefix, options: .caseInsensitive) else { return [] }
        var body = cleaned[start.upperBound...]
        // Два ключа подряд — берём первый.
        if let next = body.range(of: prefix, options: .caseInsensitive) {
            body = body[..<next.lowerBound]
        }

        var chunks: [Substring] = []
        var chunkStart: Substring.Index?
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if isBase64URL(character) {
                if chunkStart == nil { chunkStart = index }
            } else if character.isWhitespace {
                if let begin = chunkStart { chunks.append(body[begin..<index]); chunkStart = nil }
            } else {
                break   // кавычка, точка, кириллица — ключ закончился
            }
            index = body.index(after: index)
        }
        if let begin = chunkStart { chunks.append(body[begin..<index]) }
        guard !chunks.isEmpty else { return [] }

        let shortest = max(1, chunks.count - maxDroppedChunks)
        return stride(from: chunks.count, through: shortest, by: -1).map { count in
            prefix + chunks[..<count].joined()
        }
    }

    /// base64url и обычный base64 (декодер принимает оба алфавита).
    static func isBase64URL(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || "-_+/=".contains(character)
    }

    /// Символы форматирования без ширины: zero-width space/joiner, BOM, мягкий
    /// перенос, метки направления письма. Глазом не видны, а base64 ломают.
    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format
    }
}
