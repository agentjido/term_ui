#!/bin/bash

# Run the package gates used by the shared Jido CI workflow.

set -euo pipefail

mix deps.get
mix quality
mix coveralls
mix deps.unlock --check-unused
mix hex.audit
mix docs --warnings-as-errors -f html
HEX_API_KEY=dry-run mix hex.publish --dry-run --yes
