# GitHub branch cleanup on 30 September 2026

The maintainer approved GitHub cleanup before the separate Hex publication.
A verified local Git bundle and archive refs preserve all 39 original branch heads.
Every removed branch matched an exact merged PR head. Its merge remains in the target history.
Active worktrees, open PRs, unmatched work, v1 maintenance, release history, and published tags remain.
No branch was force-pushed.

| Branch | Original head | Result | Evidence |
| --- | --- | --- | --- |
| `chore/v1-maintenance-baseline` | `bf5f19b3c543f03526aff71ba458b84979fcc1eb` | removed | exact merged PR #71; head preserved in verified Git bundle |
| `chore/v2-cleanup-baseline` | `9cdb2fa518ab5543196b892999cfb58fde9a8c59` | removed | exact merged PR #72; head preserved in verified Git bundle |
| `chore/v2-release-candidate` | `0d7bcdd46235cd8d8aa0779897db5d66b4813dd6` | removed | exact merged PR #93; head preserved in verified Git bundle |
| `chore/v2-release-evidence` | `476cf99d22afa30b4f068f38ffa68ce5fb874d40` | removed | exact merged PR #96; head preserved in verified Git bundle |
| `codex/root-commands-and-table-refresh` | `fb49fa3d8059df98baa668e96d4091d3f83b5816` | removed | exact merged PR #37; head preserved in verified Git bundle |
| `develop` | `4c704860382a65b33ecfb7448d83a245e182dfe0` | keep | active branch or release history |
| `docs/1.0-documentation-audit` | `dc281cbfbd3792de8048aa8af4ed0e4fe8006c77` | removed | exact merged PR #44; head preserved in verified Git bundle |
| `docs/2.0-redesign` | `c523272abae54c53b985b470121a5caa79b415f7` | keep | no exact merged PR record |
| `docs/release-gate-dispositions` | `1c42e6be0aff0cb3ec2900ad1d29297ffc33ccdc` | removed | exact merged PR #43; head preserved in verified Git bundle |
| `docs/v1-linux-release` | `4fced97efb044a8954a36a8a2cd41c6d705aa855` | removed | exact merged PR #82; head preserved in verified Git bundle |
| `docs/v2-community` | `09f8d807bdf657a0b5fd259b554acf644f10e43f` | removed | exact merged PR #85; head preserved in verified Git bundle |
| `docs/v2-linux-release` | `560693b4dcaf0dd47215d7445659580083026362` | removed | exact merged PR #84; head preserved in verified Git bundle |
| `feat/v2-ghostty-session` | `6e1b447c041cc4928781939931b87498d23cd339` | keep | active branch or release history |
| `feat/v2-web-backend` | `cd92be5cd5b84cd72344623440587869d2ee03b8` | removed | exact merged PR #89; head preserved in verified Git bundle |
| `feat/v2-web-browser` | `b8a2dfd04aa20fc7d05de25b6a3df7e0b6e416f4` | removed | exact merged PR #90; head preserved in verified Git bundle |
| `fix/v1-cell-colors` | `51bb61cef653b6bf22b8af30cd53839470599cbf` | removed | exact merged PR #80; head preserved in verified Git bundle |
| `fix/v1-redraw-recovery` | `b9114fd4c55cc9578f058fceb355b400a4970c41` | removed | exact merged PR #76; head preserved in verified Git bundle |
| `fix/v1-resume-recovery` | `fb39af8ff9e1ae931abd3ea06cc2eb13012e63a6` | removed | exact merged PR #78; head preserved in verified Git bundle |
| `fix/v1-windows-input` | `f73957414e04bac283da71a69beb1ce173b56707` | removed | exact merged PR #92; head preserved in verified Git bundle |
| `fix/v2-option-delete` | `9409f1e09959554c814bdfccf0b7e456d9e335bb` | removed | exact merged PR #73; head preserved in verified Git bundle |
| `fix/v2-redraw-recovery` | `4bd28d5b8efec57aafa0ffffaddd087babfdb770` | removed | exact merged PR #77; head preserved in verified Git bundle |
| `fix/v2-resume-recovery` | `dbbe3f308431f74c76faf646386985885c5af9c7` | removed | exact merged PR #79; head preserved in verified Git bundle |
| `fix/v2-showcase-process-identities` | `4c683262a9b11847650a16e787ad917e8a6dbf7c` | removed | exact merged PR #97; head preserved in verified Git bundle |
| `fix/v2-signal-cleanup` | `f658d67a7b9b6e4bc964a692ee5188d1afc67051` | removed | exact merged PR #83; head preserved in verified Git bundle |
| `fix/v2-windows-input` | `3c2b9e64b3fa9ffc5aaa5418280dbbf33454fde2` | removed | exact merged PR #88; head preserved in verified Git bundle |
| `main` | `0e0e8e43542d53f113dc13a5ed2c99fbdbe7e4dd` | keep | active branch or release history |
| `maint/1.x` | `f8a363301830ab0bf5ed21088bd0b85680597874` | keep | active branch or release history |
| `multi-renderer` | `945c148106962326636efe9bcdbea8ab695da95e` | keep | no exact merged PR record |
| `next/v2` | `0b1e38245711069dd576393049d3922ff1dd97f9` | keep | active branch or release history |
| `release/1.0.0` | `c3d471730fb2056a08a4b26873af37261a0b45f9` | keep | active branch or release history |
| `release/1.0.0-final-metadata` | `6695649136aa38285c05b4f58da2a605e4f35ce0` | keep | active branch or release history |
| `test/sexy-spex-acceptance-spec` | `7b25eac0713b79faa30d5e1750a0ec904b2bdbf2` | removed | exact merged PR #69; head preserved in verified Git bundle |
| `test/v1-layout-constraints` | `f0fc2334044b55271e5209588b1cca5d8d4ef692` | removed | exact merged PR #74; head preserved in verified Git bundle |
| `test/v1-ssh-parity` | `6c73c1e08859be1bc270183468e0698478dfbb3e` | removed | exact merged PR #86; head preserved in verified Git bundle |
| `test/v2-async-monitor-registration` | `2efba0ec95cb9558a23a42b5582ac8ac71c8a982` | removed | exact merged PR #95; head preserved in verified Git bundle |
| `test/v2-cell-colors` | `fdbedec79074c6529659b3dbcd7fe2ea1eabba97` | removed | exact merged PR #81; head preserved in verified Git bundle |
| `test/v2-layout-constraints` | `62f374c92d2915f2d033124e8d415672072534b1` | removed | exact merged PR #75; head preserved in verified Git bundle |
| `test/v2-ssh-coalescing-timeout` | `c165d2cf0c25fe5abb6fa889111239be15458d6d` | removed | exact merged PR #94; head preserved in verified Git bundle |
| `test/v2-ssh-parity` | `9ae75f38124b329d70f44632474159357ceb4bc1` | removed | exact merged PR #87; head preserved in verified Git bundle |

Removed branches: 30.
The recovery bundle is `before-v2-main.bundle` in the local TermUI backup directory.
The inventory and bundle checksum are saved beside it.
