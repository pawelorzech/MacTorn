import Foundation

extension CharacterSet {
    /// Everything that ends a line, not just what Unicode files under "control".
    ///
    /// `CharacterSet.controlCharacters` is categories Cc and Cf only, which leaves
    /// U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR (categories Zl and Zp)
    /// untouched — and CoreText renders both as hard line breaks. A forum thread title of
    /// `Re: raid\u{2028}\u{2028}MacTorn: your key expired, re-enter it at …` would otherwise
    /// produce a two-paragraph notification whose second half reads as if MacTorn wrote it.
    /// `.newlines` covers LF, CR, NEL, LS and PS.
    static let lineBreaking = CharacterSet.controlCharacters.union(.newlines)
}

extension String {
    /// Strips Unicode control *and* format characters plus line breaks, and caps the length.
    ///
    /// `CharacterSet.controlCharacters` covers categories Cc and Cf, so this removes bidi
    /// overrides (U+202A–202E, U+2066–2069) and zero-width characters along with the usual
    /// C0/C1 controls — the pieces used to build text that reads as something other than
    /// what it is, on screen or through VoiceOver. It is *not* enough on its own: U+2028
    /// LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR are categories Zl/Zp and still render
    /// as hard line breaks, which is how a forum title can fake a second MacTorn-authored
    /// paragraph. `CharacterSet.lineBreaking` closes that hole.
    ///
    /// Apply to every string reaching the UI from a source we do not control: Torn's own
    /// error messages, and event text that another player can influence.
    func sanitizedForDisplay(limit: Int = 120) -> String {
        let stripped = unicodeScalars
            .filter { !CharacterSet.lineBreaking.contains($0) || $0 == .emojiJoiner }
            .map(Character.init)
        // `prefix(_:)` has a precondition of maxLength >= 0 and traps below it. No caller
        // passes a negative today — the three are 80, 200 and the 120 default — but this is
        // a shared helper on String now, so a future caller computing a limit gets an empty
        // string rather than a crash.
        return String(String(stripped).prefix(max(0, limit)))
    }
}

extension Unicode.Scalar {
    /// U+200D ZERO WIDTH JOINER.
    ///
    /// It is category Cf, so `CharacterSet.controlCharacters` matches it — but it is also
    /// the glue in every emoji ZWJ sequence, and dropping it decomposes one grapheme into
    /// several: 👨‍👩‍👧 becomes three separate people, 🏳️‍🌈 becomes a white flag beside a
    /// rainbow. That is visible corruption of legitimate content.
    ///
    /// Keeping it is a deliberately narrow exception. ZWJ only asks that adjacent glyphs be
    /// joined: unlike the bidi overrides it cannot reorder text, and unlike U+200B ZERO
    /// WIDTH SPACE — which stays stripped — it is not the character used to split a word
    /// invisibly. Variation selectors (U+FE0F) and the keycap mark (U+20E3) need no
    /// exception; they are in neither Cc nor Cf and were never removed.
    static let emojiJoiner = Unicode.Scalar(0x200D)!
}
