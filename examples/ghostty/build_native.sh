#!/bin/sh
set -eu

# Ghostty 0.5.0's Linux ARM64 asset contains x86_64 libraries.
cd "$(dirname "$0")"
example_root=$(pwd -P)
source_root="$example_root/_build/ghostty-source"
ghostty_ref=baad0aa6669dc576872831752be0f30debecbfd1

test "$(zig version)" = 0.15.2
mix deps.get
mix deps.compile

if [ ! -d "$source_root/.git" ]; then
  git init "$source_root"
  git -C "$source_root" remote add origin https://github.com/ghostty-org/ghostty.git
fi
git -C "$source_root" fetch --depth 1 origin "$ghostty_ref"
git -C "$source_root" checkout --detach FETCH_HEAD
test "$(git -C "$source_root" rev-parse HEAD)" = "$ghostty_ref"

(
  cd deps/ghostty
  MIX_DEPS_PATH="$example_root/deps" MIX_BUILD_PATH="$example_root/_build" \
    GHOSTTY_SOURCE_DIR="$source_root" mix ghostty.setup
)

GHOSTTY_BUILD=1 mix deps.compile ghostty --force
MIX_ENV=test GHOSTTY_BUILD=1 mix deps.compile ghostty --force
