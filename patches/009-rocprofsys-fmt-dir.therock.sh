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
# Root cause (confirmed in rocprofiler-systems_configure.log): the embedded
# profiler-hub clone runs profiler-hub/cmake/fmt.cmake at configure time,
# which probes find_package(fmt 11.2.0 QUIET). The bundled dist (11.1.3)
# fails the version floor, so the search escapes to the host system, and a
# successful config-mode find REWRITES fmt_DIR=/usr/lib64/cmake/fmt in the
# cache -- poisoning the later find_package(fmt REQUIRED) in FmtLib.cmake.
# Upstream CI never sees this because their images have no system fmt.
#
# Fix: force BOTH cache variables via the subproject pre-hook (runs at
# t=0.0 via _init.cmake, before profiler-hub's fmt.cmake at t=0.7):
#   1. fmt_DIR      -> the superbuild's bundled fmt dist
#   2. FMT_VERSION  -> 11.1.3, matching the dist. profiler-hub's
#      set(FMT_VERSION "11.2.0" CACHE STRING ...) is a plain (non-FORCE)
#      cache set, so it becomes a no-op when our value already exists.
#
# Post-flight check (after rocprofsys configures):
#   grep -E "fmt_DIR|FMT_VERSION" \
#     build/profiler/rocprofiler-systems/build/CMakeCache.txt
#   -> expect .../build/third-party/fmt/dist/lib/cmake/fmt and 11.1.3
# The configure log should also print:
#   "pre_hook: fmt_DIR forced to bundled fmt v11"
# and should NOT print "Using system fmt (version 12.2.0)".
#
# Retirement triggers:
#   - upstream routes fmt through the dep provider for this subproject, or
#   - profiler-hub lowers/drops its fmt version pin below the bundled
#     version, or
#   - therock bumps the bundled fmt dist version (then update the forced
#     FMT_VERSION below to match, or the probe fails LOW and we trade this
#     bug for its mirror image).

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
#
# Additionally: the embedded profiler-hub probes find_package(fmt 11.2.0)
# at configure time; against a dist of 11.1.3 that version floor fails,
# the search escapes to the host system, and the successful find rewrites
# fmt_DIR in the cache -- clobbering this hook's value before FmtLib.cmake
# runs. Forcing FMT_VERSION to the dist's exact version keeps the probe
# satisfied by the dist; profiler-hub's own plain (non-FORCE) cache set
# is then a no-op. If this hook ever fatal-errors on a version mismatch,
# the bundled fmt was probably bumped -- update the version below.
if(DEFINED THEROCK_BINARY_DIR)
    set(_therock_fmt_root "${THEROCK_BINARY_DIR}")
else()
    # Fallback: this subproject builds at
    # <superbuild-build>/profiler/rocprofiler-systems/build
    get_filename_component(_therock_fmt_root
        "${CMAKE_BINARY_DIR}/../../.." ABSOLUTE)
endif()

set(_therock_fmt_dist "${_therock_fmt_root}/third-party/fmt/dist/lib/cmake/fmt")

if(EXISTS "${_therock_fmt_dist}/fmt-config-version.cmake")
    # Read the dist's actual version so the probe pin and the dist can
    # never drift apart.
    file(READ "${_therock_fmt_dist}/fmt-config-version.cmake" _therock_fmt_verfile)
    string(REGEX MATCH "PACKAGE_VERSION \"([0-9]+\\.[0-9]+\\.[0-9]+)\"" _therock_fmt_match "${_therock_fmt_verfile}")
    if(NOT _therock_fmt_match)
        message(FATAL_ERROR
            "pre_hook: could not parse PACKAGE_VERSION from "
            "${_therock_fmt_dist}/fmt-config-version.cmake. See patches/009.")
    endif()
    set(_therock_fmt_version "${CMAKE_MATCH_1}")

    set(fmt_DIR "${_therock_fmt_dist}"
        CACHE PATH "therock bundled fmt (v${_therock_fmt_version}) -- never the host's" FORCE)
    set(FMT_VERSION "${_therock_fmt_version}"
        CACHE STRING "fmt version (must match therock dist, see patches/009)" FORCE)
    message(STATUS "pre_hook: fmt_DIR forced to bundled fmt v${_therock_fmt_version} (patches/009)")
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
