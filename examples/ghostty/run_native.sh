#!/bin/sh
set -eu

# The SDK source build links libghostty-vt by its Linux soname.
cd "$(dirname "$0")"
native_lib="$(pwd -P)/deps/ghostty/priv/lib"
test -f "$native_lib/libghostty-vt.so.0"
export LD_LIBRARY_PATH="$native_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GHOSTTY_BUILD=1
exec mix "$@"
