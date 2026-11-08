//
//  SoundsLike.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import Foundation

/// Turns a pt-BR "sounds like" spelling ("vóquis", "liéti") into X-SAMPA with fixed rules,
/// for `CustomVocabulary`. An accented vowel marks the stress (`"` before it); there's no
/// syllabification, so unaccented words get no stress mark.
nonisolated enum SoundsLike {
    private static let stressed: [Character: String] = ["á": "a", "é": "E", "í": "i", "ó": "O", "ú": "u", "â": "6", "ê": "e", "ô": "o"]
    private static let plain: Set<Character> = ["a", "e", "i", "o", "u"]
    private static let vowels: Set<Character> = Set("aeiouáéíóúâêô")
    /// Vowels that make a following "c" soft and "qu"/"gu" lose the "u".
    private static let frontVowels: Set<Character> = Set("eiéíê")
    private static let vowelPhonemes: Set<String> = ["a", "E", "e", "i", "O", "o", "u", "6"]
    private static let consonants: Set<Character> = Set("bdfgjklmnpqtvz")

    /// Comma-separated spellings ("vóks, vóquis"), one pronunciation each, in order.
    static func pronunciations(_ spellings: String) -> [String] {
        spellings.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(xsampa)
            .filter { !$0.isEmpty }
    }

    /// Phonemes separated by spaces, e.g. "vóquis" → `v "O k i s`.
    static func xsampa(_ spelling: String) -> String {
        let w = Array(spelling.precomposedStringWithCanonicalMapping.lowercased())
        let stressedSeen = w.contains { stressed[$0] != nil }
        var out: [String] = []
        var i = 0
        while i < w.count {
            let c = w[i]
            let next: Character? = i + 1 < w.count ? w[i + 1] : nil
            let last = i == w.count - 1
            // Like the prototype, a missing next letter counts as front vowel / non-vowel.
            let nextIsFront = next.map { frontVowels.contains($0) } ?? true
            let nextIsVowel = next.map { vowels.contains($0) } ?? false

            switch (c, next) {
            case ("c", "h"): out.append("S"); i += 2; continue
            case ("l", "h"): out.append("L"); i += 2; continue
            case ("n", "h"): out.append("J"); i += 2; continue
            case ("r", "r"): out.append("x"); i += 2; continue
            case ("q", "u"), ("g", "u"):
                if i + 2 < w.count, frontVowels.contains(w[i + 2]) {
                    out.append(c == "q" ? "k" : "g"); i += 2; continue
                }
            default: break
            }

            if c == "c" { out.append(nextIsFront ? "s" : "k"); i += 1; continue }
            if c == "ç" { out.append("s"); i += 1; continue }
            if c == "t" || c == "d", let next, next == "i" || next == "í" {
                out.append(c == "t" ? "tS" : "dZ"); i += 1; continue
            }
            if c == "s" {
                let between = i > 0 && vowels.contains(w[i - 1]) && nextIsVowel
                out.append(between ? "z" : "s"); i += 1; continue
            }
            if c == "x" { out.append("S"); i += 1; continue }
            if c == "r" { out.append(i == 0 || last ? "x" : "4"); i += 1; continue }
            if c == "l", last || !nextIsVowel, i > 0 { out.append("w"); i += 1; continue }
            if c == "h" { i += 1; continue }
            if let vowel = stressed[c] { out.append("\"" + vowel); i += 1; continue }
            if plain.contains(c) {
                var v = String(c)
                if last && c == "e" { v = "i" }
                else if last && c == "o" { v = "u" }
                else if last && c == "a" && stressedSeen { v = "6" }
                // Unstressed "i"/"u" next to another vowel become glides.
                let previousIsVowel = out.last.map { vowelPhonemes.contains(String($0.drop(while: { $0 == "\"" }))) } ?? false
                let nextIsFullVowel = next.map { vowels.contains($0) && $0 != "i" && $0 != "u" } ?? false
                if (c == "i" || c == "u") && (previousIsVowel || nextIsFullVowel) {
                    v = c == "i" ? "j" : "w"
                }
                out.append(v); i += 1; continue
            }
            if consonants.contains(c) {
                out.append(c == "j" ? "Z" : c == "q" ? "k" : String(c)); i += 1; continue
            }
            i += 1
        }
        return out.joined(separator: " ")
    }
}
