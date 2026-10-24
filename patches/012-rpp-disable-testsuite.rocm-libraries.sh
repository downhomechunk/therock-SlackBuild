#!/bin/sh
#
# 012-rpp-disable-testsuite.rocm-libraries.sh
#
# Target tree: rocm-libraries (routing suffix names it; script self-routes)
# File touched: projects/rpp/CMakeLists.txt
#
# WHY
# ---
# rpp's HIP test suite cannot build in-tree, deterministically, on this
# configuration. The suite sources do:
#
#     #include "rpp.h"
#
# but rpp.h is only placed in <rpp-stage>/include during rpp's STAGE step,
# which ninja runs AFTER the build step that compiles the test suite. The
# compile line even carries -isystem .../cv-libs/rpp/stage/include, and the
# header still isn't there yet. Chicken-and-egg, unfixable by include paths.
#
# Observed failure (every run):
#   FAILED: utilities/test_suite/HIP/CMakeFiles/Tensor_misc_hip.dir/...
#   .../rpp_test_suite_misc.h:32:10: fatal error: 'rpp.h' file not found
#   FAILED: utilities/test_suite/HIP/CMakeFiles/Tensor_image_hip.dir/...
#   ninja: build stopped: subcommand failed.
#
# Impact: rpp's build stamp never gets written, which is a node in the
# OUTER ninja graph, so the whole superbuild stops. librpp.so itself builds
# and stages perfectly well (librpp.so.3.2.0). The suite is not shipped.
#
# Line 413 is an UNGATED add_subdirectory(): there is no option to flip, so
# this is text surgery rather than a -D flag. Upstream-ticket-worthy.
#
# WHAT
# ----
# Comments out two lines, anchored on content (never on line numbers):
#   add_subdirectory(utilities/test_suite)          -> build it?  no.
#   install(DIRECTORY .../utilities/test_suite/ ...) -> ship its sources? no.
#
# The second is not strictly required for the build to succeed; it just
# avoids shipping test data for a suite that cannot compile. Absence of
# that line is therefore a warning, not a failure.
#
# SED NOTES (learned the hard way)
# --------------------------------
# * Patterns are single-quoted so bash never touches them; the only special
#   character sed sees is '&', which expands to the ENTIRE matched line.
#   Replacement '# &' therefore comments out the whole line, verbatim,
#   including any ${CMAKE_...} variables -- no escaping games, no risk of
#   commenting only part of a line.
# * No trailing '$' anchors: a stray trailing space upstream would silently
#   defeat the match. Prefix anchors only.
# * No hardcoded line numbers: upstream shifting one line must not turn this
#   script into a no-op that still reports success.
# * grep, not rg: rg is not a declared build dependency and this script must
#   run on a bare SBo build host.
#
# IDEMPOTENCY
# -----------
# Guard detects the post-patch (commented) form, so re-running is a no-op.
# Safe to run on every build against a warm cache.
#
# COST
# ----
# Touching this file invalidates rpp's configure fingerprint, so rpp
# reconfigures and rebuilds once -- without the test suite. Warm ccache eats
# most of it. After that, rpp's stamp is satisfiable and the outer graph
# proceeds.

set -e

# SlackBuild exports SRC_CACHE and VERSION before invoking patches.
# ':?' makes a missing variable a loud failure, not a silent path of "/therock-/".
_root="${SRC_CACHE:?SRC_CACHE not set}/therock-${VERSION:?VERSION not set}/rocm-libraries"
_f="$_root/projects/rpp/CMakeLists.txt"

[ -f "$_f" ] || {
  echo "*** ERROR: rpp CMakeLists.txt not found at $_f" >&2
  echo "***        has the rocm-libraries layout changed?" >&2
  exit 1
}

# --------------------------------------------------------------------------
# Guard: already patched?
# --------------------------------------------------------------------------
if grep -q '^# add_subdirectory(utilities/test_suite)' "$_f"; then
  echo "=> already patched: rpp test suite disabled"
  exit 0
fi

# --------------------------------------------------------------------------
# Verify expected shape before touching anything. Die loudly if upstream
# restructured -- a silent no-op here means a 40-hour build dying at rpp
# again, which is precisely what this script exists to prevent.
# --------------------------------------------------------------------------
grep -q '^add_subdirectory(utilities/test_suite)' "$_f" || {
  echo "*** ERROR: expected line not found in $_f:" >&2
  echo "***          add_subdirectory(utilities/test_suite)" >&2
  echo "***        rpp's CMakeLists changed shape; inspect manually." >&2
  exit 1
}

_have_install=no
grep -q '^install(DIRECTORY .*utilities/test_suite/' "$_f" && _have_install=yes

# --------------------------------------------------------------------------
# Apply. '&' expands to the full matched line; '# ' comments it out whole.
# --------------------------------------------------------------------------
sed -i 's|^add_subdirectory(utilities/test_suite)|# &|' "$_f"

if [ "$_have_install" = yes ]; then
  sed -i 's|^install(DIRECTORY .*utilities/test_suite/|# &|' "$_f"
else
  echo "=> note: test_suite install(DIRECTORY ...) line not present; skipping"
fi

# --------------------------------------------------------------------------
# Verify the patch actually took. Never trust sed's exit status alone.
# --------------------------------------------------------------------------
grep -q '^# add_subdirectory(utilities/test_suite)' "$_f" || {
  echo "*** ERROR: verification failed -- add_subdirectory not commented out" >&2
  exit 1
}

if [ "$_have_install" = yes ]; then
  grep -q '^# install(DIRECTORY .*utilities/test_suite/' "$_f" || {
    echo "*** ERROR: verification failed -- install(DIRECTORY ...) not commented out" >&2
    exit 1
  }
fi

echo "=> rpp test suite disabled (build + install)"
