import Foundation

extension CharacterSet {
    /// Everything that ends a line. `CharacterSet.controlCharacters` (Cc, Cf) leaves U+2028 and
    /// U+2029 (Zl, Zp) alone, and CoreText renders both as hard line breaks, so a forum title could
    /// fake a second MacTorn-authored paragraph in a notification. `.newlines` covers LF, CR, NEL, LS, PS.
    static let lineBreaking = CharacterSet.controlCharacters.union(.newlines)
}

extension String {
    /// Strips Unicode control and format characters plus line breaks, and caps the length.
    ///
    /// Removes bidi overrides (U+202A–202E, U+2066–2069) and zero-width characters, which make text
    /// read as something other than what it is, on screen or through VoiceOver. Apply to every string
    /// reaching the UI from a source we do not control: Torn's own error messages, and event text
    /// that another player can influence.
    func sanitizedForDisplay(limit: Int = 120) -> String {
        // `prefix(_:)` traps on a negative length; clamp so a computed limit cannot crash.
        let clampedLimit = max(0, limit)
        guard clampedLimit > 0, !isEmpty else { return "" }

        let scalars = unicodeScalars
        var firstDisallowed: String.UnicodeScalarView.Index?
        var idx = scalars.startIndex
        while idx < scalars.endIndex {
            let s = scalars[idx]
            // Printable ASCII (0x20...0x7E) is never in `CharacterSet.lineBreaking`.
            if s.value < 0x20 || s.value >= 0x7F {
                if CharacterSet.lineBreaking.contains(s) && s != .emojiJoiner {
                    firstDisallowed = idx
                    break
                }
            }
            idx = scalars.index(after: idx)
        }

        // Fast path: string contains no disallowed scalars. UTF-8 byte count >= Character count,
        // so `utf8.count <= clampedLimit` guarantees the length cap without counting graphemes.
        guard let badIndex = firstDisallowed else {
            return utf8.count <= clampedLimit ? self : String(prefix(clampedLimit))
        }

        var kept = String.UnicodeScalarView()
        kept.reserveCapacity(scalars.count)
        kept.append(contentsOf: scalars[..<badIndex])
        var cur = scalars.index(after: badIndex)
        while cur < scalars.endIndex {
            let s = scalars[cur]
            if (s.value >= 0x20 && s.value < 0x7F)
                || !CharacterSet.lineBreaking.contains(s)
                || s == .emojiJoiner {
                kept.append(s)
            }
            cur = scalars.index(after: cur)
        }
        let cleaned = String(kept)
        return cleaned.utf8.count <= clampedLimit ? cleaned : String(cleaned.prefix(clampedLimit))
    }
}

extension Unicode.Scalar {
    /// U+200D ZERO WIDTH JOINER. Category Cf, but it is the glue in emoji ZWJ sequences: stripping it
    /// splits one grapheme (a family, a rainbow flag) into several. Kept as a deliberate exception: it
    /// cannot reorder text like the bidi overrides, and unlike U+200B ZERO WIDTH SPACE (still stripped)
    /// it is not used to split a word invisibly.
    static let emojiJoiner = Unicode.Scalar(0x200D)!
}
