//
//  IssueID.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import Foundation

/// Finds an issue ID ("HGR-217") in transcribed speech without a language model, which tends to
/// mangle numbers and invent IDs. Handles what the pt-BR transcriber writes: "HGR-217", "HGR 217",
/// spelled letters ("agá gê erre") and numbers in words ("duzentos e dezessete"), in any mix.
/// Returns nil when there's no ID; it never guesses.
nonisolated enum IssueID {
    struct Match: Equatable {
        /// Canonical form, "HGR-217".
        let id: String
        /// Span of the spoken ID in the original text, to put the canonical form in its place.
        let range: Range<String.Index>
    }

    static func find(in text: String) -> Match? {
        let tokens = text.ranges(of: /[\p{L}\p{N}]+/).map { Token(text: String(text[$0]), range: $0) }

        for (index, token) in tokens.enumerated() {
            // Glued form the transcriber sometimes produces: "HGR217".
            if let glued = token.text.wholeMatch(of: /([A-Z]{2,})(\d+)/) {
                return Match(id: "\(glued.1)-\(glued.2)", range: token.range)
            }

            guard isNumberToken(token.text) else { continue }
            var letterEnd = index - 1
            if letterEnd >= 0, separatorWords.contains(tokens[letterEnd].text.lowercased()) {
                letterEnd -= 1
            }
            guard letterEnd >= 0, let (letters, letterStart) = letterRun(endingAt: letterEnd, in: tokens),
                  letters.count >= 2 else { continue }

            let numberTokens = numberRun(startingAt: index, in: tokens)
            guard let number = number(from: numberTokens.map(\.text)) else { continue }
            let range = tokens[letterStart].range.lowerBound..<numberTokens[numberTokens.count - 1].range.upperBound
            return Match(id: "\(letters)-\(number)", range: range)
        }
        return nil
    }

    private struct Token {
        let text: String
        let range: Range<String.Index>
    }

    // MARK: - Letters

    /// Letters spelled the pt-BR way. Names that are also common words ("de", "te", "que", "e",
    /// "o", "a") are left out, otherwise "o bug de agá gê erre" would become "OHGR" or "DHGR";
    /// those letters still work when the transcriber writes them as capitals ("D").
    private static let spelledLetters: [String: Character] = [
        "á": "A", "bê": "B", "be": "B", "cê": "C", "ce": "C", "dê": "D", "efe": "F", "éfe": "F",
        "gê": "G", "ge": "G", "guê": "G", "agá": "H", "aga": "H", "i": "I", "jota": "J", "jóta": "J",
        "cá": "K", "ka": "K", "ele": "L", "éle": "L", "eme": "M", "ême": "M", "ene": "N", "êne": "N",
        "ó": "O", "pê": "P", "pe": "P", "quê": "Q", "erre": "R", "érre": "R", "erri": "R",
        "esse": "S", "ésse": "S", "tê": "T", "u": "U", "vê": "V", "ve": "V",
        "dáblio": "W", "dablio": "W", "dábliu": "W", "dabliu": "W", "xis": "X",
        "ípsilon": "Y", "ipsilon": "Y", "zê": "Z", "ze": "Z",
    ]

    /// Spoken between prefix and number ("agá gê erre traço duzentos").
    private static let separatorWords: Set<String> = ["hífen", "hifen", "traço", "traco", "tracinho"]

    /// Letters of the run that ends at `end`, read backwards. An acronym ("HGR") is a whole
    /// prefix, so the run stops there instead of swallowing the word before it.
    private static func letterRun(endingAt end: Int, in tokens: [Token]) -> (String, Int)? {
        var letters = ""
        var start = end
        var index = end
        while index >= 0 {
            let word = tokens[index].text
            if word.wholeMatch(of: /[A-Z]{2,}/) != nil {
                letters = word + letters
                start = index
                break
            } else if word.wholeMatch(of: /[A-Z]/) != nil {
                letters = word + letters
            } else if let letter = spelledLetters[word.lowercased()] {
                letters = String(letter) + letters
            } else {
                break
            }
            start = index
            index -= 1
        }
        return letters.isEmpty ? nil : (letters, start)
    }

    // MARK: - Numbers

    private static let unitWords: [String: Int] = [
        "zero": 0, "um": 1, "uma": 1, "dois": 2, "duas": 2, "três": 3, "tres": 3, "quatro": 4,
        "cinco": 5, "seis": 6, "meia": 6, "sete": 7, "oito": 8, "nove": 9,
    ]

    private static let numberWords: [String: Int] = unitWords.merging([
        "dez": 10, "onze": 11, "doze": 12, "treze": 13, "catorze": 14, "quatorze": 14, "quinze": 15,
        "dezesseis": 16, "dezasseis": 16, "dezessete": 17, "dezassete": 17, "dezoito": 18,
        "dezenove": 19, "dezanove": 19,
        "vinte": 20, "trinta": 30, "quarenta": 40, "cinquenta": 50, "cinqüenta": 50, "sessenta": 60,
        "setenta": 70, "oitenta": 80, "noventa": 90,
        "cem": 100, "cento": 100, "duzentos": 200, "duzentas": 200, "trezentos": 300, "trezentas": 300,
        "quatrocentos": 400, "quatrocentas": 400, "quinhentos": 500, "quinhentas": 500,
        "seiscentos": 600, "seiscentas": 600, "setecentos": 700, "setecentas": 700,
        "oitocentos": 800, "oitocentas": 800, "novecentos": 900, "novecentas": 900,
        "mil": 1000,
    ]) { current, _ in current }

    private static func isNumberToken(_ word: String) -> Bool {
        word.wholeMatch(of: /\d+/) != nil || numberWords[word.lowercased()] != nil
    }

    /// Number words and digits from `start`, with "e" only between two of them, so the
    /// "e" in "duzentos e dezessete" joins but the one in "217 e depois" doesn't.
    private static func numberRun(startingAt start: Int, in tokens: [Token]) -> [Token] {
        var run: [Token] = []
        var index = start
        while index < tokens.count {
            let word = tokens[index].text
            if isNumberToken(word) {
                run.append(tokens[index])
            } else if word.lowercased() == "e", !run.isEmpty, index + 1 < tokens.count,
                      isNumberToken(tokens[index + 1].text) {
                // Connector; not part of the value.
            } else {
                break
            }
            index += 1
        }
        return run
    }

    /// "217", "2 1 7" and "dois um sete" are read digit by digit; anything else is added up
    /// in words ("duzentos e dezessete", "mil e vinte", "duzentos e 17").
    static func number(from words: [String]) -> String? {
        let lowered = words.map { $0.lowercased() }.filter { $0 != "e" }
        guard !lowered.isEmpty else { return nil }
        if lowered.allSatisfy({ $0.wholeMatch(of: /\d+/) != nil }) {
            return lowered.joined()
        }
        if lowered.count > 1, words.allSatisfy({ $0.lowercased() != "e" }),
           lowered.allSatisfy({ unitWords[$0] != nil }) {
            return lowered.compactMap { unitWords[$0].map(String.init) }.joined()
        }

        var total = 0
        var current = 0
        for word in lowered {
            if word == "mil" {
                total += max(current, 1) * 1000
                current = 0
            } else if let value = Int(word) ?? numberWords[word] {
                current += value
            } else {
                return nil
            }
        }
        return String(total + current)
    }
}
