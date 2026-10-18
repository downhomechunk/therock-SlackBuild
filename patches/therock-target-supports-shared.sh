#!/bin/sh
# therock-target-supports-shared.sh
# Fixes: rocRAND configure dies with "ADD_LIBRARY called with SHARED
# option but the target platform does not support dynamic linking"
set -e

_file=$SRC_CACHE/therock-$VERSION/cmake/therock_primlibs_benchmark_deps.cmake

# ingredient 3: prove it landed
grep -q TARGET_SUPPORTS_SHARED_LIBS "$_file" && {
  echo "already patched"; exit 0; }

# ingredient 2: the edit — insert one line at the top of the file
sed -i '1i set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)' "$_file"

# ingredient 3 again: if sed didn't do its job, die loudly
grep -q TARGET_SUPPORTS_SHARED_LIBS "$_file" || {
  echo "VERIFICATION FAILED: $_file"; exit 1; }
