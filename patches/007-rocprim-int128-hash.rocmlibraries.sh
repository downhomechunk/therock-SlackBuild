#!/bin/sh
# 007-rocprim-int128-hash.rocmlibraries.sh
# Fixes: rocPRIM test_device_segmented_topk.cpp defines hash<int128_t>
# specializations that collide with libstdc++ 16's native __int128 hashes.
# Deletion matches manual fix; guards ensure idempotent re-runs.
#
# Retirement triggers: TheRock upstream removes these specializations when
# libstdc++ 16+ is the baseline (tracked by TheRock#XXXXX).

set -e

_root="${SRC_CACHE:?}/therock-${VERSION}"
_file="${_root}/rocm-libraries/projects/rocprim/test/rocprim/test_device_segmented_topk.cpp"
_payload="$(dirname "$0")/rocprim-int128-hash.patch"

# Sanity: file must exist
[ -f "$_file" ] || { echo "*** ERROR: $_file not found." >&2; exit 1; }

# Guard: already patched? Skip.
# Detect absence of the first problematic struct declaration.
if ! grep -q 'struct hash<rocprim::int128_t>' "$_file"; then
  echo "already patched (or upstream fixed): rocprim int128 hash"
  exit 0
fi

# Payload present?
[ -f "$_payload" ] || { echo "VERIFICATION FAILED: missing $_payload" >&2; exit 1; }

# Apply the patch
patch -d "$_root" -p1 --forward < "$_payload"

# Verify: the struct declarations should be gone
if grep -q 'struct hash<rocprim::int128_t>' "$_file"; then
  echo "*** ERROR: rocprim int128 hash patch failed to apply." >&2
  exit 1
fi

echo "patched: rocprim int128 hash collision"
