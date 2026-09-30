# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TermUI is a small Elm-style terminal runtime for Elixir and the BEAM.

## Target Architecture

The runtime has three clear boundaries:

1. **Application** - One runtime process owns application state and serializes updates.
2. **Frame** - Pure views return one canonical `TermUI.Frame`.
3. **Backend** - One backend owner serializes input, output, size, capabilities, and cleanup.

### Key Design Decisions

- **OTP 28+ only** - Uses native raw mode via `shell.start_interactive({:noshell, :raw})`
- **Pure widgets** with state owned by the parent application
- **Coalesced frame scheduling** with one final meaningful render
- **One normalized event model** for keys, text, paste, mouse, resize, and focus
- **Data commands** for messages, timers, asynchronous work, and shutdown

### Platform Targets

- Elixir 1.15+, OTP 28+
- Linux, macOS, Windows 10+
- Major terminals: Alacritty, Kitty, WezTerm, iTerm2, GNOME Terminal, Windows Terminal

## Project Status

The `1.0.0-rc` design is implemented. Files under `notes/` are historical research and are not current architecture guidance.

## Development Notes

Follow these patterns:

- Keep application and widget transitions pure.
- Keep terminal implementation logic in backends.
- Return `TermUI.Frame` directly from application views.
- Keep backend callback state under one serialized owner.
- Use `TermUI.Command` values for effects.
- Preserve graceful degradation for terminal features.
- IMPORTANT you must NEVER mention Claude or any AI assistant in your commit messages!
