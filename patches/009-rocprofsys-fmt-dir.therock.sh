#!/bin/sh
# patches/009-rocprofsys-fmt-dir.therock.sh  (rev 2: hardened)
#
# Slackware platform note: rocprofiler-systems' cmake/FmtLib.cmake calls
# find_package(fmt REQUIRED), which therock_subproject_dep_provider.cmake
# does not intercept (fmt is not in the routing table for this subproject,
# despite therock-fmt being listed in BUILD_DEPS). The search therefore
# escapes to the host system. On Slackware-current, /usr/lib64/cmake/fmt is
# fmt 12.2.0 while therock-spdlog and build/third-party/fmt/dist are fmt
# 11.1.3.
#
# What the mixed-ABI link actually looks like (corrected from rev 1):
# the prebuilt libspdlog.a (and TUs configured against the bundled dist)
# reference fmt::v11 symbols, but the escaped find hands the link line the
# host's /usr/lib64/libfmt.so.12.2 -- so ld.lld reports undefined
# fmt::v11::* symbols and helpfully suggests fmt::v12::* replacements.
# rev 1's comment had the direction inverted; the v11 references are what
# the *bundled* side emits, and the host v12 is the intruder.
#
# Root cause (confirmed in rocprofiler-systems_configure.log): the embedded
# profiler-hub clone runs profiler-hub/cmake/fmt.cmake at configure time,
# which probes find_package(fmt 11.2.0 QUIET). The bundled dist (11.1.3)
# fails the version floor, so the search escapes to the host system, and a
# successful config-mode find REWRITES fmt_DIR=/usr/lib64/cmake/fmt in the
# cache -- poisoning the later find_package(fmt REQUIRED) in FmtLib.cmake.
# Upstream CI never sees this because their images have no system fmt.
#
# Fix (rev 2 hardens rev 1 three ways):
#   1. fmt_DIR  AND fmt_ROOT are both forced to the superbuild's bundled
#      fmt dist. _ROOT is the belt to _DIR's suspenders: config-mode
#      searches honour <pkg>_ROOT even when <pkg>_DIR gets invalidated or
#      clobbered, so an escaped probe that resets fmt_DIR still lands on
#      the dist.
#   2. FMT_VERSION is forced to the dist's actual version (parsed at
#      runtime from the dist's config-version file, so this cannot drift
#      from the dist on a bundled-version bump). profiler-hub's
#      set(FMT_VERSION "11.2.0" CACHE STRING ...) is a plain (non-FORCE)
#      cache set and is a no-op when our value already exists.
#      CAVEAT: if profiler-hub's probe is a literal floor
#      (find_package(fmt 11.2.0) with a hardcoded number, not
#      ${FMT_VERSION}), this half is decorative -- but the _ROOT/_IGNORE
#      guards below still catch the escape, they just convert it from
#      silent clobber to loud failure. Check with:
#        grep -rn "find_package(fmt" <subproject-src> | head
#   3. CMAKE_IGNORE_PREFIX_PATH adds /usr and /usr/local for this
#      subproject's configure only (pre-hook scope). This closes the
#      escape hatch itself: a version-floor failure against the dist now
#      fails LOUDLY instead of reaching for the host. Requires CMake
#      >= 3.23 and affects config-mode finds only (module-mode finds
#      like Threads/Python3 are untouched).
#
# spdlog companion (rev 2, optional): the same link failure also showed
# an undefined spdlog::details::log_msg constructor -- the mirror-image
# disease for spdlog. If therock-spdlog's dist config is present, pin
# spdlog_DIR/spdlog_ROOT to it the same way. Skips loudly-but-gracefully
# if the dist layout doesn't match, so a therock refactor degrades to a
# warning rather than a build break.
#
# Post-flight check (after rocprofsys configures):
#   grep -E "fmt_DIR|FMT_VERSION|spdlog_DIR" \
#     build/profiler/rocprofiler-systems/build/CMakeCache.txt
#   -> expect fmt_DIR pointing at .../build/third-party/fmt/dist/lib/cmake/fmt
#      and FMT_VERSION matching the dist.
# The configure log should print:
#   "pre_hook: fmt pinned to bundled fmt vX.Y.Z (patches/009)"
# and should NOT print "Using system fmt".
# Ground truth is still the link line, not the cache: after rebuild,
#   grep -o "/usr/lib[^ ]*libfmt[^ ]*" build/logs/rocprofiler-systems_build.log
# must return nothing.
#
# Retirement triggers:
#   - upstream routes fmt through the dep provider for this subproject, or
#   - profiler-hub drops its fmt version pin (or lowers it below the
#     bundled version), or
#   - therock bumps the bundled fmt dist version (the version-parse below
#     follows automatically; only the probe-literal caveat matters).
# On any of these, retire the FMT_VERSION force FIRST (it is the most
# likely to go stale), then fmt_ROOT/_IGNORE, then fmt_DIR last.

set -e
_root="${SRC_CACHE:?}/therock-${VERSION}"
_f="${_root}/profiler/pre_hook_rocprofiler-systems.cmake"
_marker='# therock-fmt-pin'

# Idempotency: skip if the override is already present. Explicit if --
# the rev 1 "grep -q && { ...; exit 0; }" idiom is safe mid-script under
# set -e but bites if anyone reorders it to the last statement of the
# script (the && short-circuit would swallow the exit status).
if [ -f "$_f" ]; then
  if grep -q "$_marker" "$_f"; then
    echo "already patched: rocprofsys fmt pin (rev 2)"
    exit 0
  fi
fi

# Create the hook if upstream doesn't ship one for this subproject yet;
# the fmt block is self-contained either way. ml-libs/pre_hook_MIOpen.cmake
# exists upstream, so the pre-hook loading machinery does -- it just needs
# a correctly-named file in profiler/.
touch "$_f"

cat >> "$_f" <<'EOF'

# therock-fmt-pin
# Pin find_package(fmt) AND find_package(spdlog) to the superbuild's
# bundled dists, never the host system's (Slackware-current ships fmt
# 12.2 in /usr/lib64/cmake/fmt; the dist and libspdlog.a are v11).
# The dep provider does not intercept fmt/spdlog for this subproject even
# though therock-fmt and therock-spdlog are in BUILD_DEPS; letting the
# search escape mixes ABIs at link time.
#
# Defense in depth, outermost ring first:
#   CMAKE_IGNORE_PREFIX_PATH: config-mode search never sees /usr at all
#   fmt_ROOT:                 even a clobbered fmt_DIR re-roots on dist
#   fmt_DIR (FORCE):          cache starts (and restarts) on the dist
#   FMT_VERSION (FORCE):      profiler-hub's quiet probe stays satisfied

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

    # Ring 1: deny the host a vote. Config-mode only (module-mode finds
    # like Threads are unaffected); requires CMake >= 3.23.
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.23")
        list(APPEND CMAKE_IGNORE_PREFIX_PATH "/usr" "/usr/local")
    else()
        message(WARNING
            "pre_hook: CMake ${CMAKE_VERSION} < 3.23 -- "
            "CMAKE_IGNORE_PREFIX_PATH unavailable, relying on _ROOT/_DIR pins only. "
            "See patches/009.")
    endif()

    # Ring 2 and 3: pin the search root and the cache DIR.
    set(fmt_ROOT "${_therock_fmt_dist}"
        CACHE PATH "therock bundled fmt -- never the host's" FORCE)
    set(fmt_DIR "${_therock_fmt_dist}"
        CACHE PATH "therock bundled fmt (v${_therock_fmt_version}) -- never the host's" FORCE)

    # Ring 4: satisfy profiler-hub's quiet version probe with the dist's
    # own version so its find_package can never legitimately escape.
    # If profiler-hub hardcodes its floor as a literal rather than
    # ${FMT_VERSION}, this set is inert -- but rings 1-3 mean the failed
    # probe now fails loudly instead of silently grabbing /usr.
    set(FMT_VERSION "${_therock_fmt_version}"
        CACHE STRING "fmt version (must match therock dist, see patches/009)" FORCE)

    message(STATUS "pre_hook: fmt pinned to bundled fmt v${_therock_fmt_version} (patches/009)")
else()
    message(FATAL_ERROR
        "pre_hook: therock bundled fmt not found under "
        "${_therock_fmt_root} -- expected therock-fmt to be built first "
        "(BUILD_DEPS ordering broken?). See patches/009.")
endif()

# --- spdlog companion ----------------------------------------------------
# The same link failure showed an undefined spdlog::details::log_msg
# constructor (spdlog headers from one place, library from another).
# Same treatment: ROOT + DIR pinned to the therock-spdlog dist when it
# exists. Graceful skip: if therock rearranges the spdlog dist layout,
# warn loudly but do not break the configure -- fmt was the confirmed
# root cause, this is prophylaxis.
set(_therock_spdlog_dist "${_therock_fmt_root}/third-party/spdlog/dist/lib/cmake/spdlog")
if(EXISTS "${_therock_spdlog_dist}")
    set(spdlog_ROOT "${_therock_spdlog_dist}"
        CACHE PATH "therock bundled spdlog -- never the host's" FORCE)
    set(spdlog_DIR "${_therock_spdlog_dist}"
        CACHE PATH "therock bundled spdlog -- never the host's" FORCE)
    message(STATUS "pre_hook: spdlog pinned to bundled spdlog dist (patches/009)")
elseif(EXISTS "${_therock_fmt_root}/third-party/spdlog")
    message(WARNING
        "pre_hook: therock-spdlog present but no dist config at "
        "${_therock_spdlog_dist} -- spdlog not pinned. If rocprof-sys-avail "
        "still fails on spdlog:: symbols, check this. See patches/009.")
endif()
EOF

# Verification: the marker must survive the heredoc append.
if ! grep -q "$_marker" "$_f"; then
  echo "*** ERROR: injection failed into $_f" >&2
  exit 1
fi
echo "patched: rocprofsys fmt/spdlog pins -> bundled dists (rev 2)"
