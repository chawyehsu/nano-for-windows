# nano-for-windows Release

The automation that watches GNU nano upstream, re-publishes conda packages as GitHub Releases, and tracks out-of-date versions as issues.

## Language

**Upstream nano release**:
A GNU nano version announced on nano-editor.org, parsed from the NEWS file by `check-upstream.ps1`.

**Conda package**:
A nano-for-windows package published on Anaconda.org, one per platform (win-64, win-arm64), identified by a version and an optional conda build number.
_Avoid_: conda release

**GitHub release**:
A nano-for-windows release on GitHub Releases, tagged `v<version>`, carrying the re-uploaded conda and zip assets. The tag may include a conda build suffix (e.g. `v8.2-1`).

**Release-tracking issue**:
An issue labeled `upstream-release`, titled `GNU nano <version> released upstream`, opened by `check-upstream.ps1` when upstream is ahead of GitHub, requesting a new release.
_Avoid_: upstream issue, nag issue

**Retire**:
To close a release-tracking issue — after commenting a reference to the GitHub release — once the matching version has shipped as a GitHub release.
_Avoid_: close out, resolve

**Patch set**:
The win32 patches under `patches/` that make GNU nano build and behave on Windows, applied in filename order. A set lives either in `latest/`, the working set, or in a directory named for the upstream version it targets. Filenames denote patch lineage, not position, so the same `<prefix>-<slug>.patch` name refers to the same patch across sets.

**Working patch set**:
The patch set in `patches/latest/`, which names no version of its own: the version it applies to is whatever it was last renewed for.
_Avoid_: latest patches, current patches

**Patch renew**:
The act of making the working patch set apply to a newly released upstream version: snapshot it, then repair its patches against the upstream diff until a clean apply and build pass. Never adds patches.
_Avoid_: patch update, patch refresh

**Snapshot**:
A verbatim copy of the working patch set's files into `patches/<version>/`, frozen at the moment a newer version is being renewed for. The directory name is the version.
_Avoid_: archive, freeze

**Build-verified**:
A patch set is build-verified when it has applied cleanly to its target version's sources and `pixi run build` has succeeded. This is the bar a patch renew must clear.
