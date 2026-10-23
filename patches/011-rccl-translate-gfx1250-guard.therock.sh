#!/bin/sh
# patches/011-rccl-translate-gfx1250-guard.therock.sh
#
# Slackware platform note: rccl-translate unbundles gfx1250 device code
# from librccl.so via bulk_unbundle --gfx-arch gfx1250. The step is
# guarded only by feature flags in comm-libs/CMakeLists.txt:
#
#   if(THEROCK_ENABLE_ROCJITSU_HOTSWAP AND THEROCK_FLAG_KPACK_SPLIT_ARTIFACTS
#      AND NOT THEROCK_SANITIZER)
#
# Those flags are NOT sufficient on a scoped build:
#   1. The feature-derivation layer "implicitly enables" ROCJITSU and
#      ROCJITSU_HOTSWAP even when -DTHEROCK_ENABLE_ROCJITSU_HOTSWAP=OFF
#      was passed (observed: configure prints "Implicitly enabled
#      features: ROCJITSU_HOTSWAP ... ROCJITSU" while CMakeCache.txt
#      still records OFF -- normal variables shadow the cache entries,
#      so the guard reads ON).
#   2. With GPU targets scoped (patches/010 / THEROCK_AMDGPU_FAMILIES),
#      librccl.so contains only the dist archs, and the unbundle fails:
#      ValueError: No code objects for architecture 'gfx1250'
#      -- the same failure mode upstream documents for the ASAN case
#      in the comment above the guard.
#
# Fix: harden the guard on reality instead of flags. rccl-translate is
# only meaningful when the dist actually contains gfx1250, so add
#   AND "gfx1250" IN_LIST THEROCK_DIST_AMDGPU_TARGETS
# to the condition. This is immune to feature implication, cache/normal
# variable shadowing, and stale graphs.
#
# Post-flight check (after superbuild reconfigure):
#   grep -c "rccl-translate" build/build.ninja     -> expect: 0
#   (on a gfx1250-containing dist, expect unchanged nonzero)
#
# Retirement triggers:
#   - upstream conditions rccl-translate on dist target membership, or
#   - upstream stops implicitly enabling ROCJITSU/HOTSWAP over the
#     user's explicit -D, or
#   - a future GPU families scope includes gfx1250 (remove the patch
#     and let the step run as intended).

set -e
_root="${SRC_CACHE:?}/therock-${VERSION}"
_f="${_root}/comm-libs/CMakeLists.txt"
_old='  if(THEROCK_ENABLE_ROCJITSU_HOTSWAP AND THEROCK_FLAG_KPACK_SPLIT_ARTIFACTS
     AND NOT THEROCK_SANITIZER)'
_new='  if(THEROCK_ENABLE_ROCJITSU_HOTSWAP AND THEROCK_FLAG_KPACK_SPLIT_ARTIFACTS
     AND NOT THEROCK_SANITIZER AND "gfx1250" IN_LIST THEROCK_DIST_AMDGPU_TARGETS)'

[ -f "$_f" ] || { echo "*** ERROR: $_f not found." >&2; exit 1; }

# Idempotency: the new guard line already present -> done.
grep -q 'AND "gfx1250" IN_LIST THEROCK_DIST_AMDGPU_TARGETS' "$_f" && {
  echo "already patched: rccl-translate gfx1250 guard"
  exit 0
}

# Apply: match the two-line guard verbatim. Using a context match on the
# continuation line (rather than line numbers) so upstream edits above
# don't shift the target out from under us.
if ! grep -qF "$_old" "$_f"; then
  echo "*** ERROR: expected rccl-translate guard not found in $_f." >&2
  echo "***        Upstream may have reformatted the if() block -- inspect" >&2
  echo "***        around 'therock_cmake_subproject_declare(rccl-translate' and update." >&2
  exit 1
fi

# sed multi-line replacement: join pattern with \n, replace with new text.
# FreeBSD/GNU-portable approach: use sed's N to pull the continuation.
sed -i \
  -e '/^  if(THEROCK_ENABLE_ROCJITSU_HOTSWAP AND THEROCK_FLAG_KPACK_SPLIT_ARTIFACTS$/{N;s/     AND NOT THEROCK_SANITIZER)/     AND NOT THEROCK_SANITIZER AND "gfx1250" IN_LIST THEROCK_DIST_AMDGPU_TARGETS)/;}' \
  "$_f"

# Verification: the guard must now carry the IN_LIST clause.
grep -q 'AND "gfx1250" IN_LIST THEROCK_DIST_AMDGPU_TARGETS' "$_f" || {
  echo "*** ERROR: guard rewrite failed in $_f" >&2
  exit 1
}

# Dirties the superbuild configure dependency on comm-libs/ so
# build.ninja regenerates without the rccl-translate targets on the
# next cmake/ninja run.
touch "$_f"

echo "patched: rccl-translate requires gfx1250 in dist targets"
