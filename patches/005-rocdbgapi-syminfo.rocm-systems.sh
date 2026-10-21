#!/bin/sh
# rocm-systems#12596 adjacent: bundled libbacktrace in rocdbgapi drifted
# from the signature libbacktrace expects for syminfo_callback.
# Guard: skip if the fix is already present.
set -e
_root="${SRC_CACHE}/therock-${VERSION}/rocm-systems/projects/rocdbgapi"
_target="$_root/src/debug.cpp"

if grep -q 'syminfo_callback (void \*data, uintptr_t' "$_target" 2>/dev/null; then
  echo "=> already patched (or upstream fixed): rocdbgapi syminfo_callback"
  exit 0
fi

patch -d "$_root" -p1 --verbose < "$(dirname "$0")/rocdbgapi-syminfo-callback.patch"

# Verify: die loudly if application didn't take.
if ! grep -q 'syminfo_callback (void \*data, uintptr_t' "$_target"; then
  echo "*** ERROR: rocdbgapi syminfo patch failed to apply cleanly." >&2
  exit 1
fi
