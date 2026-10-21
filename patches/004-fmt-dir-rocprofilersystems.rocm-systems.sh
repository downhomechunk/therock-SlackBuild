#!/bin/sh
# patches/004-fmt-dir-rocprofilersystems.rocm-systems.sh
#
# rocprofiler-systems find_package(fmt REQUIRED) falls through to
# /usr/lib64/cmake/fmt instead of the vendored tree, unlike spdlog
# which resolves correctly. Explicitly set fmt_DIR to match.
#
# Target tree: rocm-systems (superbuild source)

_root="${SRC_CACHE:?}/therock-${VERSION}"
_f="${_root}/profiler/CMakeLists.txt"

[ -f "$_f" ] || { echo "*** ERROR: $_f not found." >&2; exit 1; }

# Guard: already patched? No-op on re-runs.
grep -q 'fmt_DIR' "$_f" && { echo "already patched: fmt_DIR"; exit 0; }

# The path is computed in the shell and passed via the environment,
# so the Perl program stays purely single-quoted -- no escaping.
_fmt_dir="${_root}/build/third-party/fmt/dist/lib/cmake/fmt"

FMT_DIR="$_fmt_dir" perl -pi -e '
  if (/^\s*-DROCPROFSYS_BUILD_FMT=OFF/) {
    print "      -Dfmt_DIR=$ENV{FMT_DIR}\n";
  }
' "$_f"

grep -q fmt_DIR "$_f" || {
  echo "*** ERROR: fmt_DIR injection failed." >&2; exit 1;
}
