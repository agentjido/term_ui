---
title: Register a process monitor before forced exit
type: test
date: 2026-09-30
status: verified
---

# Register a process monitor before forced exit

The minimum-version CI test expected `:killed` after a forced terminal-session
exit. It sometimes received `:noproc`. The session could die before the test
installed its monitor, so the assertion depended on process scheduling.

[PR #100](https://github.com/agentjido/term_ui/pull/100) added a session callback
that checks the test process in `Process.info(self(), :monitored_by)` before
the test sends the exit signal. The test still requires the original `:killed`
result. The change did not alter the runtime or increase the timeout.

The affected test passed 251 repeated runs on Elixir 1.18.4 / OTP 28.1.1. The
full quality, coverage, and required CI checks also passed at source commit
`9b55d7178ada39d17d27ecbcdf501669956eea2e`.

When a test needs a particular exit reason, install and confirm the monitor
before the action that can stop the child. This evidence applies to that test;
it does not prove every terminal or lifecycle path.
