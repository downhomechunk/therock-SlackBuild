#!/bin/sh
# primlibs-cmake4-shared-libs.therock.sh
# Fixes: rocRAND configure dies with "ADD_LIBRARY called with SHARED
# option but the target platform does not support dynamic linking".
#
# Mechanism: therock_primlibs_benchmark_deps.cmake is injected via
# CMAKE_PROJECT_TOP_LEVEL_INCLUDES, so its find_package(amd_smi) runs
# before the sub-project's project() initializes platform support. Under
# CMake 4.x the resulting SHARED IMPORTED target fails on a platform
# that hasn't declared TARGET_SUPPORTS_SHARED_LIBS yet. Declaring it
# globally first unblocks configure.
#
# Retirement triggers:
#   https://github.com/ROCm/TheRock/issues/8847 (TARGET_SUPPORTS_SHARED_LIBS)
#   https://github.com/ROCm/rocm-libraries/pull/12532 (benchmarks declare
#     their own amd_smi dep; removes the injected find_package entirely)
# Equivalent to the retired sed-based therock-target-supports-shared.sh
# (byte-identical result; this is the unified-dialect copy).
set -e

_root=$SRC_CACHE/therock-$VERSION
_payload=$(dirname "$0")/primlibs-cmake4-shared-libs.patch
_file=$_root/cmake/therock_primlibs_benchmark_deps.cmake

# Guard: already patched? No-op on re-runs.
grep -q TARGET_SUPPORTS_SHARED_LIBS "$_file" && {
  echo "already patched"; exit 0; }

# Payload present? Die loudly rather than patch with nothing.
[ -f "$_payload" ] || {
  echo "VERIFICATION FAILED: missing payload $_payload" >&2; exit 1; }

# The edit: apply the patch from the root tree.
patch -d "$_root" -p1 --forward < "$_payload"

# Verify: die loudly if it didn't land.
grep -q TARGET_SUPPORTS_SHARED_LIBS "$_file" || {
  echo "VERIFICATION FAILED: $_file" >&2; exit 1; }
