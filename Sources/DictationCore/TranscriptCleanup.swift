import Foundation

public enum TranscriptCleanup {
    // Deliberately narrow: only the reported full phrase at the very end.
    // Ignore case, spacing and punctuation, but never remove it mid-sentence
    // or blacklist ordinary words such as "канал" or "подписывайтесь".
    private static let promotionalTail = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])["«“„]?подписывайтесь[\s\p{P}]+на[\s\p{P}]+наш[\s\p{P}]+канал[\s\p{P}]+ставьте[\s\p{P}]+лайки[\s\p{P}]+(?:и[\s\p{P}]+)?подписывайтесь[\s\p{P}]+на[\s\p{P}]+наш[\s\p{P}]+канал[\s\p{P}]*\z"#,
        options: [.caseInsensitive]
    )

    public static func removingPromotionalTail(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let match = promotionalTail.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let range = Range(match.range, in: result) {
            result = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
