#!/usr/bin/env python3
"""Extract localization keys from Swift sources into a Localizable.strings catalog.

Captures the FIRST string-literal argument of SwiftUI calls that take a
LocalizedStringKey (Text, Button, Label, .help, TextField, ...), NSLocalizedString
keys, and two-literal ternaries (cond ? "A" : "B"). Swift interpolations
`\\(...)` become `%@`, matching the key SwiftUI generates. Other escapes (\\n, \\")
are kept verbatim since .strings uses the same escape syntax.

Usage: extract_strings.py <out.strings> <file.swift>...
"""
import re
import sys

CALL_PATTERNS = [
    r'\bText\(', r'\bButton\(', r'\bLabel\(', r'\.help\(', r'\bTextField\(',
    r'\bToggle\(', r'\bSection\(', r'\bWindow\(', r'\.navigationTitle\(',
    r'\.confirmationDialog\(', r'\.alert\(', r'\bsection\(', r'\blabeled\(',
    r'\blabeledBlock\(', r'\bPicker\(', r'\bMenu\(', r'\bContentUnavailableCompat\(',
    r'\bmessage:\s*', r'\bNSLocalizedString\(', r'\bLink\(', r'\bDatePicker\(',
    r'\bStepper\(',
]
CALL_RE = re.compile('|'.join(CALL_PATTERNS))
# cond ? "A" : "B"  — both literals are keys.
TERNARY_RE = re.compile(r'\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')


def parse_literal(s, i):
    """s[i] == '"'. Return (key, end) with \\(...) -> %@ and other escapes kept."""
    assert s[i] == '"'
    i += 1
    out = []
    n = len(s)
    while i < n:
        c = s[i]
        if c == '\\':
            if i + 1 < n and s[i + 1] == '(':          # interpolation
                depth, i = 1, i + 2
                start = i
                while i < n and depth:
                    if s[i] == '(':
                        depth += 1
                    elif s[i] == ')':
                        depth -= 1
                    i += 1
                expr = s[start:i - 1]
                # SwiftUI keys Int interpolations as %lld; `.count` is the
                # only Int we interpolate. Everything else is a String (%@).
                out.append('%lld' if expr.strip().endswith('.count') else '%@')
                continue
            out.append(s[i:i + 2])                       # keep \n, \", \\ as-is
            i += 2
            continue
        if c == '"':
            return ''.join(out), i + 1
        out.append(c)
        i += 1
    return None, i


def sf_symbol_like(k):
    """SF Symbol names ("house.fill") show up in ternaries; they're not text."""
    return re.fullmatch(r'[a-z0-9.]+', k) is not None


def extract(text):
    keys = set()
    for m in CALL_RE.finditer(text):
        j = m.end()
        while j < len(text) and text[j] in ' \t\r\n':
            j += 1
        if j < len(text) and text[j] == '"':
            k, _ = parse_literal(text, j)
            if k:
                keys.add(k)
    for m in TERNARY_RE.finditer(text):
        for raw in m.groups():
            k, _ = parse_literal('"' + raw + '"', 0)
            if k and not sf_symbol_like(k) and '[[' not in k and k != '%@:':
                keys.add(k)
    return keys


def main():
    out, files = sys.argv[1], sys.argv[2:]
    keys = set()
    for f in files:
        with open(f, encoding='utf-8') as fh:
            keys |= extract(fh.read())
    keys = sorted(k for k in keys if k.strip())
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write(
            '/* Expandr — source-language (English) catalog.\n'
            '   Keys are the English strings used in code. To add a language, copy this\n'
            '   file to <lang>.lproj/Localizable.strings and translate the right-hand\n'
            '   values only. %@ is a placeholder filled in at runtime — keep it. */\n\n')
        for k in keys:
            fh.write(f'"{k}" = "{k}";\n')
    print(f'{len(keys)} keys -> {out}')


if __name__ == '__main__':
    main()
