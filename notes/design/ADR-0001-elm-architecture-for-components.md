# ADR-0001: Use The Elm Architecture for Component State Management

**Date:** 2024-11-24

**Status:** Accepted

---

## Context

TermUI needs a consistent pattern for managing component state and handling events. During development, two different patterns emerged in the codebase:

1. **StatefulComponent pattern** - Uses `use TermUI.StatefulComponent` with callbacks:
   - `init/1` - Initialize state
   - `handle_event/2` - Handle events directly
   - `render/1` - Render the component

2. **Elm Architecture pattern** - Uses `@behaviour TermUI.Elm` with callbacks:
   - `init/1` - Initialize state
   - `event_to_msg/2` - Convert events to messages
   - `update/2` - Update state based on messages
   - `view/1` - Render the component

The StatefulComponent pattern was used in early development (Phases 1-6), while the Elm Architecture pattern was introduced in Phase 7 for the Runtime system.

### Considerations

**Elm Architecture advantages:**
- Clear separation between event interpretation and state updates
- Messages are explicit, testable data structures
- Easier to reason about state transitions
- Better alignment with functional programming principles
- Proven pattern from Elm, adopted by BubbleTea (Go) and others
- Commands pattern for side effects fits naturally

**StatefulComponent advantages:**
- Simpler for basic components
- Fewer callbacks to implement
- Direct event handling can be more intuitive for simple cases

## Decision

**The Elm Architecture (`@behaviour TermUI.Elm`) is the standard pattern for TermUI components.**

All new components should implement:
- `init/1` - Return initial state
- `event_to_msg/2` - Convert event to `{:msg, term()}` or `:ignore`
- `update/2` - Return `{new_state, commands}`
- `view/1` - Return render tree

The StatefulComponent pattern remains available for backwards compatibility but should be considered deprecated for new development.

### Migration Strategy

1. New components must use the Elm Architecture pattern
2. Existing StatefulComponent-based code will continue to work
3. Integration tests may use either pattern during transition
4. Future phases should migrate StatefulComponent usage to Elm Architecture

## Consequences

### Positive

- Consistent component API across the codebase
- Better testability through explicit message types
- Clear data flow: Event → Message → Update → View
- Easier debugging (can log/inspect messages)
- Natural fit for the Command pattern for side effects
- Alignment with proven TUI framework patterns (BubbleTea)

### Negative

- Slightly more boilerplate for simple components
- Learning curve for developers unfamiliar with Elm Architecture
- Existing tests using StatefulComponent pattern create inconsistency
- Need to maintain backwards compatibility during transition

### Neutral

- Documentation should emphasize Elm Architecture as primary pattern
- Examples should demonstrate Elm Architecture pattern
- Test helpers should support both patterns during transition

---

## References

- [The Elm Architecture](https://guide.elm-lang.org/architecture/)
- [BubbleTea](https://github.com/charmbracelet/bubbletea) - Go TUI framework using similar pattern
- `lib/term_ui/elm.ex` - TermUI Elm behaviour definition
- `lib/term_ui/runtime.ex` - Runtime that orchestrates Elm components
