#!/bin/sh
# patches/010-rccl-rocshmem-dist-targets.therock.sh
#
# Slackware platform note: comm-libs/CMakeLists.txt declares rccl and
# rocshmem (the shipped libraries, not their -tests siblings) with
# USE_TEST_AMDGPU_TARGETS. Per cmake/therock_subproject.cmake:495-511,
# that option unconditionally selects THEROCK_TEST_AMDGPU_TARGETS -- the
# full 26-target set (gfx900..gfx1250) -- regardless of
# THEROCK_BUILD_TESTING=OFF. Neither THEROCK_BUILD_TESTING nor the
# scoped THEROCK_AMDGPU_FAMILIES is consulted on this path.
# Consequences on a gfx120X-all build:
#   - rccl's Device Linker table goes from 2 dist columns to 26
#     (~31,000 kernel compilations instead of ~2,500), and
#   - rccl-translate schedules gfx1250 pretranslate work, which is the
#     code path where rocjitsu-pretranslate tool failures occurred
#     (upstream TODO: "Set ON once RocJitsu supports every RCCL gfx1250
#     code object").
# rocPRIM demonstrates the intended behavior: declared without either
# target option, it inherits THEROCK_AMDGPU_TARGETS (gfx1200;gfx1201)
# and its configure summary shows exactly the dist targets.
#
# Fix: remove USE_TEST_AMDGPU_TARGETS from the rccl and rocshmem
# declares only (rccl-tests keeps it -- it is a test target and is not
# built with THEROCK_BUILD_TESTING=OFF). Both subprojects then fall
# through to the else() branch and inherit the configured targets.
#
# Alternative considered: USE_DIST_AMDGPU_TARGETS (explicitly select
# THEROCK_DIST_AMDGPU_TARGETS). Removal was chosen instead to match
# rocPRIM's precedent in the same tree.
#
# Post-flight check (after superbuild reconfigures rccl):
#   grep AMDGPU_TARGETS build/comm-libs/rccl/_toolchain.cmake
#   -> expect: set(AMDGPU_TARGETS gfx1200;gfx1201 ...)
#   and the rccl configure log's Device Linker table should list
#   gfx1200;gfx1201 only.
#
# Retirement triggers:
#   - upstream gates USE_TEST_AMDGPU_TARGETS on THEROCK_BUILD_TESTING
#     (therock_subproject.cmake:505 area), or
#   - upstream stops declaring rccl/rocshmem with USE_TEST_AMDGPU_TARGETS.
# Also retire (or revisit) if rccl-translate gfx1250 coverage is
# re-enabled and validated upstream.

set -e
_root="${SRC_CACHE:?}/therock-${VERSION}"
_f="${_root}/comm-libs/CMakeLists.txt"

[ -f "$_f" ] || { echo "*** ERROR: $_f not found." >&2; exit 1; }

# Idempotency: if neither rccl's nor rocshmem's declare block still
# carries the option, rccl-tests' copy is the only one left -> done.
# (The guarded seds below operate on address ranges that start at the
# declare line, so rccl-tests is never touched.)
_remaining=$(sed -n \
  -e '/therock_cmake_subproject_declare(rccl$/,/^)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
  -e '/therock_cmake_subproject_declare(rocshmem/,/^)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
  "$_f")
if [ -z "$_remaining" ]; then
  echo "already patched: rccl/rocshmem dist targets"
  exit 0
fi

# Delete the option within each library's declare block. The address
# range starts at 'declare(rccl' at end-of-line (so 'declare(rccl-tests'
# never matches) and ends at the block's closing paren at line start.
# Apply twice -- once per subproject -- on separate backup-free in-place
# passes guarded by the idempotency check above.
sed -i \
  -e '/therock_cmake_subproject_declare(rccl$/,/^)/{ /USE_TEST_AMDGPU_TARGETS/d }' \
  -e '/therock_cmake_subproject_declare(rocshmem$/,/^)/{ /USE_TEST_AMDGPU_TARGETS/d }' \
  "$_f"

# Verification: rccl and rocshmem declares must no longer carry the
# option, and exactly ONE occurrence must remain in the file (rccl-tests).
_keep=$(sed -n \
  -e '/therock_cmake_subproject_declare(rccl$/,/^)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
  -e '/therock_cmake_subproject_declare(rocshmem$/,/^)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
  "$_f")
if [ -n "$_keep" ]; then
  echo "*** ERROR: USE_TEST_AMDGPU_TARGETS still present in rccl/rocshmem declares:" >&2
  echo "$_keep" >&2
  exit 1
fi
_count=$(grep -c "USE_TEST_AMDGPU_TARGETS" "$_f" || true)
if [ "$_count" -ne 1 ]; then
  echo "*** ERROR: expected 1 remaining USE_TEST_AMDGPU_TARGETS (rccl-tests), found $_count." >&2
  exit 1
fi

# The tree file changed, which dirties the superbuild's configure
# dependency on comm-libs/CMakeLists.txt; the rccl _toolchain.cmake
# regenerates on the next cmake/ninja run. Belt and suspenders:
touch "$_f"

echo "patched: rccl/rocshmem -> inherit ${THEROCK_AMDGPU_TARGETS:-configured dist} targets (USE_TEST stripped from library declares)"
