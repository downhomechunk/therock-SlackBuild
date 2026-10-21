#!/bin/sh
# patches/003-cstdint-rocroller.rocm-libraries.sh
#
# libstdc++ 15+ (Slackware-current ships 16) no longer pulls <cstdint>
# in transitively via <vector>/<string>. amdisa_structures.h uses
# uint32_t/uint64_t unqualified without including <cstdint>, so it
# fails to parse. Upstream-correct fix, not a workaround.
#
# Target tree named by suffix: rocm-libraries
_root="${SRC_CACHE:?}/therock-${VERSION}/rocm-libraries"
_f="$_root/shared/rocroller/GPUArchitectureGenerator/isa_spec_manager/amdisa_structures.h"

[ -f "$_f" ] || { echo "*** ERROR: $_f not found." >&2; exit 1; }

if grep -q '^#include <cstdint>' "$_f"; then
  echo "=> already patched: $(basename "$_f")"
else
  perl -pi -e 'print "#include <cstdint>\n" if $. == 1' "$_f"
  echo "=> patched: $(basename "$_f")"
fi

grep -q '^#include <cstdint>' "$_f" || {
  echo "*** ERROR: cstdint include did not land in $_f" >&2
  exit 1
}
