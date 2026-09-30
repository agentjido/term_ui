# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-09-30

This entry records the v2 source release preparation. Hex publication is
managed separately by the maintainer.

### Changed

- One Elm runtime owns application state, update order, command execution,
  and shutdown. Application views return one complete `TermUI.Frame`.
- Widgets are pure values. The parent owns their state, composes their
  frames, and turns widget messages into command data.
- Backend owners control input, output, terminal size, capabilities, and
  cleanup. Printable input uses `Event.Text`; named and modified keys use
  `Event.Key`.
- Elixir 1.18.4 and OTP 28 are the minimum supported versions.
- V2 changes target `main`. V1 fixes remain on `maint/1.x`. The public
  `TermUI` namespace and the Jido Console runtime contract remain supported.

### Added

- Complete isolated SSH sessions with bounded output, resize, timeout, and
  disconnect cleanup.
- A bounded web frame protocol, browser renderer, and optional web host.
- Optional Ghostty terminal sessions on the tested GNU Linux and macOS ARM
  platforms, with pure conversion from emulator output to TermUI frames.
- Pure input, table, tree, layout, stream, system-data, and feedback widgets.
- A migration guide, widget parity tables, runnable showcase, source NIF
  policy, and Oracle Linux release build instructions.

### Fixed

- Option+Delete word removal, continued Unicode input, terminal redraw,
  suspend and resume, color updates, and terminal and worker cleanup.
- Windows console input and resize in the tested Command Prompt and Git
  Bash ConPTY profiles. Physical Windows Terminal and Mintty checks remain
  open follow-up work.
- Live showcase process table identities use PIDs, so equal displayed
  process values do not stop the application.

### Migration

This is a breaking change from 1.x. Use [the migration guide](guides/migration-2.0.md)
and [widget parity table](guides/widget-parity.md) before changing an application.

## [1.0.0] - 2026-08-31

- Published the v1 runtime on Hex. Its existing `v1.0.0` tag is unchanged.
- Later repairs on `maint/1.x` are maintenance source changes and are not
  claimed as part of the published 1.0.0 package.

## [0.2.0] - 2024-12-01

### Added

- **New Widgets**
  - PickList - Modal selection list for choosing items from a scrollable list
  - FormBuilder - Structured form handling with validation and field management
  - CommandPalette - VS Code-style fuzzy-search command discovery interface
  - TreeView - Hierarchical data display with expand/collapse navigation
  - SplitPane - Resizable multi-pane layouts with draggable dividers
  - LogViewer - Real-time log display with filtering and scrolling
  - StreamWidget - Backpressure-aware data streaming with GenStage integration
  - ProcessMonitor - BEAM process introspection and monitoring
  - SupervisionTreeViewer - OTP supervision hierarchy visualization
  - ClusterDashboard - Distributed cluster node visualization and monitoring
  - TextInput - Single-line and multi-line text input with cursor navigation

- **Backend Abstraction**
  - Backend behaviour for terminal abstraction
  - Raw backend for full terminal control
  - TTY backend for line-based terminals
  - Test backend for unit testing
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
  - Cross-platform compatibility (Linux, macOS, Windows 10+)
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

[Unreleased]: https://github.com/agentjido/term_ui/compare/main...HEAD
[2.0.0]: https://github.com/agentjido/term_ui/compare/v1.0.0...main
[1.0.0]: https://github.com/agentjido/term_ui/releases/tag/v1.0.0
[0.2.0]: https://github.com/agentjido/term_ui/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/agentjido/term_ui/releases/tag/v0.1.0
