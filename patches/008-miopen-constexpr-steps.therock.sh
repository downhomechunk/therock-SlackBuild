#!/bin/sh
# patches/008-miopen-constexpr-steps.therock.sh
#
# Slackware platform note: gcc 16's libstdc++ ships with _GLIBCXX_ASSERTIONS
# enabled by default; std::array bounds checks execute inside constexpr
# evaluation, and MIOpen's hipconv swizzle-layout math exceeds clang's
# default 1048576-step budget. The failed constexpr evaluation demotes
# static constexpr members to dynamic initialization, which breaks
# device-side references ("const variable cannot be emitted on device
# side" -> cascade of __host__ variable errors).
# TheRock already passes -fgpu-allow-device-init (insufficient alone);
# removing the step budget fixes it, verified on direct_wgrad_shard1.cpp.
#
# Retirement triggers: upstream MIOpen restructures the hipconv constexpr
# layouts, or Slackware disables _GLIBCXX_ASSERTIONS by default.

set -e
_root="${SRC_CACHE:?}/therock-${VERSION}"
_f="${_root}/ml-libs/pre_hook_MIOpen.cmake"

[ -f "$_f" ] || { echo "*** ERROR: $_f not found." >&2; exit 1; }

grep -q 'fconstexpr-steps' "$_f" && { echo "already patched: miopen constexpr steps"; exit 0; }

cat >> "$_f" <<'EOF'

# Raised constexpr step budget (see patches/008): Slackware's default
# _GLIBCXX_ASSERTIONS makes MIOpen hipconv layout constexpr math exceed
# clang's default limit. Appended via add_compile_options so nothing
# upstream passes is overridden.
add_compile_options(-fconstexpr-steps=0)
EOF

grep -q 'fconstexpr-steps' "$_f" || { echo "*** ERROR: injection failed." >&2; exit 1; }
echo "patched: miopen constexpr steps"
