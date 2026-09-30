---
title: Invalid paste bytes and joined grapheme width
type: bug
date: 2026-09-30
status: resolved
---

# Invalid paste bytes and joined grapheme width

The RC1 boundary tests found two faults with generation seed `30092026`.
Fixed small cases now live in `test/fuzz/terminal_regressions_test.exs`.

## Malformed bracketed paste

Corpus mutation case 36 inserted byte `193` before `界` in a complete paste.
`EscapeParser` passed the invalid binary to `Input.paste`, which raised an
`ArgumentError`. The normalized-input API correctly requires valid UTF-8;
the terminal parser failed to apply its malformed-byte policy to paste.

The parser now collects the complete paste before discarding malformed bytes.
Valid Unicode, embedded escape sequences, and bytes after the end marker stay
present. The same conversion applies to the oversized incomplete-paste path.
The conversion uses tail recursion over contiguous valid chunks, so an 8 MiB
valid paste does not require one allocation per code point or repeated binary
copies. The existing oversized-paste regression remains part of validation.

## Joined grapheme width

Frame case 2 combined joined emoji with later edits. `DisplayWidth.width`
added the widths of every code point in an emoji cluster. For `👩‍💻`, it returned
four columns, while `Cell` stored one two-column primary cell and a tail.
Text fitting and cursor layout therefore disagreed with the frame model.

Display width now sums grapheme widths, each bounded to two columns. This
matches the existing terminal-cell contract. Regressions cover joined emoji,
skin tones, composed Hangul, trailing text, fitting, and frame row output.
This is the library's cell model, not a promise that every frontend renders
every grapheme the same way.

## Evidence

The generated checks compare chunked and complete parsing, validate arbitrary
bounded byte input, preserve wide-cell ownership after edits and overlays,
reconstruct frames from diffs and browser deltas, and test protocol boundaries.
Failures report a seed, case number, and bounded input. See
[the testing guide](../../guides/testing.md) for replay commands.
