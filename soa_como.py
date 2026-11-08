"""Protótipo: grafia "soa como" em pt-BR -> X-SAMPA, por regras fixas."""
import re, sys, unicodedata

STRESSED = {"á": "a", "é": "E", "í": "i", "ó": "O", "ú": "u", "â": "6", "ê": "e", "ô": "o"}
PLAIN = {"a": "a", "e": "e", "i": "i", "o": "o", "u": "u"}
VOWELS = set("aeiouáéíóúâêô")

def to_xsampa(word: str) -> str:
    w = word.lower()
    out, i = [], 0
    stressed_seen = any(c in STRESSED for c in w)
    while i < len(w):
        c, nxt = w[i], w[i + 1] if i + 1 < len(w) else ""
        two = w[i:i + 2]
        last = i == len(w) - 1
        if two in ("ch",): out.append("S"); i += 2; continue
        if two == "lh": out.append("L"); i += 2; continue
        if two == "nh": out.append("J"); i += 2; continue
        if two == "rr": out.append("x"); i += 2; continue
        if two in ("qu", "gu") and i + 2 < len(w) and w[i + 2] in "eiéíê":
            out.append("k" if c == "q" else "g"); i += 2; continue
        if c == "c": out.append("s" if nxt in "eiéíê" else "k"); i += 1; continue
        if c == "ç": out.append("s"); i += 1; continue
        if c in "td" and nxt and nxt in "ií": out.append("tS" if c == "t" else "dZ"); i += 1; continue
        if c == "s":
            between = i > 0 and w[i - 1] in VOWELS and nxt in VOWELS
            out.append("z" if between else "s"); i += 1; continue
        if c == "x": out.append("S"); i += 1; continue
        if c == "r":
            out.append("x" if i == 0 or last else "4"); i += 1; continue
        if c == "l" and (last or nxt not in VOWELS) and i > 0: out.append("w"); i += 1; continue
        if c == "h": i += 1; continue
        if c in STRESSED: out.append('"' + STRESSED[c]); i += 1; continue
        if c in PLAIN:
            v = PLAIN[c]
            if last and c == "e": v = "i"
            elif last and c == "o": v = "u"
            elif last and c == "a" and stressed_seen: v = "6"
            # "i"/"u" átonos junto de outra vogal viram semivogal
            prev_vowel = bool(out) and out[-1].lstrip('"') in {"a","E","e","i","O","o","u","6"}
            if c in "iu" and (prev_vowel or (nxt and nxt in VOWELS - set("iu"))):
                v = "j" if c == "i" else "w"
            out.append(v); i += 1; continue
        if c in "bdfgjklmnpqtvz": out.append({"j": "Z", "q": "k"}.get(c, c)); i += 1; continue
        i += 1
    return " ".join(out)

for arg in sys.argv[1:]:
    word, sounds = arg.split("=")
    for s in sounds.split(","):
        print(f"{word:7} {s.strip():8} -> {to_xsampa(s.strip())}")
