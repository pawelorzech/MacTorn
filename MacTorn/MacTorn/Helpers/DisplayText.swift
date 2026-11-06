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
        let stripped = unicodeScalars
            .filter { !CharacterSet.lineBreaking.contains($0) || $0 == .emojiJoiner }
            .map(Character.init)
        // `prefix(_:)` traps on a negative length; clamp so a computed limit cannot crash.
        return String(String(stripped).prefix(max(0, limit)))
    }
}

extension Unicode.Scalar {
    /// U+200D ZERO WIDTH JOINER. Category Cf, but it is the glue in emoji ZWJ sequences: stripping it
    /// splits one grapheme (a family, a rainbow flag) into several. Kept as a deliberate exception: it
    /// cannot reorder text like the bidi overrides, and unlike U+200B ZERO WIDTH SPACE (still stripped)
    /// it is not used to split a word invisibly.
    static let emojiJoiner = Unicode.Scalar(0x200D)!
}
