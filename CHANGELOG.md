# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-08-28

TermUI 1.0 establishes the pre-rewrite architecture as the stable release line,
including the Raw, TTY, and SSH backends, the Elm-style runtime, differential
rendering, constraint-based layouts, and the complete widget set.

### Added

- SSH backend support for remote terminal sessions.
- Bracketed-paste parsing into dedicated paste events.
- Root startup commands and table refresh APIs.
- Cross-platform terminal testing checklists.

### Changed

- Improved raw terminal output, resilience, and cleanup.
- Moved input polling outside the runtime process.
- Added terminal-output run coalescing and linear-time buffer diffing.
- Improved Markdown rendering and example consistency.
- Upgraded MDEx to a security-maintained release and removed an unused
  development dependency that pinned vulnerable HTTP client packages.
- Added dependency-vulnerability auditing to release CI.

### Fixed

- Constraint tuples in horizontal and vertical stacks now allocate and clip
  children as documented.
- macOS Option+Delete no longer stalls the escape-sequence buffer and performs
  word deletion in text inputs.
- Concurrent SSH runtimes now use isolated render buffers and avoid mutating
  local terminal global state.
- Terminal resize rendering and shutdown races.
- ANSI style restoration after reset operations.
- WSL/ConPTY and IEx terminal cleanup behavior.
- Shift+Tab parsing across CSI variants.
- Background-color bleeding and overlay rendering artifacts.
- Elixir 1.18 regular-expression compilation.
- Safe `stty` execution when no controlling terminal is available.
- Explicit Raw runtimes now activate OS-level raw flags and restore the exact
  saved terminal settings on exit.
- On supported OTP releases, Unix runtimes now receive real `SIGWINCH` resize
  notifications and restore the cursor and alternate screen synchronously
  before `SIGTERM` shutdown.
- Pre-OTP 28 systems now stay on the TTY/`stty` path instead of invoking the
  OTP 28 native raw/cooked shell-mode contract.
- Order-dependent tests, singleton cache lifecycles, documentation links, and
  static-analysis contracts required for a reproducible release build.

### Known limitations

- Native Windows console support is experimental. TermUI 1.0 does not configure
  Win32 console modes or implement native raw input and resize handling; use WSL
  where practical and validate the chosen terminal environment.
- Mouse tracking is disabled under WSL/ConPTY because the required disable
  sequences are not handled reliably; keyboard, resize, paste, and cleanup
  remain supported through the Unix backend.
- OTP 26 TTY applications can query terminal dimensions, but its signal API
  does not provide automatic `SIGWINCH` resize notifications.
- A resume or external terminal redraw may require `TermUI.Runtime.force_render/1`.

## [0.2.0] - 2024-12-01

### Added

- **New Widgets**
  - PickList - Modal selection list for choosing items from a scrollable list
  - FormBuilder - Structured form handling with validation and field management
  - CommandPalette - VS Code-style searchable command discovery interface
  - TreeView - Hierarchical data display with expand/collapse navigation
  - SplitPane - Resizable multi-pane layouts with draggable dividers
  - LogViewer - Real-time log display with filtering and scrolling
  - StreamWidget - Bounded stream display with a GenStage consumer adapter
  - ProcessMonitor - BEAM process introspection and monitoring
  - SupervisionTreeViewer - OTP supervision hierarchy visualization
  - ClusterDashboard - Distributed cluster node visualization and monitoring
  - TextInput - Single-line and multi-line text input with cursor navigation

- **Backend Abstraction**
  - Backend behaviour for terminal abstraction
  - Raw backend for full terminal control
  - TTY backend for line-based terminals
  - Test renderers and component testing helpers
  - Automatic backend selection based on terminal capabilities
  - Character set selection (Unicode/ASCII) with graceful degradation

- **Rendering**
  - Overlay node support in NodeRenderer for absolute-positioned widgets (AlertDialog, Dialog, ContextMenu, Toast)

- **Documentation**
  - Advanced widgets user guide
  - Updated widget examples with run.exs entry points

## [0.1.0] - 2024-11-26

### Added

- Initial release
- **Core Framework**
  - Elm Architecture implementation (`use TermUI.Elm`)
  - Runtime with 60 FPS rendering loop
  - Event system for keyboard and mouse input
  - Command system for side effects

- **Rendering Engine**
  - ETS-based double buffering
  - Differential rendering (only changed cells are updated)
  - ANSI escape sequence batching
  - Style system with colors and attributes

- **Layout System**
  - Constraint-based layout solver
  - Flexbox-style alignment
  - Stack layouts (vertical/horizontal)

- **Widgets**
  - Gauge (bar and arc styles with color zones)
  - Sparkline (trend visualization)
  - BarChart (horizontal/vertical)
  - LineChart (Braille-based)
  - Table (with selection and scrolling)
  - Menu (hierarchical with submenus)
  - Tabs (tabbed interface)
  - Dialog (modal dialogs)
  - Viewport (scrollable content)
  - Canvas (custom drawing)
  - Toast (notifications)
  - ScrollBar
  - ContextMenu
  - AlertDialog

- **Terminal Support**
  - Raw mode activation
  - Unix terminal support plus initial Windows VT capability scaffolding
  - Terminal capability detection
  - Color degradation (true color → 256 → 16)

- **Developer Experience**
  - Development mode with hot reload
  - Performance monitoring
  - Testing framework
  - Comprehensive documentation

### Documentation

- User guides (overview, getting started, architecture, events, styling, layout, widgets)
- Developer guides (architecture, runtime, rendering, events, buffers, terminal, creating widgets)
- Widget examples with READMEs

[Unreleased]: https://github.com/pcharbon70/term_ui/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/pcharbon70/term_ui/compare/v1.0.0-rc...v1.0.0
[0.2.0]: https://github.com/pcharbon70/term_ui/tree/v0.2.0
[0.1.0]: https://hex.pm/packages/term_ui/0.1.0
