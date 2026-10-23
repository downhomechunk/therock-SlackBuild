#!/bin/sh
# patches/009-rocprofsys-fmt-dir.therock.sh
#
# Slackware platform note: rocprofiler-systems' cmake/FmtLib.cmake calls
# find_package(fmt REQUIRED), which therock_subproject_dep_provider.cmake
# does not intercept (fmt is not in the routing table for this subproject,
# despite therock-fmt being listed in BUILD_DEPS). The search therefore
# escapes to the host system. On Slackware-current, /usr/lib64/cmake/fmt is
# fmt 12.2.0 while therock-spdlog and build/third-party/fmt/dist are fmt
# 11.1.3 -- compiling rocprofsys against v12 headers and linking against
# v11 libs produces undefined fmt::v11 symbols when linking rocprof-sys-avail.
# Verified: CMakeCache showed FMT_VERSION=11.2.0 sitting next to
# fmt_DIR=/usr/lib64/cmake/fmt, and the failing link line ended in
# /usr/lib64/libfmt.so.12.2.0.
#
# Fix: force fmt_DIR at the bundled dist before FmtLib.cmake runs, via the
# subproject pre-hook (same mechanism as pre_hook_MIOpen.cmake).
#
# Post-flight check (after rocprofsys configures):
#   grep fmt_DIR build/profiler/rocprofiler-systems/build/CMakeCache.txt
#   -> expect .../build/third-party/fmt/dist/lib/cmake/fmt
# The configure log should also print:
#   "pre_hook: fmt_DIR forced to bundled fmt v11"
#
# Retirement triggers: upstream routes fmt through the dep provider for
# this subproject (fmt_DIR then resolves to the dist automatically), or
# profiler/ grows an upstream pre_hook_rocprofiler-systems.cmake that
# already handles it.

set -e
_root="${SRC_CACHE:?}/therock-${VERSION}"
_f="${_root}/profiler/pre_hook_rocprofiler-systems.cmake"
_marker='# therock-fmt-dir-override'

# Idempotency: skip if the override is already present (re-run over a
# tree that wasn't cleaned by the SlackBuild's git checkout pass).
if [ -f "$_f" ]; then
    grep -q "$_marker" "$_f" && { echo "already patched: rocprofsys fmt_DIR"; exit 0; }
fi

# Create the hook if upstream doesn't ship one for this subproject yet;
# the fmt block is self-contained either way. ml-libs/pre_hook_MIOpen.cmake
# exists upstream, so the pre-hook loading machinery does -- it just needs
# a correctly-named file in profiler/.
touch "$_f"

cat >> "$_f" <<'EOF'

# therock-fmt-dir-override
# Route find_package(fmt) to the superbuild's bundled fmt (v11.1.3), not
# the host system's (Slackware-current: fmt 12.2 in /usr/lib64/cmake/fmt).
# The dep provider does not intercept fmt for this subproject even though
# therock-fmt is in BUILD_DEPS; letting the search escape mixes ABIs at
# link time (therock-spdlog's libspdlog.a and the dist libfmt.a are v11).
if(DEFINED THEROCK_BINARY_DIR)
    set(_therock_fmt_root "${THEROCK_BINARY_DIR}")
else()
    # Fallback: this subproject builds at
    # <superbuild-build>/profiler/rocprofiler-systems/build
    get_filename_component(_therock_fmt_root
        "${CMAKE_BINARY_DIR}/../../.." ABSOLUTE)
endif()

if(EXISTS "${_therock_fmt_root}/third-party/fmt/dist/lib/cmake/fmt")
    set(fmt_DIR "${_therock_fmt_root}/third-party/fmt/dist/lib/cmake/fmt"
        CACHE PATH "therock bundled fmt (v11) -- never the host's" FORCE)
    message(STATUS "pre_hook: fmt_DIR forced to bundled fmt v11 (patches/009)")
else()
    message(FATAL_ERROR
        "pre_hook: therock bundled fmt not found under "
        "${_therock_fmt_root} -- expected therock-fmt to be built first "
        "(BUILD_DEPS ordering broken?). See patches/009.")
endif()
EOF

# Verification: the marker must survive the heredoc append.
grep -q "$_marker" "$_f" || { echo "*** ERROR: injection failed into $_f" >&2; exit 1; }
echo "patched: rocprofsys fmt_DIR -> bundled fmt"
