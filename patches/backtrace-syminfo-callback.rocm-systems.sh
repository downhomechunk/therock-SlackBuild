#!/bin/sh
# backtrace-syminfo-callback.rocm-systems.sh
# Fixes: roctracer/rocprofiler/rocdbgapi syminfo callbacks written against
# libbacktrace's old 5-param callback typedef; Slackware-current's newer
# libbacktrace widened backtrace_syminfo_callback to 7 params (adds
# binary_filename, base_address). Upstream builds against Ubuntu's older
# libbacktrace, so the mismatch only shows on newer distros.
# Reference: /home/dhc/Projects/sbo/therock/backtrace-syminfo-reference.diff
set -e

_root=$SRC_CACHE/therock-$VERSION/rocm-systems
_payload=$(dirname "$0")/backtrace-syminfo-callback.patch

# guard: already patched? (signature grep across all three files)
if grep -q 'binary_filename' \
     "$_root/projects/roctracer/src/util/debug.cpp" \
     "$_root/projects/rocprofiler/src/utils/helper.cpp" \
     "$_root/projects/rocdbgapi/src/debug.cpp"; then
  echo "already patched"; exit 0
fi

# payload exists? die loudly rather than patching with nothing
[ -f "$_payload" ] || {
  echo "VERIFICATION FAILED: missing payload $_payload" >&2; exit 1; }

# apply
patch -d "$_root" -p1 --forward < "$_payload"

# verify: all three call sites' callbacks now carry the widened signature
for _f in projects/roctracer/src/util/debug.cpp \
          projects/rocprofiler/src/utils/helper.cpp \
          projects/rocdbgapi/src/debug.cpp; do
  grep -q 'base_address' "$_root/$_f" || {
    echo "VERIFICATION FAILED: $_f lacks widened signature" >&2; exit 1; }
done
echo "ok"
