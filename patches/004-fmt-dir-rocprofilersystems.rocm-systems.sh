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

# Inject -Dfmt_DIR after ROCPROFSYS_BUILD_FMT=OFF
perl -pi -e '\''
  if (/^-DROCPROFSYS_BUILD_FMT=OFF/) {
    print "      -Dfmt_DIR=${SRC_CACHE}/therock-${VERSION}/build/third-party/fmt/dist/lib/cmake/fmt\n"
  }
'\'' "$_f"'

grep fmt_DIR "$_f" > /dev/null || {
  echo "*** ERROR: fmt_DIR injection failed." >&2; exit 1;
}
