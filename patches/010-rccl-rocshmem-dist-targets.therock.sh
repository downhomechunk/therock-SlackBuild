#!/bin/sh
# patches/010-rccl-rocshmem-dist-targets.therock.sh
#
# Slackware platform note: comm-libs/CMakeLists.txt declares rccl and
# rocshmem (the shipped libraries, not their -tests siblings) with
# USE_TEST_AMDGPU_TARGETS. Per cmake/therock_subproject.cmake:495-511,
# that option selects THEROCK_TEST_AMDGPU_TARGETS -- the full 26-target
# set (gfx900..gfx1250) -- regardless of THEROCK_BUILD_TESTING=OFF.
#
# NOTE: this is DELIBERATE upstream behavior, not a leak. The declare
# blocks carry explicit comments:
#   rccl:     "Build all GPU targets in a single target-neutral artifact
#              as long as the host code isn't fully target agnostic."
#   rocshmem: ".hip_fatbin/.hip_gpubin_* ELF sections ... incompatible
#              with kpack injection. Build all GPU targets in a single
#              target-neutral artifact as a workaround."
# Upstream intentionally ships fat, target-neutral artifacts for these
# two libraries. There is no way to produce a scoped dist of rccl/
# rocshmem short of patching the declares.
#
# We locally override that choice for scoped Slackware builds: with
# THEROCK_AMDGPU_FAMILIES=gfx120X-all, the full target list makes
# rccl's Device Linker table ~26 columns (~31,000 kernel compilations
# instead of ~2,500) and schedules gfx1250 work the rccl translate
# TODO ("Set ON once RocJitsu supports every RCCL gfx1250 code object")
# already calls shaky. Stripping the option lets both declares fall
# through to the else() branch and inherit THEROCK_AMDGPU_TARGETS
# (gfx1200;gfx1201) -- the same path rocPRIM takes.
#
# TRADE-OFF, accepted knowingly: our librccl.so/rocshmem artifacts cover
# gfx1200/gfx1201 only. Upstream's host-code-agnosticism concern may be
# stale or may bite. Before trusting this build, smoke-test an actual
# NCCL collective (e.g. one-node allreduce) on the target GPU.
#
# Post-flight check (after superbuild reconfigures rccl):
#   grep AMDGPU_TARGETS build/comm-libs/rccl/_toolchain.cmake
#   -> expect: set(AMDGPU_TARGETS gfx1200;gfx1201 ...)
#   and the rccl configure log's Device Linker table should list
#   gfx1200;gfx1201 only.
#
# Retirement triggers:
#   - upstream offers a sanctioned scoped-dist path for rccl/rocshmem, or
#   - upstream stops declaring them with USE_TEST_AMDGPU_TARGETS, or
#   - rccl host code becomes fully target agnostic (per their comment,
#     the workaround is conditional on that).

set -e
_root="${SRC_CACHE:?}/therock-${VERSION}"
_f="${_root}/comm-libs/CMakeLists.txt"

[ -f "$_f" ] || { echo "*** ERROR: $_f not found." >&2; exit 1; }

# Idempotency: if neither rccl's nor rocshmem's declare block still
# carries the option, rccl-tests' copy is the only one left -> done.
#
# RANGE ANCHORS: the declare block's closing paren is INDENTED
# ("  )"), so the end anchor must be /^[[:space:]]*)/. A bare /^)/
# never matches and the range overruns ~217 lines into later
# declares. (Verified empirically; do not "simplify" back to ^) .)
_remaining=$(sed -n \
  -e '/therock_cmake_subproject_declare(rccl$/,/^[[:space:]]*)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
  -e '/therock_cmake_subproject_declare(rocshmem$/,/^[[:space:]]*)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
  "$_f")
if [ -z "$_remaining" ]; then
  echo "already patched: rccl/rocshmem dist targets"
  exit 0
fi

# Delete the option within each library's declare block. The start
# anchor matches 'declare(rccl' at end-of-line only ('declare(rccl-tests'
# can never match); the end anchor stops at the first indented closing
# paren, which closes the declare.
sed -i \
  -e '/therock_cmake_subproject_declare(rccl$/,/^[[:space:]]*)/{ /USE_TEST_AMDGPU_TARGETS/d }' \
  -e '/therock_cmake_subproject_declare(rocshmem$/,/^[[:space:]]*)/{ /USE_TEST_AMDGPU_TARGETS/d }' \
  "$_f"

# Verification: rccl and rocshmem declares must no longer carry the
# option, and exactly ONE occurrence must remain in the file (rccl-tests).
_keep=$(sed -n \
  -e '/therock_cmake_subproject_declare(rccl$/,/^[[:space:]]*)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
  -e '/therock_cmake_subproject_declare(rocshmem$/,/^[[:space:]]*)/{ /USE_TEST_AMDGPU_TARGETS/p }' \
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

# Dirties the superbuild's configure dependency on comm-libs/
# CMakeLists.txt, so the rccl/rocshmem _toolchain.cmake files
# regenerate (with collapsed target lists) on the next cmake/ninja run.
touch "$_f"

echo "patched: rccl/rocshmem -> inherit configured dist targets (USE_TEST stripped from library declares)"
