# therock — The HIP Environment and ROCm Kit for Slackware-current

## Overview

This builds AMD's ROCm platform for Slackware-current via TheRock, AMD's open
source build and release system for HIP and ROCm. Since ROCm 7.14, ROCm is
built and released through TheRock; this script wraps that build into a proper
Slackware package installing under `/opt/rocm`.

- - -
## ⚠️ The Build Is Brutal — Plan Accordingly

Let's be blunt: building ROCm from source is a **massive undertaking**. We're
talking hours to days of compile time depending on your hardware, and the disk
requirements are genuinely punishing.

**Real-world measurements from a 7800X3D build:**


|Component|Size|
|-|-|
|Source cache (`/var/cache/therock/therock-10.1`)|**97.6 GiB**|
|ccache cache|**3.0 GiB**|
|Build tree (peak)|~120–150 GiB total|
|Installed payload (`/opt/rocm`)|~25–30 GiB|

**Hardware recommendations:**


|Resource|Recommendation|
|-|-|
|CPU|Throttle your parallelism. On a 7800X3D we reduced `JOBS` from the default 8 to 4–6 to avoid memory exhaustion|
|RAM|32 GB physical minimum. We used **32 GB zram swap** just to get through the build without OOM kills|
|Disk|Reserve at least **200 GB** in `/var/cache` and build locations before starting|
|Time|Set aside a full day or weekend. Don't start Friday evening unless you enjoy watching `ninja` crawl at 3 AM|

This is not for the impatient, the under-resourced, or anyone without a backup
plan. If you're wondering whether you should do this, you probably already know
the answer.

- - -
## IMPORTANT: Network Access Required

This script **requires network access while running**. TheRock downloads
component sources, toolchains, and dependency archives from the internet at
build time.  Think on how you feel about this before running.

Sources are cached persistently in `$SRC_CACHE` (default `/var/cache/therock`)
so subsequent builds and version bumps fetch only deltas. However, initial
builds download *everything*.

- - -
## Requirements

### Hard Dependencies

- `git-lfs` — **mandatory**. After installing git-lfs, run `git lfs install`
  once as the user running the build (one-time global git config setup)
- Build tools: `cmake`, `ninja`, `patchelf`, `python3`, `ctest`
- Standard Slackware development toolchain

### Optional Acceleration

- `ccache` — Rebuilds and version bumps benefit significantly from ccache
  (requires ccache from SBo). The cache persists alongside the source cache.
  Note: first builds are cache-cold; benefits appear from the second build
  onward.

Usage:

```sh
USE_CCACHE=yes ./therock.SlackBuild
```
- - -
## Usage

  Default build targets gfx1201 (RDNA4, Navi 48: RX 9070 / 9070 XT /
  9070 GRE and Radeon AI PRO R9700).  To target an exact architecture:

To target an exact architecture:

```sh
GPU_FAMILIES=gfx1201 ./therock.SlackBuild   # 9070 / 9070 XT
GPU_FAMILIES=gfx1200 ./therock.SlackBuild   # 9060 / 9060 XT
```
Multiple families are semicolon-separated and quoted:

```sh
GPU_FAMILIES="gfx103X-dgpu;gfx110X-all" ./therock.SlackBuild
```
See <https://rocm.docs.amd.com/en/latest/reference/gpu-specs.html> for
supported architectures.

- - -
## Build Environment Notes

The TheRock tag tarball (`TheRock-$VERSION.tar.gz`) is only the bootstrap; the
build system fetches the actual component sources itself. Full builds take
hours to days depending on hardware. Plan disk accordingly: the source cache
and build tree together can consume tens of gigabytes.

The virtual environment used for TheRock's Python tooling is created inside the
persistent source cache and never touches the system Python. Requirements are
installed from the tag's own `requirements.txt` so version pins always match the
tree being built.

Rebuilding the same version is safe: upstream fetching resets component trees
to pristine state. **Do NOT hand-edit sources in the cache expecting edits to
survive a re-run or version bump — they will not.** Carry patches as a separate
step after fetch.

- - -
## Runtime Permissions and Verification

On stock Slackware-current both `/dev/kfd` and `/dev/dri/renderD*` are created
world read/write (0666):

```
crw-rw-rw- 1 root video 226, 128 ... /dev/dri/renderD128
crw-rw-rw- 1 root video  508,   0 ... /dev/kfd
```
No group membership is required for GPU compute access. Expect one renderD node
per display adapter — CPUs with integrated graphics (AMD 7000/9000 series, most
modern Intel) add a node.

If your system is hardened and these nodes are 0660:

```sh
usermod -aG video yourusername
```
Then log out and back in. Slackware has no 'render' group; for a dedicated
compute group instead of video:

```sh
groupadd -r render
echo 'KERNEL=="kfd", GROUP="render", MODE="0660"' > /etc/udev/rules.d/70-kfd.rules
udevadm trigger --name-match=kfd
usermod -aG render yourusername
```
Remember: group changes do not affect running sessions. Log out and back in
before retesting.

- - -
**Credits**

This project stands on the shoulders of Condor and his ROCm-for-Slackware build
scripts.  His pre-built packages have served me well for the past few years.

Additionally, thanks to the upstream TheRock project and AMD for making ROCm's
build process a single coherent, buildable entity rather than a pile of
independent shell scripts.

- - -
*For the love of open source and the pain of recompiling everything.*

